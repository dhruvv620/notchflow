# NotchFlow

A personal macOS notch app based on [Atoll](https://github.com/Ebullioscopic/Atoll), with a compact music preview, Pomodoro timer and custom idle GIF.

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

The build runs standalone interaction/timer checks, resolves the recorded Swift dependencies, compiles, locally signs and installs **`~/Applications/NotchFlow.app`**. No paid developer account is needed. Build.log appears beside Build.command. Dependencies and intermediate build files are reused under `~/Library/Caches/NotchFlow` to speed later builds; the first build still downloads dependencies.

Quit original Atoll and any other notch overlays, then open NotchFlow. Allow Accessibility and player Automation permissions when requested. If macOS blocks launch, use the app-specific Open Anyway action in Privacy & Security.

Original upstream LFS video assets are not used by the custom panel, which uses static album art and your imported GIF. Cloning with LFS smudging skipped avoids downloading those videos.

## Interaction

| Action | Behavior |
| --- | --- |
| Idle | Small notch with chosen GIF or default sparkle |
| Hover | Compact artwork, title, artist and playback controls; no calendar |
| Click | Expanded Music and Pomodoro tabs |
| Leave hover preview | Preview closes |
| Leave clicked panel | Panel stays open |
| Click outside or Close | Expanded panel closes |

Click the sliders icon beside the tabs to import a GIF or change Pomodoro settings. GIF limits: 20 MB, 2048 x 2048 pixels and 300 frames. Focus defaults to 25 minutes, short break 5, long break 15, with a long break after four completed focus sessions. Phases advance automatically; pause/resume, skip and reset are included. Editing durations resets the cycle.

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

Test hover/click/outside-close behavior, music playback, GIF import, Pomodoro transitions, sleep/wake and external displays after the first build. Rebuilding backs up an existing NotchFlow app; it does not replace original Atoll or Atoll DV. Settings/imported GIFs use NotchFlow's own identity and do not automatically migrate from Atoll DV.

## License and credits

Based on Atoll / DynamicIsland by the Atoll contributors, with its existing third-party dependencies and acknowledgments. Source is distributed under the accompanying GPL v3 license; added customization files use GPL-3.0-or-later. Preserve all existing license and asset notices when redistributing. No claim is made that inherited artwork is original NotchFlow artwork.

Upstream project documentation and credits: [Atoll](https://github.com/Ebullioscopic/Atoll/tree/c7305ecd1522ae8eb15b20d64c11d2105c62aa31).
