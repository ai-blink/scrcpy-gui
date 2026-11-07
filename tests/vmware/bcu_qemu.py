"""Headless QMP/QGA management. This module has no host desktop input backend."""
import argparse
import base64
import json
import pathlib
import socket
import subprocess
import time
import uuid


class Channel:
    def __init__(self, port, qmp=False, timeout=20):
        self.sock = socket.create_connection(('127.0.0.1', port), timeout)
        self.sock.settimeout(timeout)
        self.stream = self.sock.makefile('rwb', buffering=0)
        self.qmp = qmp
        self.sequence = 0
        if qmp:
            if 'QMP' not in self.read():
                raise RuntimeError('Not a QMP endpoint')
            self.call('qmp_capabilities')

    def read(self):
        line = self.stream.readline(4 * 1024 * 1024)
        if not line:
            raise RuntimeError('Guest channel closed')
        return json.loads(line.lstrip(b'\xff'))

    def call(self, command, arguments=None):
        self.sequence += 1
        request = {'execute': command}
        if arguments is not None:
            request['arguments'] = arguments
        if self.qmp:
            request['id'] = self.sequence
        self.stream.write(json.dumps(request).encode() + b'\n')
        while True:
            response = self.read()
            if 'event' in response:
                continue
            if self.qmp and response.get('id') != self.sequence:
                continue
            if 'error' in response:
                raise RuntimeError(response['error'])
            if 'return' in response:
                return response['return']

    def close(self):
        self.stream.close()
        self.sock.close()


def execute(agent, code, timeout=60):
    encoded = base64.b64encode(code.encode('utf-16le')).decode()
    result = agent.call('guest-exec', {'path': 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
                                     'arg': ['-NoProfile', '-EncodedCommand', encoded], 'capture-output': True})
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = agent.call('guest-exec-status', {'pid': result['pid']})
        if status.get('exited'):
            output = base64.b64decode(status.get('out-data', '')).decode('utf-8-sig', errors='replace')
            error = base64.b64decode(status.get('err-data', '')).decode('utf-8-sig', errors='replace')
            if status.get('exitcode') != 0:
                raise RuntimeError({'guestExit': status.get('exitcode'), 'error': error})
            return output
        time.sleep(.2)
    raise TimeoutError('Guest management command timed out; no host fallback')


def read_file(agent, path):
    handle = agent.call('guest-file-open', {'path': path, 'mode': 'r'})
    data = bytearray()
    try:
        while True:
            chunk = agent.call('guest-file-read', {'handle': handle, 'count': 16384})
            data.extend(base64.b64decode(chunk.get('buf-b64', '')))
            if len(data) > 16 * 1024 * 1024:
                raise RuntimeError('Guest artifact exceeded bounded size')
            if chunk.get('eof'):
                return bytes(data)
    finally:
        agent.call('guest-file-close', {'handle': handle})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['start', 'status', 'preflight', 'collect-staged', 'shutdown'])
    parser.add_argument('--config', required=True, type=pathlib.Path)
    parser.add_argument('--out', type=pathlib.Path)
    parser.add_argument('--run-id', type=uuid.UUID)
    parser.add_argument('--expected-count', type=int, choices=[20,600], default=20)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8-sig'))
    if args.operation == 'start':
        lab = args.config.resolve().parent
        with (lab / 'stdout.log').open('wb') as stdout, (lab / 'stderr.log').open('wb') as stderr:
            child = subprocess.Popen([config['executable'], *config['arguments']], cwd=lab, stdin=subprocess.DEVNULL,
                                     stdout=stdout, stderr=stderr, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        time.sleep(2)
        if child.poll() is not None:
            raise RuntimeError({'exit': child.returncode, 'stderr': (lab / 'stderr.log').read_text(errors='replace')})
        (lab / 'session.json').write_text(json.dumps({'pid': child.pid, 'config': str(args.config.resolve()), 'host_input_fallback': False}), encoding='utf-8')
        print(json.dumps({'pid': child.pid, 'display': 'none', 'network': 'none'}))
        return
    qmp = Channel(config['qmp_port'], qmp=True)
    agent = None
    try:
        if qmp.call('query-name').get('name') != config['name']:
            raise RuntimeError('QMP VM name mismatch')
        if uuid.UUID(qmp.call('query-uuid')['UUID']) != uuid.UUID(config['uuid']):
            raise RuntimeError('QMP VM UUID mismatch')
        if args.operation == 'shutdown':
            qmp.call('system_powerdown')
            return
        if args.operation == 'status':
            print(json.dumps(qmp.call('query-status')))
            return
        if args.out is None:
            parser.error('--out is required for preflight')
        args.out.mkdir(parents=True, exist_ok=False)
        agent = Channel(config['agent_port'], timeout=30)
        agent.call('guest-ping')
        if args.operation == 'collect-staged':
            if args.run_id is None:
                parser.error('--run-id is required for collect-staged')
            run_id = args.run_id.hex
        else:
            actual = execute(agent, '(Get-CimInstance Win32_ComputerSystemProduct).UUID').strip()
            if uuid.UUID(actual) != uuid.UUID(config['uuid']):
                raise RuntimeError('Guest WMI UUID mismatch')
            run_id = uuid.uuid4().hex
            execute(agent, "& 'C:\\BackgroundLab\\payload\\tools\\Guest-LaunchPreflight.ps1' -RunId " + run_id + ' -ExpectedUuid ' + config['uuid'])
        deadline = time.monotonic() + 600
        summary_path = 'C:\\BackgroundLab\\preflight\\' + run_id + '\\summary.json'
        while time.monotonic() < deadline:
            try:
                data = read_file(agent, summary_path)
                summary = json.loads(data.decode('utf-8-sig'))
            except RuntimeError:
                time.sleep(1)
                continue
            if summary.get('runId') != run_id or uuid.UUID(summary['actualUuid']) != uuid.UUID(config['uuid']):
                raise RuntimeError('Result identity mismatch')
            (args.out / 'summary.json').write_bytes(data)
            (args.out / 'actions.ndjson').write_bytes(read_file(agent, 'C:\\BackgroundLab\\preflight\\' + run_id + '\\actions.ndjson'))
            print(json.dumps(summary))
            if summary.get('executed') != args.expected_count or summary.get('pass') != args.expected_count:
                raise SystemExit(1)
            return
        raise TimeoutError('QEMU preflight did not complete')
    finally:
        if agent:
            agent.close()
        qmp.close()


if __name__ == '__main__':
    main()
