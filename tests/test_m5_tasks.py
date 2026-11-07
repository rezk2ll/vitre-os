import re

from harness import TestFailure, Vm


def test_two_tasks_interleave():
    with Vm("m5_tasks", cmdline="test=tasks") as vm:
        vm.wait_for(r"\[sched\] tasks done")
        lines = re.findall(r"\[(alpha|beta)\] (\d)", vm.serial())
        for name in ("alpha", "beta"):
            got = [int(n) for who, n in lines if who == name]
            if got != list(range(5)):
                raise TestFailure(f"{name} printed {got}")
        order = [who for who, _ in lines]
        switches = sum(a != b for a, b in zip(order, order[1:]))
        # one switch is two tasks run back to back; how many more depends on
        # where the 10 ms slices fall under a loaded host
        if switches < 3:
            raise TestFailure(f"tasks did not interleave: {order}")
        if re.search(r"\[task\] [12] ", vm.serial()):
            raise TestFailure("ended tasks still listed")
        vm.wait_for(r"\[task\] 0 kernel ready")
