# NotchFlow

A personal macOS notch app based on [Atoll](https://github.com/Ebullioscopic/Atoll), with the original Atoll interface, two-finger tab navigation and gradient notch themes.

This is an independent customization, not an official Atoll release. The application name is NotchFlow; some inherited settings, icon artwork and internal types still use Atoll branding. Original copyrights, LICENSE, NOTICE, TRADEMARKS and COPYRIGHT_ASSETS remain applicable.

## Which branch to use

Use **`notchflow`** for the customized app. The fork's `dev` branch is the upstream reference and does not contain this interface. Do not sync upstream directly onto the custom branch without reviewing conflicts.

The initial custom branch is based on Atoll **v2.3.3-beta.3**, commit `c7305ecd1522ae8eb15b20d64c11d2105c62aa31`. It is not a promise of feature parity with later Atoll releases.

## Install on your Mac

Requires full Xcode 26 or newer and an internet connection. Open Xcode once and finish component installation. In Terminal:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -version
```

Download this branch with **Code > Download ZIP**, extract it, then type `bash ` in Terminal, drag **Build.command** into Terminal and press Return. Keep all extracted files together. You may run the script from any directory.

Alternatively, clone once:

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone --branch notchflow --single-branch https://github.com/dhruvv620/notchflow.git
cd notchflow
bash Build.command
```

The build resolves the recorded Swift dependencies, compiles, locally signs and installs **`~/Applications/NotchFlow.app`**. No paid developer account is needed. Build.log appears beside Build.command. Dependencies and intermediate build files are reused under `~/Library/Caches/NotchFlow` to speed later builds; the first build still downloads dependencies.

Quit original Atoll and any other notch overlays, then open NotchFlow. Allow Accessibility and player Automation permissions when requested. If macOS blocks launch, use the app-specific Open Anyway action in Privacy & Security.

## Interaction and appearance

The original Atoll layout, tabs, music controls and hover behavior are restored. The previous custom music/Pomodoro/GIF panel has been removed.

With gestures enabled in settings, place the pointer over the expanded notch and swipe with two fingers: left selects the next visible tab, right selects the previous one. Navigation wraps at either end and skips disabled tabs. Reverse swipe gestures reverses the direction. Closed-notch music gestures retain their existing behavior. Horizontal swipes within the expanded notch now navigate tabs instead of skipping songs; use the music buttons to skip songs there.

In **Settings > Appearance > Notch color theme**, choose **Liquid graphite** (default), **Aurora**, **Sunset**, or **Classic black**. The expanded surface fades from black into the selected gradient, inspired by the supplied reference. The closed notch and camera area remain black.

## Validation

Run `bash Build.command` on macOS with Xcode 26+. On the Mac, verify left/right swipes, one tab change per flick (including momentum), disabled tabs, wraparound, reverse direction, scrolling lists, music buttons, open/close transitions, and all four themes. Native build and visual checks require macOS; they cannot run in the Linux editing environment.

## Get future NotchFlow changes

For a Git clone, from its folder:

```bash
git pull --ff-only origin notchflow
bash Build.command
```

This retrieves changes already committed to **your custom branch**. It does not automatically integrate new Atoll releases. For a ZIP installation, download and extract a fresh custom-branch ZIP, then run its Build.command.

See [NotchFlow/UPDATING.md](NotchFlow/UPDATING.md) for upstream integration and testing.

## Validation status

The source customization was checked for patch applicability and Swift syntax relative to its upstream baseline; shell syntax was checked. The preparation environment is Linux, so a full Xcode compile, signing and runtime validation have **not** been completed. Build.command runs the included logic checks on your Mac before attempting the native build. Report failures with Build.log.

Test tab swipes, themes, music playback, sleep/wake and external displays after the first build. Rebuilding backs up an existing NotchFlow app. Settings use NotchFlow's own app identity.

## License and credits

Based on Atoll / DynamicIsland by the Atoll contributors, with its existing third-party dependencies and acknowledgments. Source is distributed under the accompanying GPL v3 license; added customization files use GPL-3.0-or-later. Preserve all existing license and asset notices when redistributing. No claim is made that inherited artwork is original NotchFlow artwork.

Upstream project documentation and credits: [Atoll](https://github.com/Ebullioscopic/Atoll/tree/c7305ecd1522ae8eb15b20d64c11d2105c62aa31).
