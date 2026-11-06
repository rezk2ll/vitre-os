import os
import re

from harness import BUILD, TestFailure, Vm


def nasm_map():
    with open(os.path.join(BUILD, "kernel.map")) as f:
        text = f.read().split("Section .text", 1)[1]
    return {name: int(addr, 16) for addr, name in re.findall(r"^\s+[0-9A-F]+\s+([0-9A-F]+)\s+(\S+)$", text, re.M)}


def test_symbol_dump_matches_map():
    with Vm("m6_syms", cmdline="test=syms") as vm:
        vm.wait_for(r"\[sym\] sym_put_signed ")
        serial = vm.serial()
    syms = re.findall(r"\[sym\] (\w+) ([0-9a-f]{16}) (\d+) (-?\d+) (-?\d+)", serial)
    if len(syms) < 50:
        raise TestFailure(f"only {len(syms)} symbols dumped")
    labels = nasm_map()
    addrs = []
    for name, addr, size, slot, src in syms:
        if labels.get(name) != int(addr, 16):
            raise TestFailure(f"{name}: kernel says {addr}, map says {labels.get(name)}")
        addrs.append((int(addr, 16), int(size)))
    for (a, size), (b, _) in zip(addrs, addrs[1:]):
        if a + size != b:
            raise TestFailure(f"symbol at {a:x} does not end where the next one starts")
    patchable = {name for name, _, _, slot, _ in syms if slot != "-1"}
    if patchable != {"kput_dec", "fb_log_mode", "pmm_log", "sched_list"}:
        raise TestFailure(f"patchable: {patchable}")
