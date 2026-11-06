# VITRE OS: project brief

This is the spec. `docs/STATUS.md` is the handoff note, `docs/DECISIONS.md` records every non-obvious choice.

## 1. Thesis

Vitre ("glass" in French) is a 64-bit operating system written entirely in x86-64 assembly, built around two ideas:

1. Self-rewriting. The OS carries its own source code, an editor and an assembler. From inside the running OS, the user can open any patchable kernel function, edit it, assemble it, and hot-patch it live. No reboot, no host machine. Patches can be saved to disk and survive a reboot.
2. Glass UI. The debugger is the user interface. Every task window shows its output next to its live registers, stack, disassembly and memory. Any task can be paused, single-stepped or inspected.

On top of that, Vitre connects to the internet and ships a text-and-layout web browser, also written in assembly.

Any feature should strengthen one of these two ideas or the networking/browser goal. If it doesn't, don't build it.

## 2. Hard constraints

- 100% assembly in the OS image. No C, no Rust, no Zig, no compiler-generated code, no third-party binaries or blobs in the image. Every byte that runs inside Vitre comes from `.asm` files in this repo.
- Assembler: NASM, flat binaries (`-f bin`), no linker. NASM version pinned in `docs/DECISIONS.md`.
- Target: x86-64, legacy BIOS boot, QEMU first (`qemu-system-x86_64`). Real hardware is out of scope.
- Host-side tools only for building and testing: `make`, `nasm`, `qemu`, `gdb`, Python 3 for the test harness and build helpers. Nothing from the host gets into the image except assembled output and embedded source text.
- No placeholders presented as done. Stubs say so in the code (`; STUB:`) and in `docs/STATUS.md`.
- A milestone is complete only when its automated test passes.

## 3. Repo layout

```
/boot        stage1 (512-byte MBR), stage2 (real mode -> long mode)
/kernel      core: memory, interrupts, scheduler, jump table, symbols
/drivers     serial, pit, keyboard, vbe framebuffer, ata pio, pci, e1000
/net         ethernet, arp, ipv4, icmp, udp, dhcp, dns, tcp, tls
/glass       window manager, panes, font, disassembler view
/forge       in-OS editor, in-OS assembler, patcher (the self-rewriting part)
/apps        shell, browser
/lib         shared routines: strings, memcpy, hex/decimal print, crypto primitives
/tests       Python harness + per-milestone tests
/docs        ARCHITECTURE.md, DECISIONS.md, STATUS.md, ABI.md, DIALECT.md
Makefile     make, make run, make debug, make test
```

## 4. Conventions

ABI (see `docs/ABI.md`):
- Args in `rdi, rsi, rdx, rcx, r8, r9`; return in `rax` (and `rdx` if needed).
- Callee-saved: `rbx, rbp, r12-r15`. Everything else is caller-saved.
- Carry flag set = error, `rax` = error code.
- Stack 16-byte aligned at call sites.

Every function gets a header comment:

```
; name: tcp_send
; in:   rdi = socket ptr, rsi = buf, rdx = len
; out:  rax = bytes queued, CF=1 on error
; clobbers: rcx, r8-r11
; patchable: yes
```

Naming: `module_action` in snake_case. Local labels with `.`.

Logging: everything important also goes to COM1 serial as `[module] message`. The test harness reads serial.

## 5. Core architecture

### 5.1 Boot
- Stage 1: 512-byte MBR that loads stage 2 from disk (BIOS int 13h extended reads).
- Stage 2 (real mode): E820 memory map, VBE linear framebuffer (1024x768x32 preferred, fall back to 800x600x32), A20, load the kernel, then GDT, 32-bit protected mode, identity-mapped paging, long mode, jump to the kernel.

### 5.2 Kernel
- IDT with handlers for all CPU exceptions (full register dump to screen and serial).
- PIC remap, PIT at 1000 Hz, PS/2 keyboard.
- Bitmap physical page allocator from E820, then a simple kernel heap.
- Preemptive round-robin scheduler with per-task saved context. Ring 0 first; ring 3 later.

### 5.3 The jump table
- Every patchable function is called only through a central jump table: `call [jt_tcp_send]`, never directly.
- The table is generated at build time from `; patchable: yes` headers.
- The image embeds a symbol table: name, jump table slot, current address, size, source file offset.
- The image embeds the source text of every patchable module in a read-only source area on disk.

### 5.4 Forge (editor + assembler + patcher)
- Patchable modules are written in the "Vitre dialect" (`docs/DIALECT.md`), a strict NASM-compatible subset. Host NASM and the in-OS assembler must produce identical bytes for the same source, checked by a test.
- The dialect covers: mov, lea, add, sub, and, or, xor, cmp, test, inc, dec, shl, shr, sar, imul, mul, div, push, pop, call, ret, jmp, jcc, setcc, cmovcc, movzx, movsx, rep movsb/stosb; 8/16/32/64-bit registers; [base + index*scale + disp]; labels; db/dw/dd/dq; equ; times. Extend only when a module needs it, document every addition.
- Patching flow: edit, assemble into a new code slot, sanity check, swap the jump table pointer atomically.
- Rollback: the patcher remembers the previous pointer. If the new code faults within N ms or N calls, the exception handler restores the old pointer and shows what happened in the glass view.
- Persistence: "save patch" writes the new source to the on-disk source area (ATA PIO) so the next boot reassembles it.

