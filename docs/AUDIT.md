# NotchFlow audit: performance, memory, security, code quality

Date: 21 November 2026. Scope: the whole app (430 Swift files, about 124,500 lines).

**How this was done.** A static review of the source: every timer and polling loop, animation, background process, web view and capture stream, every local network listener, how secrets are stored, how scripts and shell commands are built, and how the app is signed and updated. Nothing here was measured on a running Mac. The last section explains how to measure it.

## Summary

| Area | Verdict | Most important finding |
|---|---|---|
| CPU | Fair | 34 timers. Some poll every 0.1 to 3 s even when nothing changes. The music progress bar redraws at the screen's full refresh rate. |
| GPU | Fair | Three progress bars with no frame limit while music plays. Seven endless animations, which the Optimizer only partly calms. |
| Memory | Fair | Glance web pages stay loaded indefinitely, each in its own web process. The WhatsApp gateway adds a second process. The shelf thumbnail cache is unbounded. |
| Responsiveness | Needs work | Several waits block the main thread (`usleep` loops of up to 3 s, synchronous `ps`/`lsof`). Accessibility calls use a timeout in only 6 places. |
| Security | Needs work | Clipboard history stores passwords copied from password managers, in plain text. AI API keys sit in plain-text preferences. Installs skip Gatekeeper with no checksum check. |
| Good practice already in place | Strong | Local servers are loopback-only and authenticated. Sparkle updates are signed (EdDSA). AppleScript strings are escaped. Subprocesses get argument arrays, not shell strings. There is no `try!`. Pure-logic tests exist. |

## 1. CPU (processor)

### 1.1 Timers and polling (34 timers)

Timers routed through the Optimizer's `EnergyTimer` slow down on battery and pause when idle. These do: time tracking, meetings, clipboard, build jobs, copy action, agent follow. These do **not**, and run on their own:

| Where | Every | What it does | Fix |
|---|---|---|---|
| `managers/SystemMediaControllers.swift:778` | 0.15 s | Brightness polling, used when CoreBrightness notifications aren't available | Poll every 0.5 s, and stop after a few seconds with no change. |
| `managers/ScreenRecordingManager.swift:204`, `managers/ScreenAssistantManager.swift:315` | 0.1 s | Recording duration counters | Drive the label from a `TimelineView(.periodic(by: 1))` instead. |
| `managers/Glance/GlanceManager.swift:186` | 0.1 s | Watches for the Glance key being released (only while held) | Fine as is. |
| `components/Music/MusicVisualizer.swift:86` | 0.3 s | Visualizer bars | Pause when the notch is closed or music is paused (check it does). |
| `managers/StatsManager.swift:532`, `:621` | 0.5 s / setting | CPU, memory and network stats, plus a `/bin/ps` run (`:1455`) | Run only while the Stats tab is visible, and use the slowest interval when it isn't. |
| `managers/DoNotDisturbManager.swift:589` | 2 s | Reads the Focus assertions file | Watch the file with a `DispatchSource` (as notifications already do), and drop the poll. |
| `managers/BluetoothAudioManager.swift:212` | 3 s | Lists paired Bluetooth devices | Use `IOBluetoothDevice.register(forConnectNotifications:)` and per-device disconnect notifications. |
| `managers/SmartTools/FocusGuardManager.swift:48` | 3 s | Distraction meter | Route through `EnergyTimer`. |
| `MediaControllers/YouTube Music Controller/YouTubeMusicController.swift:303` | config | YouTube Music state | Route through `EnergyTimer`; stop when YouTube Music isn't the source. |
| `components/LockScreen/LockScreenWeatherWidget.swift:116`, `:187` | 15 s / 60 s | Lock screen weather | Run only while locked. |
| `managers/Productivity/PromiseKeeper.swift:101` | 30 s | Promise nudges | Fine, but could be one timer for the next due time. |
| `managers/TerminalManager.swift:457` | 1 s | Terminal "command finished" watch, only while a shell runs | Fine; could pause while no terminal tab exists. |

**Recommendation:** route every remaining repeating timer through `EnergyTimer`, so the Optimizer's battery and idle rules cover the whole app, not part of it.

### 1.2 Heavy helper programs

