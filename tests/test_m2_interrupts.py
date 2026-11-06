import os
import re
import time

from harness import BUILD, TestFailure, Vm

KERNEL_PHYS = 0x100000


def test_cmdline_from_fw_cfg():
    with Vm("m2_cmdline", cmdline="hello=a,b xtest=ud test=udx") as vm:
        vm.wait_for(r"\[kernel\] cmdline: hello=a,b xtest=ud test=udx\r?\n")
        vm.wait_for(r"\[kernel\] interrupts on")
        time.sleep(0.3)
        if "[exc]" in vm.serial():
            raise TestFailure("a partial word match ran the ud self-test")


def test_ud_register_dump():
    with Vm("m2_ud", cmdline="test=ud") as vm:
        vm.wait_for(r"\[kernel\] interrupts on")
        m = vm.wait_for(r"\[exc\] #UD vector=6 error=0+\r?\n")
        dump = vm.wait_for(r"\[exc\] halted", start=m.end())
        text = vm.serial()[m.end():dump.start()]
        for reg in ("RAX", "RBX", "RCX", "RDX", "RSI", "RDI", "RBP", "RSP",
                    "R8", "R9", "R10", "R11", "R12", "R13", "R14", "R15",
                    "RIP", "CS", "RFL", "SS", "CR2", "CR3"):
            if not re.search(rf"\b{reg}=[0-9a-f]{{16}}", text):
                raise TestFailure(f"{reg} missing from dump:\n{text}")
        rip = int(re.search(r"RIP=([0-9a-f]{16})", text).group(1), 16)
        with open(os.path.join(BUILD, "kernel.bin"), "rb") as f:
            image = f.read()
        if image[rip - KERNEL_PHYS:rip - KERNEL_PHYS + 2] != b"\x0f\x0b":
            raise TestFailure(f"RIP {rip:#x} does not point at ud2")
        cs = int(re.search(r"\bCS=([0-9a-f]{16})", text).group(1), 16)
        if cs != 0x18:
            raise TestFailure(f"CS {cs:#x}, expected the 64-bit code selector")


def test_pit_ticks_increase():
    with Vm("m2_pit", cmdline="test=pit") as vm:
        ticks = []
        pos = 0
        for _ in range(3):
            m = vm.wait_for(r"\[timer\] ticks=(\d+)", start=pos)
            ticks.append(int(m.group(1)))
            pos = m.end()
        if not (ticks[0] >= 100 and ticks[0] < ticks[1] < ticks[2]):
            raise TestFailure(f"ticks not increasing: {ticks}")
        for a, b in zip(ticks, ticks[1:]):
            if b - a < 100:
                raise TestFailure(f"less than 100 ticks between 100 ms samples: {ticks}")
