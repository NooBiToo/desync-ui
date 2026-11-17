"""Upload dist/ElvUI_DeSyncUI-<version>.zip to CurseForge (used by .github/workflows/release.yml).

  CF_API_KEY=<token> python tools/curseforge_upload.py --tag v1.0.1
  python tools/curseforge_upload.py --tag v1.0.1 --dry-run     # prints what would be sent, no token needed

The tag must equal "v" + "## Version" from the .toc; the project id comes from "## X-Curse-Project-ID".
The game version is derived from "## Interface" (16001 -> "1.60.1", the WoW Forever client).
Standard library only.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = "ElvUI_DeSyncUI"
API = "https://wow.curseforge.com/api"
REQUIRED = ("elvui_windtools", "elvui_mmediatag")


def parse_toc(text: str) -> dict:
    def field(name):
        m = re.search(rf"^## {name}:\s*(\S+)", text, re.M)
        return m.group(1) if m else None

    interface = field("Interface")
    return {
        "version": field("Version"),
        "interface": int(interface.split(",")[0]) if interface else None,
        "project_id": field("X-Curse-Project-ID"),
    }


def game_version_name(interface: int) -> str:
    return f"{interface // 10000}.{interface // 100 % 100}.{interface % 100}"


def check_tag(tag: str, version: str) -> None:
    if tag != f"v{version}":
        sys.exit(f"ERROR: tag {tag} does not match ## Version {version} in the .toc (expected v{version})")


def find_game_version_id(versions: list, name: str) -> int:
    ids = [v["id"] for v in versions if v.get("name") == name]
    if not ids:
        prefix = name.rsplit(".", 1)[0]
        close = sorted({v.get("name", "") for v in versions if str(v.get("name", "")).startswith(prefix)})
        sys.exit(f"ERROR: CurseForge has no game version {name}; close ones: {', '.join(close) or 'none'}")
    return ids[0]


def build_metadata(version: str, changelog: str, game_version_id: int, with_relations: bool = True) -> dict:
    meta = {
        "displayName": f"DeSync UI {version}",
        "changelog": changelog,
        "changelogType": "markdown",
        "gameVersions": [game_version_id],
        "releaseType": "release",
    }
    if with_relations:
        meta["relations"] = {"projects": [{"slug": s, "type": "requiredDependency"} for s in REQUIRED]}
    return meta


class CurseForgeError(Exception):
    """A refused API call; the body carries CurseForge's errorCode and errorMessage."""

    def __init__(self, code: int, body: str, path: str = ""):
        super().__init__(f"CurseForge {path} answered {code}: {body}")
        self.code, self.body = code, body
        try:
            self.error_code = json.loads(body).get("errorCode")
        except (ValueError, AttributeError):
            self.error_code = None

    @property
    def bad_relations(self) -> bool:
        # 1018: a relation slug is unknown to the API (the web page address is not always the API slug)
        return self.code == 400 and self.error_code == 1018


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8").stdout.strip()


def changelog_from_git(tag: str) -> str:
    prev = git("describe", "--tags", "--abbrev=0", f"{tag}^")
    span = f"{prev}..{tag}" if prev else tag
    lines = git("log", "--no-merges", "--format=- %s", span)
    return lines or "- Обновление"


def api(path: str, token: str, body: bytes = None, content_type: str = None):
    req = urllib.request.Request(API + path, data=body, headers={"X-Api-Token": token})
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        # CurseForge explains a refusal in the response body
        raise CurseForgeError(e.code, e.read().decode("utf-8", errors="replace"), path) from None


def multipart(metadata: dict, file: pathlib.Path):
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="metadata"\r\n'
        f"Content-Type: application/json\r\n\r\n".encode() + json.dumps(metadata, ensure_ascii=False).encode("utf-8"),
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{file.name}"\r\n'
        f"Content-Type: application/zip\r\n\r\n".encode() + file.read_bytes(),
    ]
    body = b"\r\n".join(parts) + f"\r\n--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    toc = parse_toc((ROOT / ADDON / f"{ADDON}.toc").read_text(encoding="utf-8"))
    check_tag(args.tag, toc["version"])
    if not toc["project_id"]:
        sys.exit("ERROR: add '## X-Curse-Project-ID: <id>' to the .toc")
    zip_path = ROOT / "dist" / f"{ADDON}-{toc['version']}.zip"
    if not zip_path.exists():
        sys.exit(f"ERROR: {zip_path} not found; run tools/build_release.py first")
    name = game_version_name(toc["interface"])
    changelog = changelog_from_git(args.tag)

    if args.dry_run:
        print(json.dumps(build_metadata(toc["version"], changelog, f"<id of {name}>"), ensure_ascii=False, indent=2))
        print(f"would upload {zip_path.name} to project {toc['project_id']}")
        return 0

    token = os.environ.get("CF_API_KEY")
    if not token:
        sys.exit("ERROR: CF_API_KEY is not set (GitHub secret CF_API_KEY)")
    versions = api("/game/versions", token)
    matches = [v for v in versions if v.get("name") == name]
    print(f"game versions named {name}: " + ", ".join(
        f"id {v.get('id')} (type {v.get('gameVersionTypeID')}, slug {v.get('slug')})" for v in matches))
    game_id = find_game_version_id(versions, name)
    upload = f"/projects/{toc['project_id']}/upload-file"
    meta = build_metadata(toc["version"], changelog, game_id)
    print("metadata: " + json.dumps(meta, ensure_ascii=False))
    try:
        result = api(upload, token, *multipart(meta, zip_path))
    except CurseForgeError as e:
        if not e.bad_relations:
            raise
        # the dependencies then come from the project's Default Relations tab on CurseForge
        print(f"WARNING: CurseForge refused the relation slugs ({e.body}); uploading without them. "
              "Set ElvUI WindTools and ElvUI mMediaTag as required in the project's Default Relations.")
        result = api(upload, token, *multipart(build_metadata(toc["version"], changelog, game_id, False), zip_path))
    print(f"uploaded {zip_path.name} as DeSync UI {toc['version']} (game version {name}): file id {result.get('id')}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CurseForgeError as err:
        sys.exit(f"ERROR: {err}")
