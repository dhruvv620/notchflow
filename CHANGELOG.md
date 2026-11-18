# Changelog

All notable changes to Atoll will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Agent conversations in the notch**: the AI Agents tab now lists your live sessions and your recent Claude Code and Codex sessions (last two weeks, from the files they keep), and shows the whole conversation of the one you pick: your messages, the agent's replies, and its steps folded into one line per run. It follows the session live as the agent works, wherever it runs. Type underneath to keep it going: a Claude Code session waiting in its terminal gets your message there; otherwise NotchFlow resumes the session in the background in its folder (claude -p --resume / codex exec resume) and the reply streams into the tab, with approvals in the notch. **New** runs Claude Code and Codex tasks right in the notch (Terminal is an option). Approvals now always come to the notch, even when the agent's terminal is in front (the old behavior is an option in Settings > AI Agents).
- **AI Agents: more agents, and work with them from the notch**: Connect **Codex** (approve and follow progress; trust the hooks once in Codex's /hooks), **Cursor** (approve risky shell commands and MCP tools; ordinary commands follow Cursor's own rules) and **Gemini CLI** (progress, "needs you" and done) next to Claude Code in Settings > AI Agents, each with a backup and a clean Disconnect. **New task** in the AI Agents tab starts Claude Code, Codex, Gemini CLI or Cursor Agent in a new Terminal or iTerm window with your prompt in the folder you pick; recent folders are remembered. **Reply from the notch**: when Claude Code finishes a turn, its session shows a reply button; what you type there wakes Claude and it carries on. Agents waiting in their own window (for example Gemini asking for permission) make the closed notch pulse amber too; click to bring the window forward.
- **AI Agents** (new tab and Settings > AI Agents): connect Claude Code with one click and approve it from the notch. When Claude Code would ask "Allow this?", the notch glows amber and its AI Agents tab shows the command or file with **Allow**, **Always allow** (when Claude Code offers a rule; never for destructive commands), **Deny** (with an optional note telling Claude what to do instead) and **Ask in its window**. Claude's multiple-choice questions can be answered there too. The closed notch shows what each session is doing ("notchflow · Running npm test"), and a green check with Claude's summary when it finishes; the tab lists every session with a button to bring its terminal forward. Risky commands (rm -rf, sudo, force push, curl | sh, writes to ~/.ssh) are marked. Nothing is ever approved on its own: if you don't answer in time (2 minutes by default), if NotchFlow is closed, or if Claude's terminal is already in front of you, Claude Code asks in the terminal as usual. Connecting adds hooks to ~/.claude/settings.json (keeping your own, with a backup), and Disconnect removes only NotchFlow's.
- **The notchflow command** (~/.local/bin/notchflow): `notchflow ask "Deploy?" --options "Deploy,Cancel"` waits for your choice in the notch and prints it, `notchflow notify "Backup done"` shows a message under the notch, `notchflow status` checks the connection. It talks to NotchFlow over a loopback-only connection with a token only your account can read.
- **Share NotchFlow with friends**: `bash Release.command` publishes a GitHub release (NotchFlow.dmg, NotchFlow.zip, install.sh and a signed update feed). Friends install with one Terminal line or the DMG, and get later versions from **Check for Updates…** (menu bar icon and Settings > About) or the daily automatic check. Updates now come from NotchFlow's own releases instead of Atoll's.
- **Cuely, rebuilt as a voice-following teleprompter**: your saved scripts sit in a list on the right (new, edit, duplicate and delete from the list; word count and reading time on each). In **Follow voice**, press Start reading and read aloud: Cuely listens, matches what you say to the script, dims what you have read, lights up the next word and scrolls so the line you are on stays near the top. Skipped words, misheard words and re-reading a sentence are handled; click any word to jump there. Nothing is recorded or saved, and the script's words are given to the recognizer as hints. **Auto-scroll** keeps the fixed-speed scroll. A size button makes Cuely Large or Extra large (wider and taller), and the script list can be hidden for more room.
- **Smart Tools** (new Settings > Smart Tools page):
  - **Distraction meter**: during a Pomodoro focus block, when YouTube, X or another listed site is the front browser tab (Safari, Chrome, Arc, Brave, Edge), or a listed app is in front, the notch glows amber and shows the site and "3 min off track" for the block so far. Off by default.
  - **Copy-to-action**: copy a tracking number (UPS, FedEx, USPS, Amazon, postal), a date, an address, a flight number, an e-mail, a phone number or a sum, and the closed notch offers Track, Add to Calendar (opens Calendar with the event filled in), Directions (Apple Maps), Call, Email or the answer, for nine seconds. Text marked secret by password managers is skipped.
  - **Smart replies with your MiniMax key**: a sparkles button above WhatsApp and notification replies asks MiniMax for three short replies; tap one to put it in the field. The key is kept in the Keychain; the API address and model can be changed, and a Test button checks them. Nothing is sent until you tap.
  - **People pins**: pin up to five WhatsApp chats (right-click a chat in the WhatsApp tab); they sit as faces in the Shelf corner, and dropping files on a face sends them on WhatsApp.
  - **Build watcher**: with a GitHub token (kept in the Keychain) and a list of repositories, running GitHub Actions show a spinner in the closed notch, then Passed in green or Failed in red; click to open the run. Terminal commands started with the `nf` shell function (copy it from Settings) are watched the same way.
