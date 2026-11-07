import os
import re

from harness import BUILD, SHELL_READY, TestFailure, Vm

PROMPT = r"\r\nvitre> "


def run(vm, command, start):
    vm.sendkeys(command + "\n")
    m = vm.wait_for(re.escape(command) + r"\r\n([\s\S]*?)" + PROMPT, start=start)
    return m.group(1), m.end()


def map_address(name):
    with open(os.path.join(BUILD, "kernel.map")) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 3 and parts[2] == name:
                return int(parts[0], 16)
    raise TestFailure(f"{name} not in kernel.map")


def test_single_step_advances_rip():
    loop = map_address("spin_task.loop")
    inc_len = 7                     # inc qword [rel x]: REX.W FF /0 disp32
    with Vm("m10_step") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        out, pos = run(vm, "spin", pos)
        task = re.search(r"started spin, task (\d+)", out).group(1)
        out, pos = run(vm, f"pause {task}", pos)
        if "paused" not in out:
            raise TestFailure(f"pause: {out!r}")
        rips = []
        for _ in range(4):
            out, pos = run(vm, f"step {task}", pos)
            m = re.search(r"rip ([0-9a-f]{16})", out)
            if not m:
                raise TestFailure(f"step: {out!r}")
            rips.append(int(m.group(1), 16))
        if set(rips) != {loop, loop + inc_len} or rips[0] == rips[1] or rips[0] != rips[2]:
            raise TestFailure(f"rips {[hex(r) for r in rips]}, loop at {loop:#x}")
        out, pos = run(vm, "tasks", pos)
        if not re.search(rf"\[task\] {task} spin paused", out):
            raise TestFailure(f"tasks: {out!r}")
        out, pos = run(vm, f"resume {task}", pos)
        out, pos = run(vm, f"step {task}", pos)
        if "not a task in that state" not in out:
            raise TestFailure(f"step on a running task: {out!r}")
