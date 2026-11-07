import socket
import threading

from harness import SHELL_READY, TestFailure, Vm
from test_m11_net import run


def serve_once(reply, seen=None):
    """A one-shot TCP server on the host, which the guest reaches as 10.0.2.2.
    It reads the request into `seen`, answers with `reply` and closes."""
    sock = socket.create_server(("127.0.0.1", 0))

    def answer():
        with sock, sock.accept()[0] as conn:
            conn.settimeout(5)
            data = b""
            while b"\r\n\r\n" not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            if seen is not None:
                seen.append(data)
            conn.sendall(reply)

    threading.Thread(target=answer, daemon=True).start()
    return sock.getsockname()[1]


def test_tcp_connects():
    port = serve_once(b"")
    with Vm("m13_tcp", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tcp 10.0.2.2 {port}", rf"\[tcp\] connected to 10\.0\.2\.2:{port}")
        run(vm, "tcp 10.0.2.2 1", r"\[tcp\] no connection to 10\.0\.2\.2: reset")
        run(vm, "tcp 10.0.2.2", r"usage: tcp")


def test_get_fetches_a_page():
    body = b"<title>Vitre test</title>\n" + b"".join(b"line %04d\n" % i for i in range(600))
    reply = b"HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n" + body
    seen = []
    port = serve_once(reply, seen)
    with Vm("m13_get", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"get http://10.0.2.2:{port}/index.html",
            rf"HTTP/1\.0 200 OK[\s\S]*<title>Vitre test</title>[\s\S]*line 0599\s+\[http\] {len(reply)} bytes")
    if not seen or not seen[0].startswith(b"GET /index.html HTTP/1.0\r\nHost: 10.0.2.2\r\n"):
        raise TestFailure(f"unexpected request: {seen!r}")
