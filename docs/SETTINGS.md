# How Settings is organized

Read this before adding, moving or removing a setting. `tests/test_settings_integrity.py`
(run by `Build.command` and CI) checks the rules marked **checked**.

## The sidebar

| Group | Pages | What belongs here |
|---|---|---|
| (top, no header) | General, Appearance, Tabs & Features, Shortcuts | The notch as a whole: behavior, look, which tabs exist, keys |
| In the Notch | Music, Live Activities, Notifications & Calls, WhatsApp, Calendar & Todos, Timers, Shelf | One page per thing that shows up in the notch (a tab or a closed-notch activity) |
| Tools | Smart Tools, Notes, Clipboard, Screen Assistant, Color Picker, Terminal, Stats | Features you open and use |
| System | Controls, Battery, Devices, Download Alerts, Lock Screen | macOS integrations outside the notch panel |
| Extensions | Extensions | Third-party extensions |
| (bottom) | About | Version and updates |

The group of each page is set in `SettingsTab.group`, and the order in `availableTabs`
(`SettingsView.swift`). **Checked:** every page appears exactly once in the order.

## One home per setting

- A setting has **one** page. Don't put the same control on two pages. Write one line that
  points to the other page instead ("Lock screen widgets are on the Lock Screen page").
- The one exception is a feature's on/off switch. It may also appear in Tabs & Features >
  Features, which is the overview of everything that can be turned on.
- **Lock screen** widgets (media panel, timer, weather, reminders, calendar, battery, focus,
  glass) are on **Lock Screen**.
- **Look**: anything about the island's shape, colors, accent, motion and the app icon is on
  **Appearance**. Feature-specific looks (timer colors, visualizer) stay on that feature's page.
- **Closed-notch activities** belong to their feature's page (meeting countdown on Calendar &
  Todos, music on Music). Live Activities holds the system ones (recording, Focus, Caps Lock,
  camera and microphone).

## Adding a setting

1. Define the key next to the feature that reads it: `extension Defaults.Keys { static let ... }`.
2. Read it in the app. **Checked:** a key that nothing outside `components/Settings/` reads fails
   the test, because a switch nothing reads does nothing.
3. Add the control to the feature's page, inside a `Section` with a short header (Title Case),
   and a one-line caption (`.font(.caption).foregroundStyle(.secondary)`) if the label isn't obvious.
4. Tag it with `.settingsHighlight(id: highlightID("Its title"))` and add a `SettingsSearchEntry`
   with the same title. **Checked:** every search entry must point to a tagged control.
5. Use system colors (`.primary`, `.secondary`, `.accentColor`) in Settings, not `.white`, or
   the text disappears in light mode. White is fine only on a colored badge or preview.

## Removing a setting

1. Delete the key, its control and its search entry.
2. Add the key name to `SettingsCleanup.removedKeys`, so the stored value is cleared on launch.
   **Checked:** a removed key name can't be defined again (pick a new name instead).
