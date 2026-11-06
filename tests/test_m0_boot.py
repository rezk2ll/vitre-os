from harness import Vm


def test_boot_banner():
    with Vm("m0_boot") as vm:
        vm.wait_for(r"\[boot\] stage1 ok")


def test_qmp_screendump():
    with Vm("m0_qmp") as vm:
        vm.wait_for(r"\[boot\] stage1 ok")
        assert vm.qmp("query-status")["status"] == "running"
        w, h, px = vm.screendump()
        assert w > 0 and h > 0 and len(px) == w * h * 3
