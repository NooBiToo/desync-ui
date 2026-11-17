"""Build ElvUI_DeSyncUI/Profile.lua from the author's ElvUI saved settings.

Usage (from the project root):
  .venv\\Scripts\\python tools\\export_profile.py --sv <ElvUI.lua> --key "<profile>" --version N --out ElvUI_DeSyncUI\\Profile.lua

Reads the game's SavedVariables file as plain Lua data (in an empty environment), never writes to it.
All cleaning rules live in tools/snapshot.lua.
"""
import argparse
import pathlib
import sys

import lupa.lua51 as lua51

from stopwords import local_words

ROOT = pathlib.Path(__file__).resolve().parent.parent


def lua_runtime():
    rt = lua51.LuaRuntime()
    snapshot = rt.execute((ROOT / "tools" / "snapshot.lua").read_text(encoding="utf-8"))
    snapshot.AddStop(rt.table_from(local_words()))
    load_data = rt.eval(
        'function(code) local f = assert(loadstring(code, "=savedvariables")); '
        "local env = {}; setfenv(f, env); f(); return env end"
    )
    return rt, snapshot, load_data


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sv", required=True, help="path to WTF/.../SavedVariables/ElvUI.lua")
    ap.add_argument("--key", required=True, help="ElvUI profile name to export")
    ap.add_argument("--version", required=True, type=int, help="snapshot version (raise when the look changes)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    _, S, load_data = lua_runtime()
    try:
        env = load_data(pathlib.Path(args.sv).read_bytes())
        src = S.Build(env.ElvDB, env.ElvPrivateDB, args.key, args.version)
    except lua51.LuaError as e:
        print(f"ERROR: {e}")
        return 1
    out = pathlib.Path(args.out)
    out.write_text(src, encoding="utf-8", newline="\n")
    print(f"written {out} ({out.stat().st_size} bytes), snapshot version {args.version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
