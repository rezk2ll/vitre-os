# Vitre dialect

The subset of NASM that patchable modules are written in. Forge, the in-OS assembler, accepts exactly this, and for the same source it produces the same bytes as NASM 2.16 with its default optimisation (`-Ox`).

## Modules

- A patchable module is one file, included once in the kernel image. Today there is one: `kernel/report.asm`.
- It holds functions with the usual header comment and the data they own (`db` strings and constants). No sections, no `.bss`, no macros, no `%` directives.
- Names it does not define are kernel labels and `equ` constants, resolved through the label table that `tools/gen.py` builds.

## Lines

- One statement per line. `;` starts a comment.
- `name:` defines a label. `.name:` is a local label, scoped to the last label without a dot, as in NASM.
- `name db ...`, `name dw ...`, `name dd ...`, `name dq ...` define data with a label. Items are numbers, character constants (`'x'`) and, for `db`, strings (`"..."`).
- `name equ expr` defines a constant.
- `times count db value` repeats one data item.

## Operands

- Registers: the 64-bit (`rax` to `r15`), 32-bit (`eax` to `r15d`), 16-bit (`ax` to `r15w`) and 8-bit (`al`, `cl`, `dl`, `bl`, `spl`, `bpl`, `sil`, `dil`, `r8b` to `r15b`) general registers. `ah`, `bh`, `ch` and `dh` are left out.
- Memory: `[rel label]` (RIP-relative), `[base + index*scale + disp]` with any of the parts, and `[disp]` (absolute, 32-bit). `byte`, `word`, `dword` or `qword` before `[` gives the size when no register operand does.
- Immediates and displacements are expressions: numbers (decimal or `0x` hex), character constants, labels and constants, joined with `+`, `-` and `*`.

## Instructions

mov, lea, add, sub, and, or, xor, cmp, test, inc, dec, shl, shr, sar, imul, mul, div, push, pop, call, ret, jmp, jcc, setcc, cmovcc, movzx, movsx, rep movsb, rep stosb. `call` and `jmp` also take `[rel label]`, which is how patchable code calls through the jump table.

## Encodings

Where NASM has a choice, Forge makes the same one:

- Jumps are short (rel8) when the target is in range, near (rel32) otherwise. Sizes are found by starting every jump short and lengthening the ones that do not fit until nothing changes.
- An ALU immediate (`add`, `sub`, `and`, `or`, `xor`, `cmp`) that fits a signed byte uses the imm8 form. Otherwise `al`, `eax` and `rax` use the short accumulator form, other registers the full immediate.
- `mov r64, imm` is `mov r32, imm32` when the value fits 32 unsigned bits, the sign-extended `mov r/m64, imm32` when it fits 32 signed bits, and `mov r64, imm64` otherwise.
- `mov reg, reg` and the other two-register ALU forms put the source in the ModRM reg field (opcodes 0x89, 0x01, ...).
- A zero displacement is left out, except after `rbp` and `r13`, which need a disp8 of 0. `rsp` and `r12` as a base always take a SIB byte.
- `shl`, `shr` and `sar` by 1 use the 0xd1 form.
- `imul reg, imm` is `imul reg, reg, imm`.
