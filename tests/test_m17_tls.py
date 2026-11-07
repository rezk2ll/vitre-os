from harness import SHELL_READY, Vm
from test_m11_net import run
from test_m16_tls import serve_tls


def test_tls_checks_certificate_verify():
    port = serve_tls(lambda tls: None)
    with Vm("m17_proof", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"tls 10.0.2.2 {port}", r"server holds its certificate's key")