| Where | Program | When | Cost | Fix |
|---|---|---|---|---|
| `managers/BluetoothAudioManager.swift:1977` | `ioreg -r -l -w 0` | Every AirPods listening-mode event | Dumps the **entire** I/O registry (megabytes of text) to find one value | Query only the AirPods' service: `ioreg -r -c <class> -k <key>`, or read it in-process with `IOServiceGetMatchingServices`. |
| `managers/DoNotDisturbManager.swift:544` | `log show --last … --debug` | At launch | `log show` with `--debug` can take seconds of CPU | Drop it, or limit it to a few minutes and run it at low priority (it's only the starting state). |
| `managers/BluetoothAudioManager.swift:1367` | `pmset -g accps` | On battery refreshes | Small | Fine. |
| `managers/KeyboardBrightnessSensor.swift:112`, `managers/SystemDisplayManager.swift:62` | `corebrightnessdiag status-info` | Fallback brightness reads | A process per read | Make sure this never sits inside the 0.15 s polling path; cache the method that works. |

## 2. GPU and drawing

1. **Music progress bars redraw at full frame rate (60 or 120 times a second) while music plays.** This is the single biggest avoidable drawing cost while the notch is open.
   - Where: `components/Notch/NotchHomeView.swift:277`, `components/Notch/MinimalisticMusicPlayerView.swift:783` and `components/LockScreen/LockScreenMusicPanel.swift:537` all use `TimelineView(.animation(paused:))` with no `minimumInterval`.
   - Fix: add `minimumInterval: 0.5`. The bar moves about a pixel a second, so nobody sees a difference.
2. **Seven `repeatForever` animations.**
   - Where: call screen, WhatsApp refresh, Settings, downloads spinner, Notes, LocalSend picker, Optimizer.
   - The Optimizer's "Calm endless animations" covers only some of them.
   - Fix: give each a stop condition, so it isn't animating while hidden.
3. **Several 1-second `TimelineView`s** (call timer, peek line, agents, Glance clocks). These are fine: they run only while visible.
4. **Metal visualizer** (`metal/visualizer.metal`). Runs only when the visualizer is on. The Optimizer turns it off on battery. Fine.
5. **Glance.**
   - Live app-window panels capture at 12 fps, and only while the board is open. Fine.
   - The board's blur materials are cheap.

## 3. Memory

| Item | Where | Size (typical) | Fix |
|---|---|---|---|
| Glance web pages | `managers/Glance/GlanceWebPanels.swift` | Each page runs a WebKit content process, often 50 to 200 MB | Unload pages not shown for 10 minutes, and unload all of them under memory pressure (`DispatchSource.makeMemoryPressureSource`), not only on battery. |
| WhatsApp gateway (GOWA, Go) | `managers/WhatsApp/WhatsAppGatewayProcess.swift` | A separate process, roughly 50 to 120 MB, whenever WhatsApp is on | Expected. Point it out in Settings so people know what it costs. |
| Terminal sessions | `managers/TerminalManager.swift` | Each tab keeps its scrollback (setting) and a shell | Fine. Closing a tab frees it. |
| Shelf thumbnails | `components/Shelf/Services/ThumbnailService.swift:31` | `[String: NSImage]` with no limit | Use `NSCache` with a count or cost limit. |
| Window stash previews | `managers/Productivity/WindowStash.swift` | One screenshot per stashed window | Fine; drop previews of windows that closed. |
| Lyrics cache | `managers/MusicManager.swift:518` | Capped at 80 | Good. |
| WhatsApp messages | `managers/WhatsApp/WhatsAppManager.swift:136` | Capped at 200 per chat | Good. |
| Notification history | `Communications/NotificationHub.swift:392` | Capped | Good. |
| Singletons | 128 `static let shared` objects | Each lives for the whole run | Check at launch that disabled features never create or start their manager. WhatsApp and Glance already behave; spot-check the rest. |

## 4. Responsiveness (main thread)

The main thread draws the notch. Anything that waits on it causes a pause or a spinning beachball.

1. **Waiting loops on the main thread.**
   - Where: `managers/WhatsApp/WhatsAppGatewayProcess.swift:122` and `:147` use `usleep` loops of up to 3 s while stopping the gateway or an orphaned one, plus a synchronous `ps` at `:155`. They run when WhatsApp is switched off, restarted or the app quits.
   - Fix: stop the process on a background queue, and use `terminationHandler` instead of polling.
2. **Synchronous subprocesses on the main thread.** `TerminalManager.currentDirectory` (`lsof`) runs on a button click. `AppLocationMover`, `FocusHistory`, `SystemOSDManager` (`killall`, `launchctl`) run several, some at launch. Fix: run them with `async` / `terminationHandler` off the main thread.
3. **Accessibility calls have no timeout in most places.**
   - The app reads and moves other apps' windows through Accessibility in 7 files, but `AXUIElementSetMessagingTimeout` is used in only 6 places.
   - If an app is busy or hung, each call can block for about 6 seconds.
   - Fix: set a 0.5 to 1 s timeout on every application element (or once on the system-wide element), and keep heavy walks (Glance's menu search, setups) off the main thread.
4. **Blocking semaphores.** `components/Shelf/…` has 5 `semaphore.wait(timeout: 5–10 s)` calls, and 2 untimed `sem.wait()` calls in `Ext+FileProvider.swift`. Make sure none runs on the main thread; convert to `async`.

## 5. Security

### High

1. **Clipboard history saves passwords, in plain text.**
   - `managers/ClipboardManager.swift` records whatever is copied. It doesn't skip the markers that password managers (1Password, Bitwarden, Keychain Access) put on secrets: `org.nspasteboard.ConcealedType` and `TransientType`. The Copy Action feature does skip them (`CopyActionManager.swift:88`).
   - The history is then saved to `UserDefaults` ("ClipboardHistory", `:489`). That is a plain-text file any app running as you can read, and it ends up in backups.
   - Fix:
     - Skip concealed, transient and auto-generated clipboard types.
     - Optionally ignore apps the user lists.
     - Move the stored history to a file only the user can read (0600), or keep it in memory only.
2. **AI API keys and an old Spotify token are stored in plain-text preferences.**
   - `geminiApiKey`, `openaiApiKey`, `claudeApiKey`, `groqApiKey` (Screen Assistant, `models/Constants.swift:1074–1077`).
   - `spotifyAuthAccessToken` (`:960`, from the older Spotify sign-in).
   - The newer AI providers and the Spotify connection already use the Keychain (`SecretStore`). Move these keys there too, migrating them once and then deleting the preference.

### Medium

3. **Installing skips Gatekeeper with no integrity check.**
   - `install.sh` downloads the zip from GitHub over HTTPS, then clears the quarantine flag (`:92`, `:128`) without verifying a checksum or signature.
   - The app isn't notarized; it's signed with a local or self-made identity (`Build.command:318`).
   - If the GitHub account or release were compromised, friends would run whatever was uploaded, with no warning.
   - Fix:
     - Publish a SHA-256 with each release, and check it in `install.sh` before unzipping.
     - Better still, check the Sparkle EdDSA signature that releases already carry.
     - Long term: a Developer ID certificate and notarization.
   - Sparkle updates themselves are signed (`Release.command:209`, `SUPublicEDKey` in `Info.plist`), so updates are protected; first installs are not.
4. **`com.apple.security.cs.disable-library-validation` is on.**
   - With hardened runtime, this still lets the app load libraries that aren't signed by you.
   - NotchFlow holds Accessibility, Full Disk Access, Screen Recording, Automation and Input Monitoring, so injected code would inherit all of them.
   - Fix: remove it, unless a specific bundled library needs it; if one does, sign that library with the same identity.
5. **LocalSend trusts any certificate.**
   - `components/Shelf/Services/LocalSendService.swift:1061` accepts any server certificate, so someone on the same Wi-Fi could intercept files you send.
   - LocalSend devices announce a certificate fingerprint. Fix: accept only the certificate matching the device you picked.
   - The register listener (`:621`) listens on all network interfaces. Confirm it only answers discovery and never accepts files on its own.
6. **Glance HTML widgets can read their whole folder.**
   - `GlanceWebPanels.swift:167` gives a chosen HTML file read access to its entire folder. Pages can also go online.
   - A downloaded HTML file in `~/Downloads` could therefore read other files there and send them out.
   - Fix: allow read access only to that one file (or to the agent widgets folder), and warn when adding an HTML file from outside it.

### Low

7. **Logging.** There are 423 `print` and 135 `NSLog` calls.
   - `NSLog` writes to the system log in release builds.
   - Screen Assistant prints your prompts and the AI's replies (`ScreenAssistantManager.swift:366`, `:850`, `:903`).
   - Fix: a single `Logger` with `.private` for anything containing user text, and debug-only `print`s.
8. **Message text stored in preferences.**
   - Promises (`promisesData`) keep snippets of your messages in plain-text preferences.
   - Low risk, but the same fix applies: a 0600 file in Application Support, or Keychain-protected storage.

### Already done well

- **Agent bridge (`notchflow` command):** loopback only, a random bearer token compared in constant time, and the token file is 0600 (`AgentBridgeServer.swift`, `AgentHub.swift:197`).
- **WhatsApp:**
  - The webhook accepts loopback only and HMAC-SHA256-signed bodies.
  - The gateway runs on loopback with a fresh random password each launch, its web UI and MCP turned off, and checks its download against the release's checksum.
- **Spotify:**
  - Sign-in uses PKCE with a state check, and the refresh token is kept in the Keychain.
  - The callback listener is loopback-only and closes itself.
- **Scripts and commands:** AppleScript strings are escaped everywhere (`NotchNotificationPolicy.appleScriptString`, the music and terminal scripts); subprocesses get argument arrays, not shell strings; terminal paths are shell-quoted.
- **Updates and errors:** Sparkle updates are EdDSA-signed; there are no `try!` calls and only 3 `fatalError` calls.

## 6. Code quality and maintainability

1. **Very large files.**
   - `SettingsView.swift` is 8,089 lines (every settings page in one file).
   - Also large: `ContentView.swift` (3,045), `BluetoothAudioManager.swift` (2,688), `DynamicIslandApp.swift` (1,834).
   - Split Settings into one file per page (several pages already are), and split Bluetooth into discovery, battery and listening mode.
2. **Swift 5 language mode with concurrency warnings.**
   - Recent builds failed on main-actor mistakes that Swift 6 checking would catch earlier.
   - Turn on "Strict Concurrency Checking: Targeted" and fix warnings one module at a time.
3. **Many singletons (128), mostly main-actor.** Fine for an app like this, but it makes testing hard. New logic should keep following the pattern already used: pure `…Policy` types with tests.
4. **467 `try?`.** Errors are often silently dropped (network, AppleScript, file writes). Where the user would care (sending a message, saving a setup), surface the error. The newer features do this; older code mostly doesn't.
5. **Tests exist, but CI runs few of them.**
   - `Build.command` runs about 35 pure-logic test suites.
   - The GitHub workflow (`.github/workflows/notchflow-ci.yml`) runs only about 5.
   - Fix: make CI call the same list (one script both use), plus `tests/*.py`.
6. **Leftovers.**
   - The older Spotify sign-in (`spotifyAuthAccessToken`, `SpotifyLoginSheet`) overlaps the new Spotify connection.
   - Two brightness readers both use `corebrightnessdiag`.
   - Remove or merge them.

## 7. Fix plan, in order

| # | Fix | Effort | Effect |
|---|---|---|---|
| 1 | Clipboard: skip password-manager copies; store history privately | Small | Closes the biggest privacy hole |
| 2 | Move the Screen Assistant API keys and the old Spotify token to the Keychain | Small | Secrets out of plain-text preferences |
| 3 | `minimumInterval: 0.5` on the three music progress timelines | Tiny | Biggest GPU/CPU saving while music plays with the notch open |
| 4 | Accessibility timeouts everywhere; gateway stop and subprocesses off the main thread | Small | No more beachballs from busy apps |
| 5 | `install.sh` checksum (or EdDSA) verification | Small | Safe first installs for friends |
| 6 | Remove `disable-library-validation` (if nothing needs it) | Tiny | Smaller attack surface |
| 7 | `ioreg` narrowed to the AirPods' entry; drop or shorten the launch `log show` | Small | Removes the heaviest helper-process work |
| 8 | Route all repeating timers through `EnergyTimer`; Bluetooth and Focus to notifications | Medium | Lower idle CPU and battery use |
| 9 | Glance: unload idle web pages and on memory pressure; `NSCache` for thumbnails | Small | Caps memory growth |
| 10 | LocalSend certificate pinning; Glance HTML read access limited to the file | Small | Closes the LAN and file-read risks |
| 11 | CI runs every test suite; one logging helper with privacy | Small | Catches regressions; quieter logs |
| 12 | Split `SettingsView.swift`; stricter concurrency checking | Medium to large | Faster builds, fewer surprise compile errors |

## 8. How to measure on your Mac

1. **Activity Monitor.**
   - Search "NotchFlow". Watch **Memory**, **% CPU** and **Energy Impact** with the notch closed, then open, then with music playing.
   - Also check its helper processes: `whatsapp` (the gateway) and "NotchFlow Web Content" (Glance pages).
2. **Settings › Optimizer.** It shows NotchFlow's own memory, CPU and estimated wake-ups per second, live.
3. **From the terminal.**
   - `top -pid $(pgrep -x NotchFlow)`: CPU over time.
   - `footprint NotchFlow`: real memory, including graphics.
   - `sudo powermetrics --samplers tasks --show-process-energy -i 5000 | grep -i notch`: energy and wake-ups.
4. **Instruments** (comes with Xcode).
   - Time Profiler: where CPU goes.
   - Allocations / Leaks: memory growth.
   - Energy Log: wake-ups and GPU.
   - Record with the notch closed for a minute, then open with music playing, and compare.

Good targets for an app like this, with the notch closed and nothing playing:
- **CPU:** under 0.5% on average.
- **Wake-ups:** under 5 a second.
- **Memory:** under 200 MB, not counting the WhatsApp gateway and Glance pages.
