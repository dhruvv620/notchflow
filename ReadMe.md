# NotchFlow

A personal macOS notch app based on [Atoll](https://github.com/Ebullioscopic/Atoll), with the original Atoll interface, two-finger tab navigation, gradient notch themes, Cuely scripts/transcription, Ask AI and an animated Focus companion.

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
GIT_LFS_SKIP_SMUDGE=1 git clone --branch feature/notch-themes-and-tab-swipes --single-branch https://github.com/dhruvv620/notchflow.git
cd notchflow
bash Build.command
```

The build first runs the AI process regression checks, then resolves the recorded Swift dependencies, compiles, locally signs and installs **`~/Applications/NotchFlow.app`**. No paid developer account is needed. Build.log appears beside Build.command. Dependencies and intermediate build files are reused under `~/Library/Caches/NotchFlow` to speed later builds; the first build still downloads dependencies.

Quit original Atoll and any other notch overlays, then open NotchFlow. Allow Accessibility and player Automation permissions when requested. If macOS blocks launch, use the app-specific Open Anyway action in Privacy & Security.

## Interaction and appearance

The original Atoll layout, tabs, music controls and hover behavior are restored. The previous custom music/Pomodoro/GIF panel has been removed.

With gestures enabled in settings, place the pointer over the expanded notch and swipe with two fingers: left selects the next visible tab, right selects the previous one. Navigation wraps at either end and skips disabled tabs. Reverse swipe gestures reverses the direction. Closed-notch music gestures retain their existing behavior. Horizontal swipes within the expanded notch now navigate tabs instead of skipping songs; use the music buttons to skip songs there.

In **Settings > Appearance > Notch color theme**, choose **Liquid graphite** (default), **Aurora**, **Sunset**, or **Classic black**. The expanded surface fades from black into the selected gradient, inspired by the supplied reference. The closed notch and camera area remain black.

## Cuely

Select **Cuely** in the notch's tabs (or the tab overflow menu). In Scripts, add a script, edit its title/text, then turn off Edit and press Start. Slow/Normal/Fast/Sprint controls the scrolling speed; the size slider changes the text. Pause and Rewind let you practice. Scripts are saved locally in `~/Library/Application Support/NotchFlow/Cuely/scripts.json`. Deletion asks for confirmation.

In **Live transcript**, press Record and allow Microphone and Speech Recognition access. Speech is recognized on-device; this requires on-device recognition support for the current system language. When unavailable, Cuely reports the limitation rather than sending audio to a remote service. It records the microphone only, not meeting/system audio. Stop recording to save the transcript as a script, or copy it at any time. Leaving Cuely or closing the notch stops recording; long recordings may end at the system recognition limit. The transcript itself stays in memory unless you save it as a script.

Cuely stays open while you read. It is visible in screen sharing: capture hiding is not implemented.

## Ask AI with Codex or Claude

Install the official Codex CLI or Claude Code on your Mac and complete sign-in by running it in Terminal. Open **Ask AI**, choose the provider, then send a message. Use Setup to choose an executable if it is not found automatically (common Homebrew, local npm and Codex.app locations are searched). If a CLI installed through a Node version manager cannot find Node, ensure Node is available in `/opt/homebrew/bin` or `/usr/local/bin`, or select an executable wrapper that configures its runtime.

This creates conversations through the command-line tools; it does not attach to existing Codex/Claude desktop chats. No API key is stored by NotchFlow. Text is sent to the selected provider using the CLI's existing sign-in and account terms. Codex runs in read-only mode in a temporary directory; Claude runs in print mode with built-in tools disabled. This is a text assistant, not a coding workspace or screen-reading agent.

Messages stay in app memory until New chat, switching providers, or quitting. The last 12 messages (up to 8,000 characters each) are included as context. Each message is limited to 16 KB and each request to two minutes. Stop cancels an active request. Temporary prompt/output files are removed when the process exits; provider-side storage follows the provider's policies. A request can finish while another tab is open.

## Focus companion

Select **Focus**, choose 1–180 minutes and press Start focus, or start a 5/15-minute break. Pause, resume and End session use the existing timer. Replacing a running timer asks for confirmation. The companion appears beside the closed-notch countdown with the existing timer's progress indicator and sound settings. Focus sessions do not automatically start a break.

A bouncing yellow character is included. **Choose character image / GIF** imports your own artwork (PNG/JPEG/GIF, up to 10 MB, 2048 × 2048 pixels and 300 frames) into local app storage. Choose Default character to reset it. Animation pauses with the timer and respects Reduce Motion. Character artwork such as SpongeBob can be supplied through this import control.

These tabs use the standard layout; turn off Minimalistic UI in Appearance if the tab bar is hidden.

## Validation

Run `bash Build.command` on macOS with Xcode 26+. On the Mac, verify left/right swipes, one tab change per flick (including momentum), disabled tabs, wraparound, reverse direction, scrolling lists, music buttons, open/close transitions, and all four themes. Also test script persistence and delete confirmation, teleprompter speeds, denied microphone/speech permissions, leaving Cuely during permission prompts, live transcription and saving, each signed-in CLI, invalid executable paths, cancellation, Focus pause/resume/breaks, timer replacement, custom GIFs and Reduce Motion. Native build and visual checks require macOS; they cannot run in the Linux editing environment.

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
