# NotchFlow fresh start

This branch starts from **Atoll v2.3.3 stable**, commit `e21cdf7b10e62e82ddbc9c23158e6e8cf5b21cf5`.
It retains upstream controls and adds compact Music, Todos, Clipboard and timer views, trackpad tab navigation, tab organization, and shared appearance controls. The earlier custom panels, AI chat, Cuely, mascots and gradient themes are not included.

Original Atoll source, licensing, notices and artwork remain in place. NotchFlow has its own app identity and preference domain, so it starts with upstream defaults rather than old experimental settings. Official Atoll auto-updates and legacy extension servers are disabled in this personal build.

## Install and iterate on your Mac

Use Xcode 26+ and Git LFS. Keep original artwork by allowing `git lfs pull`; skipping LFS leaves placeholder files instead of the original animations.

For an existing single-branch clone:

```bash
cd ~/notchflow
git status
git remote set-branches --add origin fresh/reminders-liquid-glass
git fetch origin
git switch --track origin/fresh/reminders-liquid-glass
bash Build.command
```

Save uncommitted work before switching. If this local branch already exists, use `git switch fresh/reminders-liquid-glass` and `git pull --ff-only`.

`Build.command` uses cached packages and a Debug build and installs `~/Applications/NotchFlow.app`. When Xcode has an Apple Development (or Developer ID) identity, the script reuses it so privacy grants remain attached to the same signed application identity. It falls back to ad-hoc signing without a paid developer account, with a warning that Accessibility may then require reapproval after rebuilding. Before replacing the installed bundle, the script asks every running NotchFlow copy (including legacy `.dev` and timestamped backup copies) to terminate, waits up to ten seconds, and aborts without moving anything if one remains alive. This prevents a live process from being renamed into `NotchFlow Backup …` and receiving a separate permission record. Existing app backups are kept under `~/Library/Application Support/NotchFlow/Build Backups` rather than beside the live app, preventing several backup copies from appearing as indistinguishable permission rows. The full build output is saved as `Build.log` next to the script.

For the fastest edit/build/run loop, open `DynamicIsland.xcodeproj`, choose scheme **DynamicIsland**, destination **My Mac**, configuration **Debug**, and use Command-R. The product is NotchFlow.app. To build the optimized configuration with the script:

```bash
NOTCHFLOW_CONFIGURATION=Release bash Build.command
```

Native Liquid Glass requires macOS 26+. Earlier supported systems use a frosted material. The existing app's deployment target is macOS 14.6.

## Apple Reminders

In the standard layout, select the checklist tab to open Todos. Use Open and Done to switch incomplete/completed items; the header summarizes overdue and today counts, and pages keep the rows within the selected island size. Allow Reminders access when requested. Choose All Lists or a specific Apple Reminders list, add a reminder with the + button, optionally set a date and time, and use the circle to complete it. Done shows completed items and lets you mark them incomplete again. The Todos title menu selects the Apple Reminders list.

Data is read and saved directly through Apple's EventKit store; there is no separate task database or account login. Cloud synchronization follows the account configured in Apple Reminders. Undated reminders are included. Read-only lists remain visible, and creation uses a writable list. The panel refreshes after saves, when EventKit reports a change, and when the app becomes active.

Use **Settings > Tabs & Features > Tabs** to control visibility and order; the Features segment enables the underlying tools. The tab bar is part of Standard UI; if Minimalistic UI is enabled, switch back to Standard to use it. The Todos tab and the separate upcoming-reminder activity are off by default. Enable either one explicitly; disabling the activity removes reminder takeovers from the closed notch without affecting Apple Reminders data.

The Allow button brings NotchFlow forward for the macOS prompt. It shows a waiting state, reports refusals/errors, and offers Open Privacy Settings and Check Access even if the prompt stalls. If access is denied, open **System Settings > Privacy & Security > Reminders**, grant access and choose Check Access. If no lists exist, create one in Apple Reminders first. Errors stay visible and failed saves do not hide reminder rows.

### Natural reminder dates

Type a title followed by a date phrase, for example `Send invoice by tomorrow 7 pm`. The Add form previews the recognized phrase, cleaned title and due date before saving. You can edit the date/time or choose **Keep as text** to prevent interpreting that phrase.

The parser runs locally with the Mac's calendar and time zone. It supports `today`, `tomorrow`, AM/PM, noon/midnight, 24-hour times, weekdays, ISO dates, English month dates and durations such as `in 30 minutes` or `in 2 days at 8 pm`. A time without a day uses its next occurrence. A day without a time stays all-day. Explicit `today 7 am` remains today even when that time has passed. Invalid or ambiguous input is left as text; nonexistent daylight-saving times are rejected, and repeated times choose the first occurrence. Date words are recognized as a complete trailing phrase; this is not a cloud AI parser.

