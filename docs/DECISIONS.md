# Decisions

Each entry: the choice, then why.

## D1. NASM 2.16.01

The build and CI use NASM 2.16.01, the Ubuntu 24.04 package. The in-OS assembler (M8) is checked byte for byte against this version, so a different NASM can change the expected bytes.

## D2. Test harness without pytest

`tests/run.py` collects `test_*` functions from `tests/test_*.py` and runs them in order. Only the Python standard library is needed on the host and in CI. `make test T=m3` filters by substring.

## D3. QEMU wiring for tests

Each test boots a private copy of `build/vitre.img` so disk writes (patch persistence) cannot leak between tests. COM1 goes to stdio, QMP to a unix socket (screendump, sendkey, HMP commands). `isa-debug-exit` at port 0xf4 lets the kernel end a run with an exit code. Networking is off unless a test asks for it.

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

## D17. Source area and ATA PIO

The source area holds the full text of every file that contains a patchable function, which lets Forge show and reassemble a whole module. It starts with a header (`VSRC`, file count, total length) and a directory of 48-byte entries (path, offset, length); a symbol record's source offset points at the function's header comment inside it. It lives on disk at LBA 2048, 1 MiB reserved, so the kernel can grow to just under 1 MiB without moving it. The kernel reads it at boot with polled ATA PIO (LBA28, primary master), the same driver that will write saved patches back. Polling is fine at this size and avoids an IRQ 14 handler.

## D18. Patchable modules and the Forge test

A patchable module is a whole file written in the Vitre dialect (docs/DIALECT.md), so Forge only ever assembles code it fully understands. The log printers moved into `kernel/report.asm` for this. Names a module uses but does not define are resolved through a label table that `tools/gen.py` emits next to the symbol table: every top-level label and `equ` in the image with its value. Because the module is linked into the kernel by NASM, "Forge matches NASM" is checked inside the OS: Forge assembles the module's source from the source area at the address of its first label, and the result must equal the kernel's own bytes at that address.

## D19. Live patching, rollback and persistence

- A patch assembles the whole module into 4 fresh pages, then swaps every jump table slot it defines under `cli`, so no caller ever sees half a module. Old code is never freed, because a task may still be running it.
- Rollback is one level deep: it restores the slots saved by the last patch. That covers "undo what I just broke" without keeping a history.
- For 10 s after a patch, a CPU exception whose RIP is in the new code rolls the patch back and resumes the shell at its prompt. Recovery only runs when interrupts were on (not inside an IRQ handler, which would lose its EOI) and the faulting task is the shell. Anything else stays fatal.
- `edit` stores into the source area in memory and marks the module edited. `save` writes the whole source area back to its disk sectors. At boot, every module marked edited is patched from its saved source, so edits survive a reboot without rebuilding the image.
- Known limit: symbol records keep the source offsets from the build, so after an edit they can point at the wrong place in the module text.

## D20. Debugger and Glass

- Stepping sets TF in the task's saved frame, resumes it, and waits up to 1 s for the #DB handler to pause it again. On a timeout, TF is cleared under `cli` so that a stray #DB later is not fatal.
- Breakpoints are one-shot: the trap restores the original byte, rewinds RIP and drops the breakpoint. That avoids the step-over-and-rearm dance, and in practice a breakpoint is set again when needed.
- A breakpoint pauses the task only when it is not the shell and interrupts were on. Otherwise it only reports the hit and goes on, because pausing the shell or an IRQ path would hang the machine.
- The disassembler covers what the kernel itself uses: the one-byte map, the groups, and the parts of the 0x0f map that NASM emits for this code. Anything else prints as `db`. The test compares mnemonics and lengths with ndisasm over the kernel's own functions, which is what Glass shows.
- The code pane decodes from the start of the enclosing function, so the lines before RIP are real instruction boundaries rather than guesses from decoding backwards.
- Glass redraws every 100 ms from the task's saved frame and yields between frames, so the watched task keeps running at full speed.

## D21. Network stack shape

