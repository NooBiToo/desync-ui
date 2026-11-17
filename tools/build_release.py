"""Build the CurseForge upload: dist/ElvUI_DeSyncUI-<version>.zip (one folder ElvUI_DeSyncUI inside).

  .venv\\Scripts\\python tools\\build_release.py

Refuses to build if any text file of the addon carries personal data or MerathilisUI leftovers
(the stop words come from tools/snapshot.lua, the same list the snapshot is checked with).
"""
import pathlib
import re
import sys
import zipfile

import lupa.lua51 as lua51

from stopwords import local_words

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = "ElvUI_DeSyncUI"
TEXT = {".lua", ".toc", ".xml"}
# only what an addon needs ships; anything else (logs, backups, .orig, desktop.ini) stops the build
ALLOWED = TEXT | {".tga", ".blp", ".ttf", ".otf", ".ogg", ".mp3"}


def stop_words():
    S = lua51.LuaRuntime().execute((ROOT / "tools" / "snapshot.lua").read_text(encoding="utf-8"))
    return [S.STOP[i] for i in range(1, len(S.STOP) + 1)] + local_words()


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    src = ROOT / ADDON
    toc = (src / f"{ADDON}.toc").read_text(encoding="utf-8")
    m = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    if not m:
        print("ERROR: no ## Version in the .toc")
        return 1
    version = m.group(1)

    words = stop_words()
    files = sorted(p for p in src.rglob("*") if p.is_file())
    problems = []
    for p in files:
        if p.suffix.lower() not in ALLOWED:
            problems.append(f"{p.relative_to(ROOT)}: unexpected file type, not shipped")
        elif p.suffix.lower() in TEXT:
            text = p.read_text(encoding="utf-8")
            for w in words:
                if w in text:
                    problems.append(f"{p.relative_to(ROOT)}: {w}")
            if re.search(r'\["mui"\]|\.mui\b', text):
                problems.append(f"{p.relative_to(ROOT)}: mui")
    if problems:
        print("ERROR: build stopped (personal data, MerathilisUI leftovers or unexpected files):")
        for line in problems:
            print("  " + line)
        return 1

    out = ROOT / "dist" / f"{ADDON}-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, f"{ADDON}/{p.relative_to(src).as_posix()}")
    for p in files:
        print("  " + f"{ADDON}/{p.relative_to(src).as_posix()}")
    print(f"built {out} ({out.stat().st_size} bytes, {len(files)} files, version {version})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
