# Status

## Current milestone

M0 done. Next: M1, stage 1 loads stage 2, stage 2 reaches long mode and prints `[boot] long mode ok`.

## Milestones

- M0: done. `make test` boots the image headless, reads COM1, talks QMP.

## Stubs

- `boot/stage1.asm`: prints a banner and halts, does not load stage 2 (M1).

## Sizes

- stage1: 512 bytes
