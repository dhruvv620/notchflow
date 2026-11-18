# Changelog

All notable changes to Atoll will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
