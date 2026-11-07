import os
import re
import subprocess
import tempfile

from harness import BUILD, SHELL_READY, TestFailure, Vm

PROMPT = r"\r\nvitre> "
KERNEL_PHYS = 0x100000

# Functions followed by another function, so their range holds only code.
DIS_FUNCTIONS = [
    "kputc", "task_create", "sched_tick", "sched_switch", "task_step",
    "debug_trap", "bp_set", "bp_trap", "parse_dec", "parse_addr",
    "shell_readline", "shell_execute", "cmd_help", "cmd_uptime", "cmd_layout",
    "ed_insert", "ed_up", "ed_down", "dis_hex", "dis_reg", "dis_fetch",
    "src_replace", "patch_apply", "cmd_reboot",
]

# ndisasm spells some conditions differently; both name the same opcode.
CC_ALIASES = {"z": "e", "nz": "ne", "c": "b", "nc": "ae", "na": "be",
              "pe": "p", "po": "np", "nl": "ge", "ng": "le"}
WORD_ALIASES = {"pushf": "pushfq", "popf": "popfq"}


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


def map_labels():
    with open(os.path.join(BUILD, "kernel.map")) as f:
        rows = [line.split() for line in f]
    return sorted((int(r[0], 16), r[2]) for r in rows
                  if len(r) == 3 and re.fullmatch(r"[0-9A-F]+", r[0])
                  and "." not in r[2] and int(r[0], 16) >= KERNEL_PHYS)


def mnemonic(text):
    words = text.replace(",", " ").split()
    while words and words[0] in ("lock", "rep"):
        words = words[1:]
    word = WORD_ALIASES.get(words[0], words[0])
    for prefix in ("cmov", "set", "j"):
        if word.startswith(prefix) and word != "jmp":
            cc = word[len(prefix):]
            return prefix + CC_ALIASES.get(cc, cc)
    return word


def ndisasm(start, end):
    with open(os.path.join(BUILD, "kernel.bin"), "rb") as f:
        f.seek(start - KERNEL_PHYS)
        code = f.read(end - start)
    with tempfile.NamedTemporaryFile() as tmp:
        tmp.write(code)
        tmp.flush()
        out = subprocess.run(["ndisasm", "-b", "64", "-o", hex(start), tmp.name],
                             capture_output=True, text=True, check=True).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3:         # continuation lines carry only bytes
            rows.append((int(parts[0], 16), mnemonic(parts[2])))
    return rows


def test_disassembler_matches_ndisasm():
    labels = map_labels()
    ends = {name: labels[i + 1][0] for i, (_, name) in enumerate(labels[:-1])}
    starts = {name: addr for addr, name in labels}
    with Vm("m10_dis") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        for name in DIS_FUNCTIONS:
            want = ndisasm(starts[name], ends[name])
            got = []
            while len(got) < len(want):
                addr = want[len(got)][0]
                count = min(64, len(want) - len(got))
                out, pos = run(vm, f"dis {addr:#x} {count}", pos)
                before = len(got)
                for m in re.finditer(r"  ([0-9a-f]{16})  (.*?)(?:\r\n|$)", out):
                    got.append((int(m.group(1), 16), mnemonic(m.group(2))))
                    if got[-1] != want[len(got) - 1]:
                        break
                if len(got) == before or got[-1] != want[len(got) - 1]:
                    break
            for (ga, gm), (wa, wm) in zip(got, want):
                if (ga, gm) != (wa, wm):
                    raise TestFailure(f"{name}: at {wa:#x} ndisasm says {wm}, "
                                      f"Vitre says {gm} at {ga:#x}:\n{out}")
            if len(got) < len(want):
                raise TestFailure(f"{name}: Vitre printed {len(got)} of {len(want)} lines:\n{out}")


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


def test_breakpoint_pauses_task():
    loop = map_address("spin_task.loop")
    with Vm("m10_break") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        out, pos = run(vm, "spin", pos)
        task = re.search(r"started spin, task (\d+)", out).group(1)
        out, pos = run(vm, f"break {loop:#x}", pos)
        if f"set at {loop:016x}" not in out:
            raise TestFailure(f"break: {out!r}")
        pos = vm.wait_for(rf"\[break\] task {task} hit {loop:016x}, paused", start=pos).end()
        out, pos = run(vm, f"step {task}", pos)
        if f"rip {loop + 7:016x}" not in out:
            raise TestFailure(f"step after the breakpoint: {out!r}")
        out, pos = run(vm, "break spin_task", pos)
        if "set at" not in out:
            raise TestFailure(f"break on a label: {out!r}")
        out, pos = run(vm, "break 0x10", pos)
        if "not in kernel code" not in out:
            raise TestFailure(f"break outside the kernel: {out!r}")


def test_task_view_pauses_and_steps():
    with Vm("m10_view") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        out, pos = run(vm, "spin", pos)
        task = re.search(r"started spin, task (\d+)", out).group(1)
        vm.sendkeys(f"glass {task}\n")
        vm.wait_screen(r"glass  spin  running")
        vm.wait_screen(r"inc qword \[rel 0x[0-9a-f]+\]")
        vm.sendkeys("p")
        rip = vm.wait_screen(r"glass  spin  paused[\s\S]*RIP= ([0-9a-f]{16})").group(1)
        vm.sendkeys("s")
        vm.wait_screen(r"RIP= (?!" + rip + r")[0-9a-f]{16}")
        vm.sendkeys("q")
        vm.wait_for(PROMPT, start=pos)


def test_glass_alone_watches_a_task():
    with Vm("m10_pick") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("glass\n")
        vm.wait_screen(r"glass  spin  running")
        vm.sendkeys("q")
        pos = vm.wait_for(PROMPT, start=pos).end()
        out, pos = run(vm, "tasks", pos)
        if len(re.findall(r"spin", out)) != 1:
            raise TestFailure(f"glass should reuse the running task:\n{out}")
        vm.sendkeys("glass\n")
        vm.wait_screen(r"glass  spin  running")


def test_patch_view_shows_both_versions():
    with Vm("m10_patch_view") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        out, pos = run(vm, "glass patch", pos)
        if "no live patch" not in out:
            raise TestFailure(f"glass patch before any patch: {out!r}")
        out, pos = run(vm, "patch kernel/report.asm", pos)
        vm.sendkeys("glass patch\n")
        vm.wait_screen(r"jt 0x[0-9a-f]+  0x[0-9a-f]+ <\w+>  was 0x1[0-9a-f]+")
        vm.wait_screen(r"old code +new code")
        vm.press("down")
        vm.sendkeys("q")
        vm.wait_for(PROMPT, start=pos)
