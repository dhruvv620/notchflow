"""Keeps Settings tidy: no dead switches, every page reachable, search lands somewhere.

Run: python3 -m unittest tests.test_settings_integrity
See docs/SETTINGS.md for the rules these checks enforce.
"""

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "DynamicIsland"
SETTINGS_DIR = APP / "components" / "Settings"
SETTINGS_VIEW = SETTINGS_DIR / "SettingsView.swift"
CLEANUP = APP / "helpers" / "SettingsCleanup.swift"

KEY_DEFINITION = re.compile(r"static let (\w+)\s*=\s*(?:Defaults\.)?Key<")

# Keys the app may define without reading them outside Settings, with a reason.
ALLOWED_SETTINGS_ONLY = {}


def swift_sources():
    return {path: path.read_text(encoding="utf-8", errors="ignore") for path in APP.rglob("*.swift")}


class SettingsIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.sources = swift_sources()
        self.settings_view = SETTINGS_VIEW.read_text()

    def test_every_setting_is_read_by_the_app(self):
        """A switch nothing reads does nothing; remove it (and add it to SettingsCleanup)."""
        dead = []
        for path, text in self.sources.items():
            for key in KEY_DEFINITION.findall(text):
                if key in ALLOWED_SETTINGS_ONLY:
                    continue
                pattern = re.compile(r"\." + key + r"\b")
                read_outside_settings = any(
                    pattern.search(other)
                    for other_path, other in self.sources.items()
                    if SETTINGS_DIR not in other_path.parents
                )
                if not read_outside_settings:
                    dead.append(f"{key} ({path.relative_to(ROOT)})")
        self.assertEqual([], dead, "Settings that nothing in the app reads")

    def test_removed_settings_stay_removed(self):
        removed = re.findall(r'"(\w+)"', CLEANUP.read_text().split("removedKeys = [", 1)[1].split("]", 1)[0])
        self.assertTrue(removed)
        defined = {key for text in self.sources.values() for key in KEY_DEFINITION.findall(text)}
        self.assertEqual(set(), defined & set(removed), "A removed setting was defined again; pick a new key name")

    def test_every_page_is_in_the_sidebar(self):
        enum_body = self.settings_view.split("private enum SettingsTab: String", 1)[1].split("var id: String", 1)[0]
        cases = re.findall(r"^\s*case (\w+)\s*$", enum_body, re.M)
        ordered_body = self.settings_view.split("let ordered: [SettingsTab] = [", 1)[1].split("]", 1)[0]
        ordered = re.findall(r"\.(\w+),?", ordered_body)
        self.assertEqual(sorted(cases), sorted(ordered), "Every SettingsTab case appears once in the sidebar order")
        self.assertEqual(len(ordered), len(set(ordered)))

    def test_search_results_point_at_existing_controls(self):
        """Each search entry's highlight title must be attached to a control on some page."""
        entries = re.findall(r'SettingsSearchEntry\(tab: \.(\w+), title: "[^"]+".*?highlightID\(for: "([^"]+)"\)', self.settings_view)
        self.assertTrue(entries)
        all_settings_code = "\n".join(
            text for path, text in self.sources.items() if SETTINGS_DIR in path.parents
        )
        # Controls tag themselves with highlightID("Title") or a literal "tab-Title" id.
        missing = []
        for tab, title in entries:
            escaped = re.escape(title)
            tagged = (
                re.search(r'(?:highlightID|highlightProvider)\("' + escaped + r'"\)', all_settings_code)
                or re.search(r'settingsHighlight\(id: SettingsTab\.\w+\.highlightID\(for: "' + escaped + r'"\)\)', all_settings_code)
                or re.search(r'"' + re.escape(tab) + "-" + escaped + '"', all_settings_code)
            )
            if not tagged:
                missing.append(f"{tab}: {title}")
        self.assertEqual([], missing, "Search entries whose control no longer exists")


if __name__ == "__main__":
    unittest.main()
