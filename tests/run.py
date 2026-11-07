"""Runs every test_* function in tests/test_*.py, several at a time.

Optional argv[1] filters by substring. JOBS sets how many run at once.
"""

import importlib
import os
import sys
import time
import traceback
from concurrent.futures import ProcessPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from harness import TestFailure  # noqa: E402


def run_one(full):
    modname, name = full.split(".")
    t0 = time.time()
    try:
        getattr(importlib.import_module(modname), name)()
        return True, f"PASS {full} ({time.time() - t0:.1f}s)"
    except TestFailure as e:
        return False, f"FAIL {full}: {e}"
    except Exception:
        return False, f"FAIL {full}:\n{traceback.format_exc()}"


def main():
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    here = os.path.dirname(os.path.abspath(__file__))
    mods = sorted(f[:-3] for f in os.listdir(here) if f.startswith("test_") and f.endswith(".py"))
    tests = [f"{m}.{n}" for m in mods for n in sorted(dir(importlib.import_module(m)))
             if n.startswith("test_") and flt in f"{m}.{n}"]
    jobs = int(os.environ.get("JOBS") or os.cpu_count() or 1)
    passed = failed = 0
    with ProcessPoolExecutor(max_workers=jobs) as pool:
        for fut in as_completed([pool.submit(run_one, t) for t in tests]):
            ok, line = fut.result()
            passed += ok
            failed += not ok
            print(line, flush=True)
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed or not passed else 0)


if __name__ == "__main__":
    main()
