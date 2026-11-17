"""Personal stop words (realm, account number, ...) from tools/stopwords.local.txt.

The file is not in git: one word per line, lines starting with # are comments. Without it only the generic
stop words from snapshot.lua apply (plus the "no non-ASCII text in the snapshot" rule).
"""
import pathlib

LOCAL = pathlib.Path(__file__).resolve().parent / "stopwords.local.txt"


def local_words() -> list:
    if not LOCAL.exists():
        return []
    lines = LOCAL.read_text(encoding="utf-8").splitlines()
    return [w.strip() for w in lines if w.strip() and not w.lstrip().startswith("#")]
