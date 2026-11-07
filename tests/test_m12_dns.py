from harness import SHELL_READY, Vm
from test_m11_net import run


def test_dhcp_lease_at_boot():
    with Vm("m12_dhcp", net=True) as vm:
        vm.wait_for(r"\[dhcp\] lease 10\.0\.2\.15, gateway 10\.0\.2\.2, dns 10\.0\.2\.3")
        vm.wait_for(SHELL_READY)
        run(vm, "dhcp", r"\[dhcp\] lease 10\.0\.2\.15")