## Compact clipboard and gestures

Clipboard keeps the latest 20 recent copied items, with All/Links/Colors/Images/Code/Text filters and a paginated row of compact preview cards. Click a card to copy the original content again; a green check confirms success. Copying a card does not create another history entry. Re-copying the same content in another app moves it to the front. Clear asks for confirmation. Previously pinned items remain available in the legacy clipboard interface separately.

Clipboard and Reminders use the same panel width and height as Music. Their contents scroll or paginate instead of expanding the notch. Additional tabs use tighter icon spacing or an overflow menu to stay within the original header width.

With gestures enabled, a two-finger horizontal swipe over the expanded panel selects the next/previous visible tab; one gesture selects one tab and momentum is ignored. Direction respects Reverse swipe gestures. Vertical content scrolling remains inside the tab, and closed-notch media swipes retain their existing behavior.

Glass has a shape-matched near-transparent backing so the inside of the expanded panel receives clicks. A native input-region bridge follows the visible shape and releases the old expanded area immediately on collapse, including when a close animation still retains a larger backing window. Read-only mouse monitors preserve hover activation while outside clicks pass through. Clipped corners and outer margins remain transparent. Root click-to-open applies only to the closed notch. Mouse drag recognition starts only after actual movement, preserving button clicks. These input changes still require verification against real windows on the Mac.

## Music, timers and tab organization

Music is a single full-width Now Playing panel with a media-source picker, fixed 84-point artwork, progress and playback controls. Playing and pausing never enlarge its artwork. Today/calendar content no longer appears alongside it. Calendar is a separate optional tab, hidden by default. The Mirror camera control opens a small popover rather than expanding the Music layout.

The header always uses an icon strip, with the selected icon moving smoothly during navigation. It sits below the physical camera so the entire row can use the panel width; additional extension icons scroll into view instead of replacing the strip with a dropdown. Frosted uses native behind-window blending to sample the desktop and apps behind the panel. Header and content share one surface and a gentle full-panel accent wash, without a painted black header band or a separate artwork rectangle.

### System media and source selection

Automatic follows the system Now Playing session: browser video, movies and music from apps that publish macOS media metadata. Use the source button at the upper right of Now Playing to pin Spotify, Apple Music or another installed supported player, then choose Automatic to follow the system again. Selecting an app does not start playback. Refresh reconnects system updates; Open app opens the current source. This update selects Automatic once and restores the compact music activity/visualizer; later source choices persist.

Detection and transport commands both use the original bundled MediaRemote adapter through its system Perl host, including on macOS 15.4+. The app no longer silently substitutes Apple Music based on OS version or switches to Pear Desktop without a source choice. Diff updates preserve unchanged artwork, handle explicit removals, accept fractional timestamps and maintain the playback clock through pause/resume. Streams are stopped when switching sources and refreshed after wake. Apps that do not publish system media metadata cannot supply titles/artwork through Automatic.

Timers contains **Timer**, **Pomodoro** and **Stopwatch** sections. Drag the ruler with the mouse to set a timer or focus duration; use the settings popover for exact hours/minutes/seconds and break options. Pomodoro defaults to 25-minute focus, 5-minute breaks and a 15-minute long break after four sessions, then repeats. Its pause/resume/reset state is shared with the compact live activity. Stopwatch elapsed time survives tab changes and sleep while the app is running. Starting a new Timer or Pomodoro asks before replacing an active timer; external Clock timers remain controlled by Clock.

**Settings > Tabs & Features** has pinned Tabs and Features segments. Show/hide tabs, drag native list rows to reorder, use accessible move-up/down actions or reset the layout. The header, horizontal swipes and indicators share that order. Hidden tabs keep their position; hiding a tab does not disable its service. Features groups the tool switches and links to their detailed settings. Music remains the fallback if every tab is hidden.

Clipboard cards use the native pointing-hand cursor. Slides use one stable clipped viewport, continuous card edges and cached, downsampled high-quality previews; decoded thumbnails do not inherit navigation animations. Originals remain intact for copying.

## Appearance

Settings > Appearance now contains:

- **Elements:** Subtle, Graphite and Gradient card treatments.
- **Island:** Compact, Spacious, or Custom width/height; expanded corner radius; Black, Dynamic, Glass or Frosted background; optional outline. Width is bounded by the display, and custom height ranges from 200–420 points.
- **Accent:** Adaptive (current artwork), System, or Fixed with white/blue/purple/pink/green/orange/cyan swatches and a custom color picker. The resolved accent reaches selected tabs/chips, music playback/progress/visualizers and normal timer controls. Semantic error, overdue, category and list colors remain meaningful. Adaptive artwork colors have a minimum brightness for dark-surface contrast.
- **Artwork glow:** controls the existing blurred artwork backdrops and accent shadows without modifying album artwork.
- **Motion:** combines the app's Reduce Motion option with macOS accessibility preferences, suppressing SwiftUI transitions and pausing native spectrum/waveform animations.
- **Carousel:** optional bottom page indicators, displayed as Dots or Icons. They reuse the existing inset and can select a tab.

