import re

from harness import SHELL_READY, TestFailure, Vm


def test_forge_matches_nasm():
    with Vm("m8_forge") as vm:
        m = vm.wait_for(SHELL_READY)
        vm.sendkeys("forge\n")
        vm.wait_for(r"\[forge\][^\n]*\n[\s\S]*?vitre> ", start=m.end())
        lines = re.findall(r"\[forge\] ([^:]+): ([^\r]*)", vm.serial()[m.end():])
        if not lines:
            raise TestFailure("forge printed nothing")
        for path, result in lines:
            if not re.fullmatch(r"\d+ bytes, same as the kernel", result):
                raise TestFailure(f"{path}: {result}")
