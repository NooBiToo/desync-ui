"""Run the headless Lua 5.1 specs for ElvUI_DeSyncTools.

Usage (from the project root): .venv\\Scripts\\python tests\\run.py
"""
import pathlib
import sys

import lupa.lua51 as lua51

ROOT = pathlib.Path(__file__).resolve().parent.parent


def run_python_tests() -> int:
    """tests/test_*.py (release tooling) through unittest."""
    import unittest
    print("== python tests")
    suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_*.py")
    result = unittest.TextTestRunner(stream=sys.stdout, verbosity=1).run(suite)
    return 0 if result.wasSuccessful() else 1


def main() -> int:
    status = run_python_tests()
    for spec in sorted((ROOT / "tests").glob("*_spec.lua")):
        print(f"== {spec.name}")
        rt = lua51.LuaRuntime()  # fresh globals per spec file
        rt.globals().ROOT = ROOT.as_posix()
        rt.globals().SPEC = spec.as_posix()
        try:
            rt.execute("dofile(SPEC)")
        except lua51.LuaError as e:
            print(f"ERROR: {str(e).splitlines()[0]}")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
