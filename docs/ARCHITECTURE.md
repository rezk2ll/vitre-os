# Architecture

## Disk image

- LBA 0: stage 1 (MBR)
- LBA 1 to 32: stage 2
- LBA 64 onward: kernel

## Physical memory

- 0x5000: boot info (E820 count, entries at 0x5100)
- 0x7c00: stage 1, real-mode stack below it
- 0x8000: stage 2
- 0x20000: kernel load bounce buffer (32 KiB)
- 0x70000: page tables (PML4, PDPT, 4 page directories)
- 0x90000: initial kernel stack top
- 0x100000: kernel image

## Boot flow

```mermaid
flowchart TD
  bios[BIOS] --> s1[stage 1 at 0x7c00]
  s1 -->|int 13h ext read| s2[stage 2 at 0x8000]
  s2 --> cpuid[CPUID long mode check]
  cpuid --> a20[A20 on]
  a20 --> e820[E820 map to boot info]
  e820 --> load[kernel to 1 MiB via unreal mode]
  load --> pm[32-bit protected mode]
  pm --> pg[identity map 4 GiB, PAE, EFER.LME]
  pg --> lm[long mode, jump to 0x100000]
```

## Test flow

```mermaid
flowchart LR
  make[make test] --> run[tests/run.py]
  run --> vm[harness.Vm]
  vm -->|boots copy of vitre.img| qemu[QEMU headless]
  qemu -->|COM1 stdio| vm
  vm <-->|QMP socket| qemu
```
