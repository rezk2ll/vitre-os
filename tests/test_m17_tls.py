from harness import SHELL_READY, Vm
from test_m11_net import run
from test_m16_tls import serve_tls


def test_tls_checks_the_key_and_the_name():
    nameless = serve_tls(lambda tls: None)
    named = serve_tls(lambda tls: None, "-addext", "subjectAltName=DNS:*.example.test,IP:10.0.2.2")
    with Vm("m17_proof", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tls 10.0.2.2 {nameless}", r"holds its certificate's key, but the certificate does NOT name it")
        run(vm, f"tls 10.0.2.2 {named}", r"the certificate names the server, which holds its key")
