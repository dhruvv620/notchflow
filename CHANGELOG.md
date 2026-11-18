# Changelog

All notable changes to Atoll will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Notifications, rebuilt**: the Notifications tab now collects every app's notifications from Notification Center's own store (with Full Disk Access), so notifications arrive even when their banner was missed and the inbox survives relaunches (up to 200, kept on this Mac). On-screen banners still add their native Reply/Open/Close actions, and WhatsApp messages from the linked gateway join the inbox. Notifications are grouped by app with per-app filter chips, expand on click, and show Reply, Open and a menu on hover. Replies are sent inline: through the WhatsApp gateway, through Messages (by AppleScript, using the conversation Notification Center records), or through the live banner. Dismiss one, clear an app, or clear everything with a few seconds to Undo; mute an app from its menu. New notifications are announced in the closed notch with the app icon, and opening the notch lands on that notification. Notification Center is only read, from a private copy, never changed.
- **WhatsApp in the notch (experimental)**: a WhatsApp tab lists recent chats with unread counts, opens a conversation beside the list, and sends replies without leaving the notch. New messages are announced in the closed notch; opening the notch while one shows goes straight to that chat. Link once from Settings > WhatsApp by scanning a QR code with your phone (WhatsApp > Settings > Linked devices). It runs through [GOWA](https://github.com/aldinokemal/go-whatsapp-web-multidevice), an open-source WhatsApp multi-device gateway that NotchFlow downloads on request (checked against the release's published SHA-256), runs on 127.0.0.1 only behind a per-launch password, and stops when NotchFlow quits. New messages arrive at once through a signed local webhook. Groups can stay quiet unless you are mentioned, announcements can pause during a Focus, chats can be ignored, and read receipts are sent only when you open a conversation (or, with that off, only when you reply). Unofficial and off by default; enable it under Tabs & Features.

### Changed

### Fixed
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
