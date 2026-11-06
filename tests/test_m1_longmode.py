from harness import Vm


def test_long_mode():
    with Vm("m1_longmode") as vm:
        vm.wait_for(r"\[boot\] stage1 ok")
        vm.wait_for(r"\[boot\] stage2")
        vm.wait_for(r"\[boot\] kernel loaded")
        vm.wait_for(r"\[boot\] long mode ok")
        vm.wait_for(r"\[kernel\] image ok")