Black keeps the classic opaque background. Dynamic uses the resolved accent in a dark gradient. Glass uses the public native Liquid Glass API on macOS 26+ and falls back to a frosted material on older supported systems. Frosted uses a regular material. The closed notch stays black; the expanded surface continues behind navigation around the physical camera. Reduce Transparency makes the surface opaque. The old single Glass switch migrates to the new Glass option once. No private glass API is added by these controls.

Compact keeps Clipboard and Todos at Music's original panel size. Spacious and Custom apply consistently to these tabs. Compact uses 640 × 200 points regardless of enabled tab count. Spacious uses 720 × 240; Timer reserves up to 224 points in Compact. Other utilities add at most 40 points automatically, with scrolling for larger content. Custom sizing remains an explicit choice.

## Verification

GitHub's **NotchFlow Native Build** workflow compiles Debug on macOS 15 and Release on macOS 26 with Xcode 26+ and pinned packages, checks privacy declarations, and runs isolated Reminders/date-parser/clipboard/timer/tab-order/Shelf-cleanup/input-region/system-media regression executables. A separate Swift/Linux job compiles and runs the pure Foundation date, clipboard, timer, tab-order, Shelf-cleanup and system-media checks independently of macOS runner capacity. Build logs and Xcode result bundles are retained as workflow artifacts. These are compile and logic checks, not a claim of visual or account-sync validation.

The regression checks use a fake service and never request access to real reminder data. To run them manually on a Mac:

```bash
xcrun swiftc -swift-version 5 -parse-as-library \
  DynamicIsland/models/ReminderItem.swift \
  DynamicIsland/Providers/RemindersServiceProviding.swift \
  DynamicIsland/managers/RemindersManager.swift \
  tests/RemindersRegression.swift -o /tmp/NotchFlowRemindersRegression
/tmp/NotchFlowRemindersRegression
```

Before merging, verify on an interactive Mac:

- Music opens without an adjacent Today/calendar panel; optional Calendar and Mirror popover still work. Compact tabs have consistent widths and modest heights; original shelf and open/close interactions still work.
- All four backgrounds, three element styles, size presets/custom sliders, corner radius/outline, adaptive and fixed accents, artwork glow, reduced motion, both indicator styles, bright/dark wallpapers, and older-macOS fallback. Change tracks and confirm the visualizer and progress update with Adaptive accent.
- Todos Open/Done paging and due summaries, date detection preview/manual override/Keep as text, and Reminders permission grant/denial/revocation, zero lists, read-only lists, very long titles, undated and date-only reminders, timed reminders, completed toggle, create/complete failures and changes made in Apple Reminders.
- Clipboard retains exactly the latest 20 recent items after 21 external copies, repeated external copies move to the front, clicking a card preserves full original content without adding duplicates, filters/pages remain valid, and clear requires confirmation.
- A quick horizontal flick changes one tab, vertical scrolling does not navigate, disabled tabs are skipped, and reverse direction works. Clipboard/Reminders match Music's panel dimensions.
- Close the notch with the pointer outside its closed shape and immediately click controls throughout its former expanded area; those clicks must reach the background app, with no invisible blocked rectangle. Test repeated open/close, trackpad drag, mouse-down outside, and display changes.
- Artwork remains 84 points during repeated Play/Pause; header and content share one continuous background on light/dark desktops, without a black header seam or square artwork backdrop. All standard tab icons remain in the top strip and the selected icon follows swipes.
- Automatic with Safari/Chrome YouTube, QuickTime/IINA or another Now Playing-enabled video player, Spotify, track changes, pause/resume, empty metadata and sleep/wake; pin Spotify while video plays, return to Automatic, and verify old helpers stop on source changes.
- Native list drag reordering upward/downward and multiple rows, visibility toggles, scroll/restart, and saved order across header/swipes/indicators.
- Timer/Pomodoro/Stopwatch start, pause, resume and reset; short/long break boundaries, compact controls, replacing an existing timer, sleep/wake, and switching tabs while running.
- Tabs & Features visibility and drag ordering persist after restart and agree across header, swipes and indicators; hiding every tab keeps a usable fallback.
- Hover every clipboard card for a hand cursor; swipe repeatedly between image-heavy Clipboard and Music on Retina displays and verify clean borders and stable columns.
- Place a clickable control behind the expanded glass: interior clicks must stay in the notch, nested buttons must work, and transparent corners/margins must still pass clicks through.
- Scrolling remains inside reminder content, typing does not close the composer, permission denial or a slow prompt offers actionable feedback, manual Check Access accepts changed permissions, and sleep/wake/fullscreen do not leave stale panels.

