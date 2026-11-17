"""Unit tests for tools/curseforge_upload.py (pure parts; no network)."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "tools"))
import curseforge_upload as cu  # noqa: E402

TOC = """## Interface: 16001
## Title: DeSync UI
## Version: 1.0.1
## X-Curse-Project-ID: 123456
Core.lua
"""


class TocTests(unittest.TestCase):
    def test_parse_toc_reads_version_interface_and_project(self):
        self.assertEqual(cu.parse_toc(TOC), {"version": "1.0.1", "interface": 16001, "project_id": "123456"})

    def test_parse_toc_without_project_id(self):
        self.assertIsNone(cu.parse_toc(TOC.replace("## X-Curse-Project-ID: 123456\n", ""))["project_id"])

    def test_interface_to_game_version_name(self):
        self.assertEqual(cu.game_version_name(16001), "1.60.1")   # WoW Forever client 1.60.1
        self.assertEqual(cu.game_version_name(11507), "1.15.7")
        self.assertEqual(cu.game_version_name(120105), "12.1.5")


class TagTests(unittest.TestCase):
    def test_tag_must_match_toc_version(self):
        cu.check_tag("v1.0.1", "1.0.1")
        with self.assertRaises(SystemExit):
            cu.check_tag("v1.0.2", "1.0.1")
        with self.assertRaises(SystemExit):
            cu.check_tag("1.0.1", "1.0.1")


class VersionLookupTests(unittest.TestCase):
    VERSIONS = [{"id": 1, "name": "1.15.7"}, {"id": 2, "name": "1.60.1"}, {"id": 3, "name": "11.2.0"}]

    def test_finds_the_game_version_id_by_name(self):
        self.assertEqual(cu.find_game_version_id(self.VERSIONS, "1.60.1"), 2)

    def test_unknown_version_fails_and_names_close_ones(self):
        with self.assertRaises(SystemExit) as e:
            cu.find_game_version_id(self.VERSIONS, "1.60.2")
        self.assertIn("1.60.1", str(e.exception.code))


class MetadataTests(unittest.TestCase):
    def test_metadata_marks_windtools_and_mmediatag_required(self):
        m = cu.build_metadata("1.0.1", "- fix", 2)
        self.assertEqual(m["displayName"], "DeSync UI 1.0.1")
        self.assertEqual(m["gameVersions"], [2])
        self.assertEqual(m["releaseType"], "release")
        self.assertEqual(m["changelogType"], "markdown")
        slugs = {p["slug"]: p["type"] for p in m["relations"]["projects"]}
        self.assertEqual(slugs, {"elvui_windtools": "requiredDependency", "elvui_mmediatag": "requiredDependency"})


if __name__ == "__main__":
    unittest.main()
