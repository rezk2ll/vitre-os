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