### 5.5 Glass UI
- Framebuffer window manager with a built-in 8x16 bitmap font written in asm.
- Each task window has panes: output, registers, stack (with symbol names), disassembly around RIP, hex memory view.
- Controls: pause, resume, single-step (trap flag), breakpoint (int3), "open in Forge" on the function under RIP.
- Glass shows Forge patches landing: old vs new code and the jump table swap.

## 6. Networking and browser

### 6.1 Stack
- PCI enumeration, e1000 driver (QEMU `-nic user,model=e1000`), rx/tx rings with interrupts.
- Ethernet, ARP (with cache), IPv4, ICMP echo, UDP, DHCP client, DNS resolver (A records), TCP (handshake, sequence numbers, retransmission with timeout, sliding window, FIN/RST).
- A small socket-like API for apps.

### 6.2 TLS
- Phase A: TLS 1.3 client, only `TLS_CHACHA20_POLY1305_SHA256` with X25519. SHA-256, HKDF, ChaCha20, Poly1305 and X25519 in asm, each tested against RFC vectors. Certificates not validated: the browser shows an "UNVERIFIED" banner on every HTTPS page.
- Phase B: certificate chain parsing (ASN.1/DER), signature verification (ECDSA P-256, RSA PKCS#1 v1.5 / PSS), small embedded root store. The banner goes away only when validation passes.
- Randomness: RDRAND/RDSEED if available, mixed with timer jitter. Weakness documented in `docs/DECISIONS.md`.

### 6.3 Browser
- HTTP/1.1 client: GET, redirects (max 5), Content-Length and chunked. No Accept-Encoding.
- Tolerant HTML tokenizer, simple tree.
- Rendering: text, headings, paragraphs, line breaks, links, lists, bold/italic, `<pre>`, basic tables if time allows. Ignore script and style. No JavaScript, no CSS.
- UI: address bar, scrolling, keyboard links (Tab cycles, Enter follows), back, status line for DNS/TCP/TLS progress.
- Targets: `http://example.com`, then `https://example.com`, then simple text-heavy sites.

## 7. Milestones

Strictly in order. Each ends with tests passing, `docs/STATUS.md` updated, and a commit `M<n>: <summary>`.

- M0: repo, Makefile, QEMU run/debug scripts, Python harness that boots QEMU headless and checks serial. Test: `make test` passes a trivial boot test.
- M1: stage 1 + stage 2 boot to long mode. Test: serial prints `[boot] long mode ok`.
- M2: IDT, exceptions, PIC, PIT, serial logging. Test: deliberate `#UD` prints a register dump; PIT tick count increases.
- M3: VBE framebuffer, font, text console, keyboard. Test: screendump shows expected text; keystrokes echo (QEMU monitor sendkey).
- M4: E820, page allocator, heap. Test: alloc/free stress, no overlap.
- M5: scheduler + tasks. Test: two tasks interleave output on serial.
- M6: jump table + symbol table + embedded source + build generator. Test: symbol dump matches the build-time map.
- M7: shell (help, clear, reboot, syms, mem, tasks). Test: commands produce expected serial output.
- M8: Forge assembler. Test: bytes identical to NASM for every patchable module.
- M9: Forge editor + live patch + rollback + save. Test: live patch changes behavior; faulting patch rolls back; saved patch survives reboot.
- M10: Glass UI panes, pause, step, breakpoints, disassembler. Test: single-step a task, RIP advances correctly.
- M11: PCI + e1000 + Ethernet + ARP + IPv4 + ICMP. Test: ping 10.0.2.2 and get a reply.
- M12: UDP + DHCP + DNS. Test: DHCP lease; resolve `example.com`.
- M13: TCP. Test: fetch `http://example.com` raw over TCP.
- M14: browser v1 (HTTP). Test: example.com title and link visible in screendump.
- M15: crypto primitives. Test: all RFC vectors pass.
- M16: TLS 1.3 Phase A. Test: `https://example.com` with UNVERIFIED banner.
- M17: TLS Phase B. Test: valid chain passes, tampered cert rejected.

## 8. Working rules

- Fully autonomous: decide, document in `docs/DECISIONS.md`, continue.
- Tests are the only reviewer. Run the full `make test` after every milestone; regressions first.
- Debug with evidence: serial logs, `-d int,cpu_reset`, QEMU monitor, gdb.
- When stuck on a blocker after a serious effort: write it up in `docs/STATUS.md`, move to the next milestone that doesn't depend on it, come back later. Never mark a blocked milestone done.
- `docs/STATUS.md` is the handoff note: current milestone, what works, what's in progress, exact next action.
- Track image and module sizes in `STATUS.md`. Small is a feature. Small, readable code beats clever code.

## 9. Definition of done

All of M0 to M17 pass `make test`, or each remaining milestone is documented as blocked with evidence. Then write `docs/FINAL.md`: one-page summary, a demo script (boot, live-patch, watch in Glass, open a website), test results per milestone, image size and line counts per module, known limitations.
