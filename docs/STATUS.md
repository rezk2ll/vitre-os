# Status

## Current milestone

M11 done. Next: M12, UDP, DHCP and DNS.

## Milestones

- M0: done. `make test` boots the image headless, reads COM1, talks QMP.
- M1: done. Stage 1 loads stage 2, stage 2 loads the kernel to 1 MiB, collects E820, enables A20 and enters long mode.
- M2: done. IDT for all 256 vectors, exception register dump, PIC remapped to 32-47, PIT at 1000 Hz. Tests pick scenarios through the fw_cfg command line (`test=ud`, `test=pit`).
- M3: done. Stage 2 sets a 1024x768x32 VBE mode (800x600 fallback). The kernel log is drawn on a full-screen console with an original 8x16 font, and the PS/2 keyboard echoes keys. Tests read the screen back by matching cells against the same font.
- M4: done. Bitmap page allocator from E820, first-fit kernel heap (`kmalloc`/`kfree`) with coalescing. `test=mem` stamps 256 page runs to prove no overlap, then runs 4000 random heap operations with content checks and verifies nothing leaks.
- Keyboard layouts: AZERTY by default with AltGr and Latin-1 accented characters, `kbd=qwerty` for US.
- M5: done. Preemptive round-robin scheduler for kernel tasks (10 ms slices, `int 0x40` yield). `test=tasks` runs two tasks whose output interleaves, then lists the task table.
- M6: done. `tools/gen.py` builds the jump table, symbol table and source area from function headers. Patchable functions are only called through `jt_*` slots. The source area sits on disk at LBA 2048 and is read at boot with ATA PIO. `test=syms` dumps both and the test checks them against the NASM map.
- M7: done. The kernel ends in a shell with `help`, `clear`, `mem`, `tasks`, `syms`, `uptime`, `layout` and `reboot`. Backspace edits the line, Ctrl+C drops it, Ctrl+L clears the screen.
- M8: done. Forge, the in-kernel assembler for the Vitre dialect, runs multi-pass with growing jumps and resolves names against the module and then the kernel label table. The `forge` command assembles every module in the source area at its linked address and compares the bytes with the running kernel: `kernel/report.asm` matches NASM byte for byte.
- M9: done. `edit <module>` opens a full-screen editor on a module of the source area (Ctrl+S store, Ctrl+F find, Ctrl+Q quit). `patch <module>` assembles it into fresh pages and swaps its jump table slots under `cli`; `rollback` restores them. A CPU exception in new code within 10 s of a patch rolls it back and returns to the prompt. `save` writes the source area to disk, and boot re-patches every edited module.
- M10: done. `pause`, `resume` and `step` control a task (`spin` starts one to try them on). `break` sets one-shot int3 breakpoints. `dis` disassembles kernel code, and a test checks it against ndisasm over two dozen functions. `glass <task>` shows a live full-screen view: registers with changes highlighted, code around RIP, the stack with symbols, and memory. Its keys pause, step, or open the module under RIP in the editor.
- M11: done. `lspci` lists PCI devices. The e1000 driver brings the card up with interrupt-driven receive, and `net` shows the MAC, link and frame counters. ARP answers for 10.0.2.15 and caches senders (`arp`). IPv4 and ICMP echo answer pings, and `ping 10.0.2.2` gets replies from QEMU's gateway.

## Stubs

- None.

## Sizes

- stage1: 512 bytes
- stage2: 16 KiB slot (code is under 1 KiB)
- kernel: 80816 bytes (4 KiB interrupt stubs and table, 3.5 KiB font, symbol and label tables, Forge, editor, disassembler, Glass, network stack)
- source area: 3047 bytes
