"""Runs every test_* function in tests/test_*.py. Optional argv[1] filters by substring."""

import importlib
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from harness import TestFailure  # noqa: E402


def main():
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    here = os.path.dirname(os.path.abspath(__file__))
    mods = sorted(f[:-3] for f in os.listdir(here) if f.startswith("test_") and f.endswith(".py"))
    passed = failed = 0
    for modname in mods:
        mod = importlib.import_module(modname)
        for name in sorted(n for n in dir(mod) if n.startswith("test_")):
            full = f"{modname}.{name}"
            if flt not in full:
                continue
            t0 = time.time()
            try:
                getattr(mod, name)()
                passed += 1
                print(f"PASS {full} ({time.time() - t0:.1f}s)", flush=True)
            except TestFailure as e:
                failed += 1
                print(f"FAIL {full}: {e}", flush=True)
            except Exception:
                failed += 1
                print(f"FAIL {full}:\n{traceback.format_exc()}", flush=True)
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed or not passed else 0)


if __name__ == "__main__":
    main()
