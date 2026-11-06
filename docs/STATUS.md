# Status

## Current milestone

M2 done. Next: M3, VBE framebuffer set by stage 2, 8x16 font, text console, PS/2 keyboard echo.

## Milestones

- M0: done. `make test` boots the image headless, reads COM1, talks QMP.
- M1: done. Stage 1 loads stage 2, stage 2 loads the kernel to 1 MiB, collects E820, enables A20 and enters long mode.
- M2: done. IDT for all 256 vectors, exception register dump, PIC remapped to 32-47, PIT at 1000 Hz. Tests pick scenarios through the fw_cfg command line (`test=ud`, `test=pit`).

## Stubs

- None.

## Sizes

- stage1: 512 bytes
- stage2: 16 KiB slot (code is under 1 KiB)
- kernel: 6576 bytes (of which 4 KiB are the 256 interrupt stubs and their table)
