import os
import socket
import ssl
import subprocess
import tempfile
import threading

from harness import SHELL_READY, Vm
from test_m11_net import run

TMP = tempfile.mkdtemp()


def openssl(*args):
    subprocess.run(["openssl", *args], check=True, capture_output=True, cwd=TMP)


def ca(name):
    openssl("req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
            "-nodes", "-subj", f"/CN={name}", "-keyout", f"{name}.key", "-out", f"{name}.pem",
            "-addext", "basicConstraints=critical,CA:TRUE")
    return name


def issue(name, issuer, ext):
    with open(os.path.join(TMP, f"{name}.ext"), "w") as f:
        f.write(ext)
    openssl("req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
            "-nodes", "-subj", f"/CN={name}", "-keyout", f"{name}.key", "-out", f"{name}.csr")
    openssl("x509", "-req", "-in", f"{name}.csr", "-CA", f"{issuer}.pem", "-CAkey", f"{issuer}.key",
            "-CAcreateserial", "-days", "1", "-sha256", "-extfile", f"{name}.ext", "-out", f"{name}.pem")
    return name


def key_hex(name):
    der = subprocess.run(["openssl", "ec", "-in", f"{name}.key", "-pubout", "-outform", "DER"],
                         check=True, capture_output=True, cwd=TMP).stdout
    return der[-64:].hex()


def serve(leaf, *issuers):
    chain = os.path.join(TMP, f"{leaf}.chain")
    with open(chain, "w") as out:
        for name in (leaf, *issuers):
            out.write(open(os.path.join(TMP, f"{name}.pem")).read())
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_3
    ctx.load_cert_chain(chain, os.path.join(TMP, f"{leaf}.key"))
    sock = socket.create_server(("127.0.0.1", 0))

    def loop():
        while True:
            conn = sock.accept()[0]
            try:
                with ctx.wrap_socket(conn, server_side=True):
                    pass
            except (OSError, ssl.SSLError):
                pass

    threading.Thread(target=loop, daemon=True).start()
    return sock.getsockname()[1]


SERVER = "subjectAltName=IP:10.0.2.2\nbasicConstraints=CA:FALSE\n"


def test_tls_verifies_the_chain():
    root, other = ca("root"), ca("other")
    good = serve(issue("good", root, SERVER), root)
    stranger = serve(issue("stranger", other, SERVER), other)
    fake_ca = issue("fake", root, "basicConstraints=CA:FALSE\n")
    forged = serve(issue("forged", fake_ca, SERVER), fake_ca, root)
    with Vm("m17_chain", net=True, cmdline="kbd=qwerty") as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tls 10.0.2.2 {good}", r"the chain is NOT verified")
        run(vm, f"trust {key_hex(root)}", r"trusted keys: 1")
        run(vm, f"tls 10.0.2.2 {good}", r"certificate verified")
        run(vm, f"tls 10.0.2.2 {stranger}", r"the chain is NOT verified")
        run(vm, f"tls 10.0.2.2 {forged}", r"the chain is NOT verified")
