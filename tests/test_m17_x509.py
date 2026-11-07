import subprocess
import tempfile

from harness import SHELL_READY, Vm
from test_m15_crypto import QWERTY, check


def der(data, at=0):
    """The tag, content and end of the DER element at `at`."""
    tag, size, at = data[at], data[at + 1], at + 2
    if size & 0x80:
        count = size & 0x7f
        size, at = int.from_bytes(data[at:at + count], "big"), at + count
    return tag, data[at:at + size], at + size


def children(data):
    at, out = 0, []
    while at < len(data):
        tag, content, at = der(data, at)
        out.append((tag, content))
    return out


def make_cert(*args):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt",
                        "ec_paramgen_curve:prime256v1", "-nodes", "-subj", "/CN=v",
                        "-keyout", f"{tmp}/k.pem", "-out", f"{tmp}/c.der", "-outform", "DER",
                        "-days", "1", *args], check=True, capture_output=True)
        return open(f"{tmp}/c.der", "rb").read()


def expected(cert):
    tbs, alg, sig = children(der(cert)[1])
    fields = children(tbs[1])
    key = children(fields[6][1])[1][1][2:]
    r, s = children(der(sig[1][1:])[1])
    algs = {bytes.fromhex("2a8648ce3d040302"): 1, bytes.fromhex("2a8648ce3d040303"): 2}
    return (bytes([algs[der(alg[1])[1]], 1]) + key
            + r[1].lstrip(b"\0").rjust(32, b"\0") + s[1].lstrip(b"\0").rjust(32, b"\0")).hex()


def test_x509_reads_a_p256_certificate():
    certs = [make_cert(), make_cert("-sha384", "-addext", "subjectAltName=IP:10.0.2.2")]
    with Vm("m17_x509", cmdline=QWERTY) as vm:
        vm.wait_for(SHELL_READY)
        for cert in certs:
            check(vm, f"x509 {cert.hex()}", expected(cert))
        check(vm, f"x509 {certs[0][:-1].hex()}", "")


def test_x509_matches_the_host_name():
    cert = make_cert("-addext", "subjectAltName=DNS:vitre.test,DNS:*.example.test,IP:10.0.2.2").hex()
    cases = {"vitre.test": "01", "VITRE.Test": "01", "a.example.test": "01",
             "example.test": "00", "a.b.example.test": "00", "vitre.tes": "00",
             "10.0.2.2": "01", "10.0.2.3": "00"}
    with Vm("m17_x509host", cmdline=QWERTY) as vm:
        vm.wait_for(SHELL_READY)
        for host, want in cases.items():
            check(vm, f"x509host {cert} {host.encode().hex()}", want)
        check(vm, f"x509host {make_cert().hex()} {b'v'.hex()}", "00")
        tld = make_cert("-addext", "subjectAltName=DNS:*.test").hex()
        check(vm, f"x509host {tld} {b'a.test'.hex()}", "00")
