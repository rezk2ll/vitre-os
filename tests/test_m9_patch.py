import re

from harness import SHELL_READY, TestFailure, Vm

PROMPT = r"\r\nvitre> "


def run(vm, command, start):
    vm.sendkeys(command + "\n")
    m = vm.wait_for(re.escape(command) + r"\r\n([\s\S]*?)" + PROMPT, start=start)
    return m.group(1), m.end()


def test_patch_and_rollback():
    with Vm("m9_patch") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        out, pos = run(vm, "patch kernel/report.asm", pos)
        m = re.search(r"\[patch\] kernel/report.asm: 4 functions, 504 bytes at ([0-9a-f]{16})", out)
        if not m:
            raise TestFailure(f"patch: {out!r}")
        out, pos = run(vm, "mem", pos)
        if not re.search(r"pages free \d+ of \d+", out):
            raise TestFailure(f"mem after patch: {out!r}")
        out, pos = run(vm, "rollback", pos)
        if "[patch] rolled back 4 functions" not in out:
            raise TestFailure(f"rollback: {out!r}")
        out, pos = run(vm, "rollback", pos)
        if "[patch] no live patch" not in out:
            raise TestFailure(f"second rollback: {out!r}")
