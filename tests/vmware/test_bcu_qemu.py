import json
import socket
import threading
import unittest
from bcu_qemu import Channel


class ProtocolTests(unittest.TestCase):
    def test_qmp_handshake_events_ids_and_error(self):
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        failures = []

        def serve():
            try:
                sock, _ = listener.accept()
                with sock, sock.makefile('rwb', buffering=0) as stream:
                    stream.write(b'{"QMP":{"version":{},"capabilities":[]}}\n')
                    for index in range(3):
                        request = json.loads(stream.readline())
                        stream.write(b'{"event":"EXAMPLE"}\n')
                        stream.write(json.dumps({'return': {'ignored': True}, 'id': -1}).encode()+b'\n')
                        response = {'id': request['id']}
                        if index == 2:
                            response['error'] = {'class': 'GenericError', 'desc': 'intentional'}
                        else:
                            response['return'] = {} if index == 0 else {'status': 'paused'}
                        stream.write(json.dumps(response).encode()+b'\n')
            except Exception as error:
                failures.append(error)
            finally:
                listener.close()

        thread = threading.Thread(target=serve)
        thread.start()
        channel = Channel(listener.getsockname()[1], qmp=True, timeout=2)
        try:
            self.assertEqual(channel.call('query-status'), {'status': 'paused'})
            with self.assertRaisesRegex(RuntimeError, 'intentional'):
                channel.call('unsupported')
        finally:
            channel.close()
            thread.join(3)
        self.assertFalse(thread.is_alive())
        self.assertFalse(failures)


if __name__ == '__main__':
    unittest.main()
