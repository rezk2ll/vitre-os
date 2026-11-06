from harness import TestFailure, Vm


def test_e820_and_free_pages():
    with Vm("m4_map") as vm:
        m = vm.wait_for(r"\[mem\] free pages (\d+) of (\d+) usable")
        free, total = int(m.group(1)), int(m.group(2))
        # 128 MiB guest: about 32k pages, minus low memory and the kernel
        if not 25000 < free < total <= 32768:
            raise TestFailure(f"free={free} total={total}")


def test_alloc_free_stress():
    with Vm("m4_stress", cmdline="test=mem") as vm:
        vm.wait_for(r"\[mem\] pages ok")
        vm.wait_for(r"\[mem\] heap ok")
        m = vm.wait_for(r"\[mem\] free blocks after drain: (\d+)")
        if "FAIL" in vm.serial():
            raise TestFailure("self-test reported a failure")
        # every growth chunk coalesces back into one block
        if int(m.group(1)) > 4:
            raise TestFailure(f"heap left fragmented: {m.group(1)} free blocks")
