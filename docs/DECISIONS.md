# Decisions

Each entry: the choice, then why.

## D1. NASM 2.16.01

The build and CI use NASM 2.16.01, the Ubuntu 24.04 package. The in-OS assembler (M8) is checked byte for byte against this version, so a different NASM can change the expected bytes.

## D2. Test harness without pytest

`tests/run.py` collects `test_*` functions from `tests/test_*.py` and runs them in order. Only the Python standard library is needed on the host and in CI. `make test T=m3` filters by substring.

## D3. QEMU wiring for tests

Each test boots a private copy of `build/vitre.img` so disk writes (patch persistence) cannot leak between tests. COM1 goes to stdio, QMP to a unix socket (screendump, sendkey, HMP commands). `isa-debug-exit` at port 0xf4 lets the kernel end a run with an exit code. Networking is off unless a test asks for it.

## D4. No repo CLAUDE.md

The brief asks to read `CLAUDE.md` at session start. Agent configuration is kept outside the repo, so `docs/BRIEF.md` holds the spec and `docs/STATUS.md` the handoff note.

## D5. Boot layout

- Disk: stage 1 at LBA 0, stage 2 in LBA 1 to 32, kernel from LBA 64. `boot/layout.inc` is the single source for these numbers.
- Stage 2 loads the kernel in 64-sector chunks into a real-mode buffer at 0x20000 and copies each chunk to 1 MiB with unreal mode. This keeps every BIOS call in plain real mode and puts no 640 KiB cap on the kernel.
- The Makefile passes the kernel's sector count to stage 2 with `-DKERNEL_SECTORS`. The kernel's last qword is a magic value it checks at entry, so a short load shows up as `[kernel] image truncated`.
- Paging identity-maps the first 4 GiB with 2 MiB pages (tables at 0x70000). This covers RAM and the QEMU framebuffer and MMIO holes without a page-table manager.

## D6. Interrupt handlers return the frame to resume

All vectors share one entry path and one frame layout. A handler gets the frame in `rdi` and returns the frame to resume in `rax`. The preemptive scheduler (M5) and the Glass single-step and breakpoint controls (M10) then work by returning a different or edited frame, with no special entry code. Alternative considered: separate exception and IRQ paths, which would need a second context-switch path later.

## D7. Test scenarios through fw_cfg

The kernel reads a command line from the QEMU fw_cfg file `opt/vitre/cmdline`. Tests pass `-fw_cfg name=opt/vitre/cmdline,string=test=ud` and the kernel runs the named self-test after boot. Normal boots have no command line and run no self-test. This keeps one image for every test instead of a build per scenario. fw_cfg exists only under QEMU, which is the target.

## D8. Kernel .bss

Zero-initialised kernel state is declared with `section .bss` in each module. The flat binary leaves it out of the image and `kernel_entry` clears it from `bss_start` to `bss_end`. Large tables such as the IDT cost no disk space or load time.

## D9. Video mode

Stage 2 picks a VBE linear framebuffer mode at 1024x768, 32 bpp, falling back to 800x600. Without one the kernel runs headless on serial. The kernel never changes mode, so no real-mode trip is needed after boot.

## D10. Font

The 8x16 font in `glass/font.asm` is an original design covering ASCII 32 to 126, one glyph per line of `db`. Glyphs sit in rows 2 to 10, with descenders down to row 12. Bold and italic for the browser will be derived at draw time (bit smear, row shear) instead of shipping more glyph tables.

## D11. Screen layout on the 8x16 grid

Consoles and, later, Glass panes put text only on the 8x16 character grid of the screen. Tests then read any screen region as text by matching each cell against `build/font.bin`, which is `glass/font.asm` assembled on its own. A cell's top-left pixel is its background, since every glyph leaves row 0 empty. Colours can change freely without breaking tests.

## D12. Keyboard

Scancode set 1, which the i8042 produces by default under QEMU. Printable keys map to ASCII on a US layout, Ctrl+letter gives 1 to 26, and arrows, paging keys and F1 to F10 get `KEY_*` codes above 0x7f. A 64-byte ring buffer sits between the IRQ and `kbd_getc`.

## D13. Physical page allocator

A bitmap with one bit per 4 KiB page below 4 GiB (128 KiB of .bss), built from the E820 usable ranges. Everything below the end of the kernel's .bss stays reserved. `page_alloc` scans for a run of N free pages from a rotating hint, which keeps the code short and gives contiguous runs for DMA buffers later (e1000 rings). Memory above 4 GiB is ignored because the identity map stops there.

## D14. Keyboard layouts

AZERTY (French) is the default layout, QWERTY (US) is chosen with `kbd=qwerty` on the command line. Each layout has a plain, a Shift and an AltGr map indexed by scancode. Non-ASCII characters are Latin-1 key codes (0xa0 to 0xff), so every character stays one byte; the font covers the Latin-1 characters on the French keyboard and draws '?' for the rest. Dead keys are not composed: `^` and `¨` type themselves.

## D15. Scheduler

Kernel tasks only, round-robin, preempted by the PIT every 10 ms. A task is a slot in a fixed table of 32 with a 16 KiB stack from the page allocator; its saved state is the interrupt frame on its own stack, so `task_create` builds a fake frame and a switch is returning another frame (D6). `int 0x40` yields. A task ends by returning from its entry; its stack is freed by the next switch that runs on another stack. No FPU/SSE state is saved: kernel code does not use those registers. `kputs` runs with interrupts off so log lines from tasks never mix.

## D16. Jump table and symbol table

`tools/gen.py` runs before the kernel build. It walks `kernel/main.asm` through its includes, in image order, and reads every function header. A `; patchable: yes` function gets a `jt_<name>` qword slot holding its address; callers use `call [rel jt_<name>]`, and the build fails on any direct `call` or `jmp` to it. Every function with a header gets a 64-byte symbol record (address, size up to the next function, jump table slot, source offset, name), so the symbol table also names unpatchable code for the debugger. The generator is a host build helper, like the test harness: the kernel itself stays assembly. The first patchable functions are the log printers (`kput_dec`, `fb_log_mode`, `pmm_log`, `sched_list`), chosen because a broken patch to them shows up at once and cannot take down the exception handler, which prints its vector number on its own.