The editing environment is Linux. It cannot provide a real notch screenshot or verify iCloud synchronization; those remain explicit Mac acceptance checks.

## Design and media references

- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials): standard materials for content, restrained glass on controls, contrast and accessibility.
- [SwiftUI Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): one coherent material treatment and limited effect layering.
- [SwiftUI native row movement](https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove(perform:)): native list destinations and reordering.
- [MediaRemote adapter documentation](https://github.com/ungive/mediaremote-adapter#readme): system-hosted stream/transport commands on modern macOS, diff semantics and timestamps.

## Communications prototype

Enable **Settings > Communications > Enable Communications**, select notification/call apps, then use **Allow Access** to grant macOS Accessibility access. Return and choose **Check Access**. This feature is off by default. Notification permission for NotchFlow's own alerts does not grant access to other apps' notifications.

Accessibility belongs to the exact bundle identifier and signing identity, not the visible app name. Debug and Release now share one NotchFlow bundle identifier, and a one-time migration preserves missing settings from the former `.dev` preference domain. If Privacy & Security shows duplicate NotchFlow rows or Check Access remains unavailable, choose **Repair Stale Entries** in Communications settings (or **Repair** in the Notifications tab), approve the new macOS prompt for the currently running copy, and return to NotchFlow. **Reveal This NotchFlow** locates that copy in Finder. Repair resets only the current and former NotchFlow Accessibility records; it does not change other applications' permissions.

A Notifications tab joins the existing icon strip (and can be hidden/reordered in Tabs & Features). It keeps up to 20 observed notifications in memory until cleared or the app quits. Native Notification Center cards must be exposed and visible; this does not import private notification databases, encrypted message histories or every background push. Reply/Open/Dismiss are advertised only for live exposed actions. Historical cards offer Open app. Reply uses the native card's editor and Send action after the same source/sender/body is revalidated; no coordinate clicks, keyboard injection or automatic replies are used. Some native layouts do not expose Reply or an editable field; Open app remains the fallback. Instagram/browser notifications are conditional on a recognizable native app header.

Incoming call controls temporarily take priority over the current tab without destroying its view or reply draft. A closed-notch activity leaves the physical camera clear; hover/tap expands the existing panel for actual available call controls. Ongoing calls show a duration marked **Detected** when no real connection timestamp is provided. Selecting a tab can return to other content during an ongoing call; incoming calls retain priority. A positive call from an observed app is excluded from Automatic Music metadata. Merely using the microphone, playing audio or having a window title is not enough to declare a call.

This first integration targets **English, exposed native UI** in FaceTime/iPhone-on-Mac, WhatsApp Desktop, Teams and Zoom, including native call banners where a clear app header and Answer/Decline pair exist. It is an Accessibility-based conditional prototype, not a universal CallKit observer or a guarantee across app/OS updates. iPhone calling must already be configured on the Mac. Native CallKit's CXCallObserver is not available to this native macOS target. Web meeting tabs, hidden/unsupported controls and localized layouts can remain undetected; use the source app in those cases. A verified call window can remain observed while minimized. End/Decline dispatch native actions and wait for observed disappearance; source-app confirmation dialogs are not automatically accepted, and host-wide End meeting for all is not offered as an ordinary hangup.

Call activity takes precedence over notification previews and music. Previews hide when the Mac locks; Focus can suppress new notification/ringing alerts using the app's existing Focus detection. Turn previews off independently. Sources and memory/history controls are grouped in Notifications and Calls settings segments. All AX traversal runs on bounded worker queues, not the UI thread.

The prior window-layout crash is addressed by explicitly disabling NSHostingView-driven window sizing and safe-area feedback: the AppDelegate owns the frame, and hosting content autoresizes inside it. Input-region refreshes caused by native frame changes are deferred/coalesced. Native regression checks animate changing content against explicit frame sizes and verify first-click behavior and frame ownership.

Validation includes synthetic notification parsing, source/action filtering, call classification, ring priority, bounded history/stale actions and a native animated-hosting regression. These tests do not send real messages or place calls. Before relying on the prototype, verify on your Mac: grant/deny/revoke Accessibility; Messages/WhatsApp visible banners and a deliberate test reply; FaceTime/Continuity answer/decline; Teams/Zoom join/mute/leave plus native confirmation; minimized/background windows; call end/missed call and two simultaneous sources; previews off, Focus/lock, sleep/wake; composition preempted by a call; and repeated opening/closing without a blocked background area or layout crash.

API references: [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement), [User notification scope](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter), [Call observer platform availability](https://developer.apple.com/documentation/callkit/cxcallobserver).
