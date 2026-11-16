"""호스트 → 게스트 역방향 중계.

호스트에서 연결을 기다리면 Windows 방화벽 허용 알림이 사용자 화면에 뜬다.
그래서 호스트는 게스트 쪽으로 '나가는' 연결만 만들고, 그 연결을 호스트의
가상 폰 adb 포트(127.0.0.1:<emulator-port>)에 이어 준다.
연결이 끊기면 다시 건다. 한 번에 한 쌍만 잇는다(adb 연결은 소켓 하나).

사용: python host_relay.py <guest-ip> <guest-port> <emulator-adb-port> <stop-file>
"""
import os
import socket
import sys
import threading
import time


def pipe(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def main() -> None:
    guest, guest_port, emu_port, stop_file = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    while not os.path.exists(stop_file):
        try:
            g = socket.create_connection((guest, guest_port), timeout=3)
        except OSError:
            time.sleep(1)
            continue
        try:
            e = socket.create_connection(("127.0.0.1", emu_port), timeout=3)
        except OSError:
            g.close()
            time.sleep(1)
            continue
        for s in (g, e):
            s.settimeout(None)
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        print(time.strftime("%H:%M:%S"), "paired", flush=True)
        threads = [threading.Thread(target=pipe, args=(g, e), daemon=True),
                   threading.Thread(target=pipe, args=(e, g), daemon=True)]
        for t in threads:
            t.start()
        while any(t.is_alive() for t in threads) and not os.path.exists(stop_file):
            time.sleep(0.2)
        g.close()
        e.close()
        print(time.strftime("%H:%M:%S"), "closed", flush=True)


if __name__ == "__main__":
    main()