- One card, one address. The e1000 is found by PCI ID and QEMU's user network fixes the addresses, so there is no interface table or routing table: hosts on the local /24 are reached directly and everything else goes through the gateway.
- Receive runs in the IRQ handler, straight up the layers. ARP replies and ICMP echo replies are sent from there too, so every send path runs under `cli`, and the shared packet buffers are only touched with interrupts off.
- Sending to a host with no ARP entry resolves it first, but only outside an IRQ (interrupts on). From the IRQ path the packet is dropped instead, because waiting there would stop the clock.
- Addresses and ports stay in network byte order everywhere, as they sit in the packet. Only printing and parsing convert.
- Fragmented IPv4 packets are dropped. Nothing the later milestones fetch needs reassembly.

## D22. DHCP and DNS

- The static QEMU addresses stay as defaults, so the stack works before the lease and if no DHCP server answers. The client sends from that address rather than 0.0.0.0, which QEMU accepts.
- Replies are asked for by broadcast, and IPv4 accepts packets to 255.255.255.255 for that reason.
- One query in flight at a time, with fixed client ports and transaction IDs. A lookup waits up to 2 s per try, 3 tries.
- DNS takes the first A record of the answer and skips CNAMEs, since recursive servers include the final A records in the same answer.
- UDP checksums are 0 on send, as IPv4 allows, and are not checked on receive.

## D23. TCP

- One connection at a time, which is all a page fetch needs. There is no TIME_WAIT: the next connection picks a new local port.
- Sending is stop-and-wait, one 1024-byte segment until it is acknowledged, retried 3 times. Requests are small, so a send window would add code and no speed.
- Receiving takes in-order data only, into a 256 KiB buffer, and the advertised window is the room left in it. Out-of-order segments are dropped and the peer resends them.
- The send sequence number advances before the segment leaves, because the answer is handled in the IRQ and can arrive before `ip_send` returns.
- The initial sequence number mixes the tick count with a constant. It is not meant to resist guessing.
- Tests serve pages from the host (10.0.2.2) rather than example.com, so they run offline.

## D24. Browser

- HTTP/1.0 with `Connection: close`: the end of the body is the end of the connection, so there is no chunked encoding or Content-Length to handle.
- The layout is a grid of character cells with a style per cell, not a box tree. It wraps at the screen width once per page, and scrolling only redraws.
- Links are followed by typing their number, since there is no mouse driver. The number is shown after the link text.
- Redirects are shown as the page they return, not followed.

## D25. Crypto

- Only what TLS 1.3 with TLS_CHACHA20_POLY1305_SHA256 and X25519 needs. ChaCha20 needs no AES tables and no special instructions.
- Plain `mul` everywhere: QEMU's default CPU has no BMI2 or ADX.
- A field element for X25519 is four 64-bit limbs below 2^256, reduced below p only for output, since 2^256 is 38 mod p. Poly1305 keeps its accumulator in three limbs the same way.
- The ladder swaps with masks and runs all 255 steps, and the AEAD tag compare has no early exit. The final reductions still branch, so this is not a hardened implementation.
- HMAC, HKDF, Poly1305, the AEAD and X25519 keep their state in fixed buffers: one caller at a time, as TLS runs one connection at a time. SHA-256 takes a context, so transcript hashes can be copied mid-way.
- Tests type hex at the `crypto` command with `kbd=qwerty`. On AZERTY every digit needs Shift, which doubles the key events and drops keys on long lines.

## D26. TLS

- One suite (TLS_CHACHA20_POLY1305_SHA256) and one group (X25519). Every server tried accepts them, so there is no HelloRetryRequest path: one is refused.
- Records are decrypted in place in the TCP receive buffer. Handshake messages are copied out and joined, since a Certificate can span records. Application data is moved to the front of the buffer, so `http_body` and the browser read an https response like an http one.
- The random values come from the TSC and tick count, stirred into a SHA-256 pool. That is not a strong generator: a guessed key share would expose the session.
- The certificate and CertificateVerify are hashed into the transcript and not checked until M17. `get` and the browser title bar say so on every https page.
- Session tickets are skipped and an alert ends the response, close_notify or not.
