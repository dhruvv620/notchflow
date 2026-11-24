# NotchFlow: notes for coding agents (Codex, Cursor and others; same as CLAUDE.md)

## Settings (required)
Any change to Settings (adding, moving, restyling or removing a setting or page) must follow:
- `docs/SETTINGS_DESIGN.md`: how a page looks (header, kit rows, colours, buttons, words). Use the
  kit in `DynamicIsland/components/Settings/SettingsKit.swift`.
- `docs/SETTINGS.md`: where each setting lives, keys, search entries, removing settings.
Run `python3 tests/test_settings_integrity.py` before finishing.

## General
- Every feature has an on/off switch, and off means it does nothing (no observers, timers or memory).
- Pure logic lives in `DynamicIsland/helpers/*Policy.swift` with tests in `tests/`, run by `Build.command`.
- Add a line to `CHANGELOG.md` under Unreleased for anything a user would notice.
- Writing for users: short, plain words, no em dashes.
