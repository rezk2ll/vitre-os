import re

from harness import SHELL_READY, TestFailure, Vm
from test_files import write_file
from test_m9_patch import run

ANSWER = """\
start:
    mov eax, 6
    imul eax, 7
    mov edi, eax
    call [rel jt_kput_dec]
    lea rdi, [rel tail]
    jmp kputs
tail db " is the answer", 10, 0
"""


def test_run_shipped_programs():
    with Vm("run") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        out, pos = run(vm, "run hello.asm", pos)
        if out != "Hello, world! Vitre assembled this program itself.":
            raise TestFailure(f"hello: {out!r}")
        out, pos = run(vm, "run hello.asm Vitre", pos)
        if not out.startswith("Hello, Vitre!"):
            raise TestFailure(f"hello with an argument: {out!r}")
        out, pos = run(vm, "run nope.asm", pos)
        if out != "no such file: nope.asm":
            raise TestFailure(f"missing file: {out!r}")

        vm.sendkeys("run guess.asm\n")
        low, high = 1, 100
        for _ in range(8):
            guess = (low + high) // 2
            pos = vm.wait_for(r"guess: ", start=pos).end()
            vm.sendkeys(f"{guess}\n")
            m = vm.wait_for(r"(higher|lower|yes! found in \d+ tries)\r\n", start=pos)
            pos = m.end()
            if m.group(1) == "higher":
                low = guess + 1
            elif m.group(1) == "lower":
                high = guess - 1
            else:
                break
        else:
            raise TestFailure("guess.asm never said yes")
        vm.wait_for(r"vitre> ", start=pos)


def test_write_and_run_a_program():
    with Vm("run_new") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        pos = write_file(vm, "answer.asm", ANSWER, pos)
        out, pos = run(vm, "run answer.asm", pos)
        if out != "42 is the answer":
            raise TestFailure(f"answer.asm: {out!r}")
        pos = write_file(vm, "bad.asm", "    frob rax\n", pos)
        out, pos = run(vm, "run bad.asm", pos)
        if not re.fullmatch(r"\[run\] bad\.asm: line 1: .+", out):
            raise TestFailure(f"bad.asm: {out!r}")


def test_a_crashing_program_stops_and_the_shell_lives():
    with Vm("run_crash") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        pos = write_file(vm, "div.asm", "    xor ecx, ecx\n    div rcx\n    ret\n", pos)
        out, pos = run(vm, "run div.asm", pos)
        if not re.search(r"\[run\] #DE at [0-9a-f]{16}, program stopped", out):
            raise TestFailure(f"div.asm: {out!r}")
        pos = write_file(vm, "far.asm", "    mov rax, 0x10000000000\n    mov rax, [rax]\n    ret\n", pos)
        out, pos = run(vm, "run far.asm", pos)
        if not re.search(r"\[run\] #PF at [0-9a-f]{16}, program stopped", out):
            raise TestFailure(f"far.asm: {out!r}")
        out, pos = run(vm, "run hello.asm", pos)
        if not out.startswith("Hello, world!"):
            raise TestFailure(f"shell after the crashes: {out!r}")
