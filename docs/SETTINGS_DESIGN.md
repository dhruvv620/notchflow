# Settings design standard

**Every change to a Settings page follows this file.** Read it (and `docs/SETTINGS.md`, which says
where settings go) before adding, moving or restyling anything in Settings. The building blocks are
in `DynamicIsland/components/Settings/SettingsKit.swift`; use them instead of drawing your own.

## A page, top to bottom

1. **Header**: drawn for every page by `SettingsForm` (`SettingsTabHeader` in `SettingsView.swift`):
   the page's icon in its group's colour, the title, **one plain sentence** (`SettingsTab.summary`),
   a status line (`SettingsTabStatus`), and, on a feature's page, its **main on/off switch**
   (`SettingsTab.masterKey`). Pages **don't draw their own header**; set those three things instead.
2. **Off state**: when the main switch is off, show one short line ("Off: … does nothing at all")
   and hide every other section.
   Pages are always one `Form` (grouped). No `GroupBox`, no `ScrollView` of boxes, no second `Form`
   inside a page: put shared parts in a `Group` of `Section`s so they join the page's form.
3. **Sections** in this order: the parts of the feature, how it behaves, connections (accounts,
   API keys, folders), then **Data** (reset, forget, delete) last.

```swift
// In SettingsView.swift: summary, masterKey (and a status case if it has one).
// The page itself starts with its sections:
Form {
    if !enabled {
        Section { Text("Off: Orbit does nothing at all.").font(.callout).foregroundStyle(.secondary) }
    } else {
        Section {
            SettingsToggle(key: .orbitLoops, title: "Loops", detail: "What's still open, in one list.")
        } header: { Text("Parts") }
    }
}
```

## Rows

| Row | Use | How |
|---|---|---|
| Switch | on/off | `SettingsToggle(key:title:detail:highlightID:)` |
| Choice | pick one | `Picker("Title", selection:)`; a long list as a menu, 2–4 short options `.segmented` |
| Slider | a number | `SettingsSlider(title:detail:value:range:step:valueText:)`: the slider and its value on the right (`0.3s`, `60%`) |
| Action | do something | `SettingsRowLabel` on the left, the button on the right |
| Status | how it's going | `SettingsStatus(text:kind:)` |
| Link | go elsewhere | a plain `Link`/button with the destination's name |

- Each row gets **at most one line** of explanation (`detail:`). Longer explanations go in the
  section's `footer`.
- Sub-options of a switch appear only while it's on, indented with `.padding(.leading, 16)`.

## Colours: one meaning each (`SettingsPalette`)

| Colour | Meaning |
|---|---|
| `accent` (macOS accent) | main actions, switches |
| `ok` (green) | working, connected, done |
| `warn` (orange) | needs you: disconnected, waiting, not set up |
| `danger` (red) | remove, reset, errors |

- **Sidebar icons and page headers use their group's colour**: General `general` (blue), In the
  notch `notch` (teal), Work `work` (purple), System `system` (grey). Never a per-page colour.
- Use system colours (`.primary`, `.secondary`) for text, so light and dark mode both work. No
  hard-coded white text except on a coloured tile.

## Buttons: three kinds

- **Main**: `.settingsPrimaryButton()`. At most **one per section**, for the action the section is for.
- **Normal**: the default button style. Everything else.
- **Destructive**: `.settingsDestructiveButton()` for remove, reset, forget, disconnect. If it
  can't easily be undone, it **asks first** with a `confirmationDialog`.

## Words

- Section headers in **sentence case**: "When the notch opens", not "When The Notch Opens".
- Short and plain, like talking to a friend. No jargon where a plain word works. No em dashes.
- Say what happens, not how it's built ("Your files aren't touched", not "uses a git worktree").

## The window

- A normal title bar (`SettingsWindowController`): no `.fullSizeContentView`, no transparent title
  bar, no `NavigationSplitView`. The sidebar and page are a plain `HStack` in `SettingsView`, so nothing
  is ever drawn under the window buttons. Don't change this to get a "seamless" look; it caused pages
  to slide under the title bar.

## The sidebar

- Groups: **General**, **In the notch**, **Work**, **System**, then About. Membership and order:
  `SettingsTab.group` and `availableTabs` in `SettingsView.swift` (see `docs/SETTINGS.md`).
- A page that needs the user (disconnected, failed, an error) shows an **orange dot**:
  add a case to `needsAttention(_:)` in `SettingsView.swift`.
- **Restart** and **Quit** sit at the bottom of the sidebar (`SettingsAppControls`), the same on every
  page; pages don't add their own.
- Every page has one background and one accent: `SettingsView` sets `.tint` and hides scroll
  backgrounds. Pages don't set their own `.tint`, background or brand colours.

## Search

Every switch and choice a user might look for has a `settingsHighlight` tag and a
`SettingsSearchEntry` with the same title (`tests/test_settings_integrity.py` checks this).

## Before you finish

- [ ] `summary` (and `masterKey` for a feature) set for the page; no page-drawn header
- [ ] Everything hidden while the feature is off
- [ ] Kit rows, one-line details, sentence-case headers
- [ ] One main button per section at most; destructive buttons ask first
- [ ] Only palette colours
- [ ] Search tags and entries; `python3 tests/test_settings_integrity.py` passes