- **Lyrics button in the Music tab**: a lyrics button in the Now Playing header (and the Lyrics control slot) shows or hides a lyrics panel under the player, with the previous, current and next lines and a highlight sweeping across the sung line. The notch grows to fit it and shrinks back when it is hidden. Lyrics no longer appear under the artist name on their own.

### Changed
- **Swipe through the clipboard**: with the pointer over the clipboard cards, a three-finger page swipe (when macOS is set to swipe between pages with three fingers) goes to the next or previous page, with a slide. Two-finger swipes still switch tabs everywhere, including over the clipboard. The arrows still work.
- **Copy-to-action has its own temporary tab**: clicking the closed notch always opens it, so the action buttons there could not be clicked. Now the closed notch only previews what you copied (for 10 seconds), and a **Copied** tab appears first in the tab bar. The notch opens on it when you hover or click, with large Track / Add to Calendar / Directions / Call / Email buttons and the copied text. The tab disappears 30 seconds after the copy (the countdown pauses while you look at it) or as soon as you use an action, and the notch moves back to your usual tab.
- **Settings reorganized**: the sidebar is now General, Appearance, Tabs & Features and Shortcuts at the top, then **In the Notch** (Music, Live Activities, Notifications & Calls, WhatsApp, Calendar & Todos, Timers, Shelf), **Tools** (Smart Tools, Notes, Clipboard, Screen Assistant, Color Picker, Terminal, Stats), **System** (Controls, Battery, Devices, Download Alerts, Lock Screen) and Extensions. Every setting has one home: lock screen widgets and glass only on Lock Screen (removed from Music, Calendar, Timers and Appearance), the music live-activity switch and visualizer coloring on Music, the reminder activity only on Calendar & Todos. Tabs & Features lists every switchable feature, including the new closed-notch ones, without duplicate links. Appearance is grouped into Elements, Island, Accent, Motion (with the simpler close animation), Carousel, Notch, Closed Notch, Extras and App icon.
- **Unfolding animation is now optional and off by default**: Settings > Appearance > Unfold content out of the notch. Without it the notch opens with the quicker fade.
- **Up next**: the Music tab shows what plays next under the artist when there is room (Spotify's queue through the signed-in web session, or the following tracks of the playing Apple Music playlist when not shuffled). Click it for the next five and pick one to skip ahead to it.
- **Sing along under the closed notch** (Settings > Media, with lyrics on): while a song with synced lyrics plays, the line being sung shows under the closed notch, tinted with the album color, and a highlight sweeps across it in time with the music (30 fps). Instrumental stretches show a pulsing note; Peek takes the line's place while you hover.
- **Pomodoro history and Focus**: completed focus sessions are recorded (90 days kept, sessions finished during sleep counted too), and the Pomodoro section shows the last seven days as bars with today's minutes, the week's total and your streak. Optionally, Pomodoro runs a Shortcut when focus starts and another on breaks or when stopped, so a Focus can turn on and off with it (make two shortcuts with Set Focus and name them in the Pomodoro settings).
- **Todos from anywhere and today's progress**: drop text, a link, a file or an email address on the Todos tab to add it as a todo (a trailing date such as "tomorrow 7 pm" is read like in the Add form), or choose Add to Todos on a notification or a WhatsApp chat ("Reply to Selene: …"). When the closed notch is otherwise idle and todos are due today, it shows a progress ring with done/total (overdue todos count as due); off with Settings > Calendar > Show today's progress.
- **Shelf quick actions**: selecting files on the Shelf shows an action bar: Resize (half size, fit 2048 px or 1080 px), PDF, Cut Out (remove background), Zip, AirDrop, and WhatsApp, which sends the files to one of your recent chats through the linked account (images as photos, other files as documents). Results land back on the Shelf.

### Fixed
- **"Unable to Check For Updates" on launch**: local builds from Build.command no longer start the updater (they update with git pull); Check for Updates is shown only in release builds made with Release.command. About no longer lists the update settings twice.
- **Settings that did nothing were removed**: the custom music animation ("Coming soon") and Lottie visualizer list, colour history size, timer input style and preset-list switches, expanded shelf drag area, album-art blur (replaced by Artwork glow), the Atoll release name, and ten other stored settings no code read. Their saved values are cleared once on launch. Unused code from Atoll was deleted too (custom updater windows, old status bar menu, AirDrop and drag views, volume manager, HUD debugger).
- **The accent color now reaches everything**: timer icons, system indicators and HUDs used an old accent setting that could no longer be changed (stuck on blue); they now follow the accent chosen in Appearance.
- **Light mode**: a Download Alerts label was drawn in white and disappeared in light mode.
- **Notch shook when switching tabs**: SwiftUI's own requests to resize the notch window during layout are now ignored (the app owns the window size) instead of being applied a moment late, where they fought the app's resize.
- **Lyrics under the closed notch now follow the lyrics button**: with lyrics turned off in the Music tab, no lyrics show under the closed notch either.
- **Crash while the notch resized**: SwiftUI's hosting view could resize the notch window from inside the window's own layout pass (`windowDidLayout`), which invalidated the layout of a scroll view mid-pass; AppKit then threw and the app aborted. The notch window now holds any resize requested during its layout pass and applies the newest one right after it.
- **Shelf right-click actions were missing for files**: Open, Open With, Image Actions and Compress depended on a file location that was never filled in after bookmark resolution was made asynchronous, so they never appeared and their handlers did nothing. Resolved locations are now cached as items load.
- **Better incoming calls**: the call card shows the caller's photo from Contacts (or colored initials) with a pulse while it rings, their latest message from the last 15 minutes as the likely reason for the call, and a Message menu next to Decline with quick replies or a custom message. Declining with a message sends it through the linked WhatsApp account for WhatsApp calls, or through Messages to the caller's number from the call or Contacts. Contacts access is requested the first time a call needs it.

### Fixed
- The privacy configuration test still required the speech-recognition entitlement removed in 001435b, and pinned the old AppleScript usage text.
- **Meetings in the notch** (Settings > Calendar): five minutes before an event with a Zoom, Google Meet, Teams, Webex or similar link (from its conference field, URL, location or notes), the closed notch shows the meeting, a live countdown and a Join button that stays for the first ten minutes. When the meeting starts, playing music pauses, and resumes when it ends if NotchFlow paused it.
- **Opens on the tab that fits the moment** (Settings > General, on by default): Calendar from five minutes before a meeting until it ends, Timers while one runs, WhatsApp when there are unread messages, Notifications when something arrived since you last looked, Music while something plays, in that order and only among visible tabs. With nothing going on, the usual tab is kept. An announced notification or WhatsApp message still opens on itself.
- **Peek before opening** (Settings > General, off by default): hovering the closed notch first shows a one-line preview of what matters now (a running timer, the playing song, a meeting within the hour, unread WhatsApp and notifications, or the time and battery). Click to open; with Open notch on hover on, keeping the pointer there for under a second more opens it too. Accidental passes over the notch no longer open the whole panel.
- **Wallpaper accent and glass tones**: a new Wallpaper accent picks the most vibrant color of the desktop picture (sampled from a small thumbnail off the main thread, refreshed when the Space, display or picture changes), and Adaptive now falls back to it instead of the system accent when nothing is playing. Glass and Frosted backgrounds gain a Glass tone: Dark (as before), Light, Tinted with the accent, or Clear.
- **Content unfolds out of the notch**: opening no longer grows an empty panel and then fades the content in. The header and tab content start folded against the notch's top edge, as narrow as the camera housing, and unfold with the panel on a spring, slightly behind the shape; closing folds them back in. Scale and opacity only, no per-frame blur. Reduce Motion (NotchFlow's or the system's) gets a plain cross-fade.
- **Shared design kit**: `NotchDesignKit.swift` defines one set of spacing, radius, type and motion tokens and the building blocks every tab can share: card, row, badge, chip, icon button, pill button, section header, empty state and compose field. Notifications and WhatsApp now use it, so their cards, filters, buttons, empty states and reply fields look and behave alike.
- **Adaptive tab heights**: each tab declares how tall the open notch should be, relative to the chosen panel size, in one rule table shared by the window, the visible panel and the view model (which previously each kept their own list). Timer keeps its 224-point floor, Terminal is 40 points taller, WhatsApp 60 points taller, and Notifications follows its content: a short inbox gives a shorter notch (down to 40 points below the preset), a long one grows up to 60 points. Switching tabs animates the height; a growing window is enlarged before the panel animates and a shrinking one is fitted after, so nothing is clipped mid-animation.
- **Notifications, rebuilt**: the Notifications tab now collects every app's notifications from Notification Center's own store (with Full Disk Access), so notifications arrive even when their banner was missed and the inbox survives relaunches (up to 200, kept on this Mac). On-screen banners still add their native Reply/Open/Close actions, and WhatsApp messages from the linked gateway join the inbox. Notifications are grouped by app with per-app filter chips, expand on click, and show Reply, Open and a menu on hover. Replies are sent inline: through the WhatsApp gateway, through Messages (by AppleScript, using the conversation Notification Center records), or through the live banner. Dismiss one, clear an app, or clear everything with a few seconds to Undo; mute an app from its menu. New notifications are announced in the closed notch with the app icon, and opening the notch lands on that notification. Notification Center is only read, from a private copy, never changed.
- **WhatsApp in the notch (experimental)**: a WhatsApp tab lists recent chats with unread counts, opens a conversation beside the list, and sends replies without leaving the notch. New messages are announced in the closed notch; opening the notch while one shows goes straight to that chat. Link once from Settings > WhatsApp by scanning a QR code with your phone (WhatsApp > Settings > Linked devices). It runs through [GOWA](https://github.com/aldinokemal/go-whatsapp-web-multidevice), an open-source WhatsApp multi-device gateway that NotchFlow downloads on request (checked against the release's published SHA-256), runs on 127.0.0.1 only behind a per-launch password, and stops when NotchFlow quits. New messages arrive at once through a signed local webhook. Groups can stay quiet unless you are mentioned, announcements can pause during a Focus, chats can be ignored, and read receipts are sent only when you open a conversation (or, with that off, only when you reply). Unofficial and off by default; enable it under Tabs & Features.

### Changed

### Fixed
- **Notch closing or crashing on external displays and when reopened quickly**: windows were tracked by `NSScreen` object, which AppKit replaces on every display change (attaching, waking or rearranging a monitor), so every notch window was torn down and rebuilt, sometimes during its own layout pass. Windows now follow their display by display ID, and windows of displays that are really gone are disposed on the next run-loop turn. Opening no longer forces a synchronous redraw from inside the SwiftUI update, invalid frames are refused instead of raising, and closing on hover exit now waits for the opening to settle and checks that the pointer really left the panel.
- Fixed an issue where `BluetoothHUDAnimations` (.mov files) were missing in release builds.
- Improved the GitHub Actions release workflow to use a monotonic build number allocator and automated patch versioning for stable releases.

### Removed

## [2.3.2] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.1] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.0] - 2026-07-20

### Added
- **Lock Screen & Live Activities**: Full support for Lock Screen widgets, Live Activities, and expanding lock screen music players with flip animations.
- **Screen Assistant (AI)**: Introducing Screen Assistant with snipping capabilities and Gemini API integration.
- **Advanced System HUDs**: Dynamic polling HUDs for Volume (mute/unmute), Brightness, Bluetooth, and Privacy Access Indicators.
- **Clipboard Manager**: New floating clipboard manager panel with customizable settings and quick access.
- **System Stats Panel**: Real-time tracking of CPU usage, Memory, Disk Read/Write, and Network usage with circular progress graphs.
- **Custom Timer**: Dedicated Timer UI with custom timer capabilities.
- **Multi-channel Updates**: Switch seamlessly between Nightly, Alpha, Beta, and Stable update channels directly from Settings.
- **Automated CI/CD**: Full automated release pipeline via GitHub Actions using Sparkle.

### Changed
- **UI & Aesthetics**: Major overhaul to support a new Minimalistic UI option, as well as a Frutiger Aero aesthetic option.
- **Onboarding & Settings**: Revamped the onboarding experience and Settings window layout for a cleaner, native macOS feel.
- **Media Player**: Refined NowPlaying detection, expanded the Lock Screen music player, and smoothed out slider behavior.
- **Performance**: Disabled `OSDUIHelper` polling in favor of event-driven system HUD monitoring to drastically reduce CPU footprint.

### Fixed
- Fixed timeline reset and playback jumping issues in the Media Player.
- Fixed jittering animations on brightness and volume HUDs.
- Fixed corner radius clipping and window alignment bugs across multiple popup panels.
- Fixed double conversion network errors and memory usage spikes in the System Stats panel.
- Fixed lock screen GIF tracking via Git LFS.

### ❤️ Special Thanks to Our Contributors
A massive shoutout to everyone who contributed to this milestone release:
Hariharan Mudaliar, Jis G Jacob, Felipe Giacomini Cocco, delli, Federico Imberti, Dan Querido, Soham Sharma, 杨锟, DanFQ, Amir Zarrinkafsh, HerbJul, StellarSea, XiNian-dada, AkhilKonduru1, createthisnl, fatih ozdil, Santiago Quihui, Venkatesh, A-Akhil, Alex, JoelVR2k, Ninzorn, SSylvain1989, landuoduo, and dozens of others!

## [2.2.0] - 2026-05-30
### Added
- Initial release on the new update pipeline
