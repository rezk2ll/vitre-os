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


def test_tls_decrypts_with_the_handshake_keys():
    port = serve_tls(lambda tls: None)
    with Vm("m16_hello", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tls 10.0.2.2 {port}", r"\[tls\] handshake keys work")


def test_tls_refuses_a_plain_server():
    port = serve_once(b"HTTP/1.0 200 OK\r\n\r\nnot tls")
    with Vm("m16_plain", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tls 10.0.2.2 {port}", r"\[tls\] handshake failed")
