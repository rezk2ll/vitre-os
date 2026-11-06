# Status

## Current milestone

M6 done. Next: M7, the shell.

## Milestones

- M0: done. `make test` boots the image headless, reads COM1, talks QMP.
- M1: done. Stage 1 loads stage 2, stage 2 loads the kernel to 1 MiB, collects E820, enables A20 and enters long mode.
- M2: done. IDT for all 256 vectors, exception register dump, PIC remapped to 32-47, PIT at 1000 Hz. Tests pick scenarios through the fw_cfg command line (`test=ud`, `test=pit`).
- M3: done. Stage 2 sets a 1024x768x32 VBE mode (800x600 fallback). The kernel log is drawn on a full-screen console with an original 8x16 font, and the PS/2 keyboard echoes keys. Tests read the screen back by matching cells against the same font.
- M4: done. Bitmap page allocator from E820, first-fit kernel heap (`kmalloc`/`kfree`) with coalescing. `test=mem` stamps 256 page runs to prove no overlap, then runs 4000 random heap operations with content checks and verifies nothing leaks.
- Keyboard layouts: AZERTY by default with AltGr and Latin-1 accented characters, `kbd=qwerty` for US.
- M5: done. Preemptive round-robin scheduler for kernel tasks (10 ms slices, `int 0x40` yield). `test=tasks` runs two tasks whose output interleaves, then lists the task table.
- M6: done. `tools/gen.py` builds the jump table, symbol table and source area from function headers. Patchable functions are only called through `jt_*` slots. The source area sits on disk at LBA 2048 and is read at boot with ATA PIO. `test=syms` dumps both and the test checks them against the NASM map.

## Stubs

- None.

## Sizes

- stage1: 512 bytes
- stage2: 16 KiB slot (code is under 1 KiB)
- kernel: 20496 bytes (4 KiB interrupt stubs and table, 3.5 KiB font, 7 KiB symbol table)
- source area: 16777 bytes
