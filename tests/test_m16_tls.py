import socket
import ssl
import subprocess
import tempfile
import threading

from harness import SHELL_READY, Vm
from test_m11_net import run
from test_m13_tcp import serve_once


def serve_tls(handle):
    """A TLS 1.3 server on the host with a throwaway self-signed certificate,
    running `handle` on each connection."""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt",
                        "ec_paramgen_curve:prime256v1", "-nodes", "-subj", "/CN=vitre.test",
                        "-keyout", f"{tmp}/key.pem", "-out", f"{tmp}/cert.pem"],
                       check=True, capture_output=True)
        ctx.load_cert_chain(f"{tmp}/cert.pem", f"{tmp}/key.pem")
    sock = socket.create_server(("127.0.0.1", 0))

    def loop():
        while True:
            conn = sock.accept()[0]
            conn.settimeout(10)
            try:
                with ctx.wrap_socket(conn, server_side=True) as tls:
                    handle(tls)
            except (OSError, ssl.SSLError):
                pass

    threading.Thread(target=loop, daemon=True).start()
    return sock.getsockname()[1]


def test_tls_completes_the_handshake():
    accepted = threading.Event()
    port = serve_tls(lambda tls: accepted.set())
    with Vm("m16_hello", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tls 10.0.2.2 {port}", r"\[tls\] handshake done")
    assert accepted.wait(5), "the server did not accept our Finished"


def test_get_over_https():
    def answer(tls):
        request = b""
        while b"\r\n\r\n" not in request:
            request += tls.recv(1024)
        assert request.startswith(b"GET /secret HTTP/1.0\r\n")
        tls.sendall(b"HTTP/1.0 200 OK\r\n\r\n" + b"sealed " * 1000 + b"end")

    port = serve_tls(answer)
    with Vm("m16_get", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"get https://10.0.2.2:{port}/secret",
            r"sealed end\s+\[http\] over TLS, certificate NOT verified, 7022 bytes")


def test_browse_https_keeps_the_scheme():
    pages = {b"/": b"<title>Safe</title><a href=next>n</a>", b"/next": b"<title>Next</title>"}

    def answer(tls):
        request = b""
        while b"\r\n\r\n" not in request:
            request += tls.recv(1024)
        tls.sendall(b"HTTP/1.0 200 OK\r\n\r\n" + pages[request.split()[1]])

    port = serve_tls(answer)
    with Vm("m16_browse", net=True) as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("browse\n")
        vm.wait_screen(r"Vitre browser")
        vm.sendkeys(f"ghttps://10.0.2.2:{port}/\n")
        vm.wait_screen(r"^ Safe .*certificate UNVERIFIED")
        vm.sendkeys("1\n")
        vm.wait_screen(r"^ Next[\s\S]*https://10\.0\.2\.2:\d+/next")


def test_tls_refuses_a_plain_server():
    port = serve_once(b"HTTP/1.0 200 OK\r\n\r\nnot tls")
    with Vm("m16_plain", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tls 10.0.2.2 {port}", r"\[tls\] handshake failed")
