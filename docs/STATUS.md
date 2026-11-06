# Status

## Current milestone

M3 done. Next: M4, E820-driven physical page allocator and kernel heap, with an alloc/free stress self-test.

## Milestones

- M0: done. `make test` boots the image headless, reads COM1, talks QMP.
- M1: done. Stage 1 loads stage 2, stage 2 loads the kernel to 1 MiB, collects E820, enables A20 and enters long mode.
- M2: done. IDT for all 256 vectors, exception register dump, PIC remapped to 32-47, PIT at 1000 Hz. Tests pick scenarios through the fw_cfg command line (`test=ud`, `test=pit`).
- M3: done. Stage 2 sets a 1024x768x32 VBE mode (800x600 fallback). The kernel log is drawn on a full-screen console with an original 8x16 font, and the PS/2 keyboard echoes keys. Tests read the screen back by matching cells against the same font.

## Stubs

- None.

## Sizes

- stage1: 512 bytes
- stage2: 16 KiB slot (code is under 1 KiB)
- kernel: 9584 bytes (4 KiB interrupt stubs and table, 1520 bytes font)
