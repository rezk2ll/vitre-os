import socket
import threading

from harness import SHELL_READY, Vm
from test_m11_net import run


def serve_once(reply):
    """A one-shot TCP server on the host, which the guest reaches as 10.0.2.2."""
    sock = socket.create_server(("127.0.0.1", 0))

    def answer():
        with sock, sock.accept()[0] as conn:
            conn.sendall(reply)

    threading.Thread(target=answer, daemon=True).start()
    return sock.getsockname()[1]


def test_tcp_connects():
    port = serve_once(b"")
    with Vm("m13_tcp", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tcp 10.0.2.2 {port}", rf"\[tcp\] connected to 10\.0\.2\.2:{port}")
        run(vm, "tcp 10.0.2.2 1", r"\[tcp\] no connection to 10\.0\.2\.2")
        run(vm, "tcp 10.0.2.2", r"usage: tcp")
