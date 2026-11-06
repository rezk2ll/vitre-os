from harness import TestFailure, Vm


def test_e820_and_free_pages():
    with Vm("m4_map") as vm:
        m = vm.wait_for(r"\[mem\] free pages (\d+) of (\d+) usable")
        free, total = int(m.group(1)), int(m.group(2))
        # 128 MiB guest: about 32k pages, minus low memory and the kernel
        if not 25000 < free < total <= 32768:
            raise TestFailure(f"free={free} total={total}")
