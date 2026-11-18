# NotchFlow and your privacy

NotchFlow runs on your Mac. It has no account, no analytics and no tracking, and it does not send what it reads to the developer.

## What stays on your Mac

Settings, clipboard history, notes, todos, Pomodoro history, Cuely scripts, the notification inbox and agent sessions are stored on your Mac only (in NotchFlow's preferences and in `~/Library/Application Support/NotchFlow`). Keys you enter (MiniMax, GitHub, Gemini) are kept in your login Keychain.

## Permissions and why they are asked for

macOS asks the first time a feature needs one of these. Every feature works without the others, so allow only what you use.

| Permission | Used for |
| --- | --- |
| Accessibility | Replacing the volume, brightness and keyboard backlight HUDs, trackpad gestures, and reading notification banners so you can reply from the notch. |
| Automation (Apple Events) | Controlling Spotify and Apple Music, syncing with Notes, sending replies through Messages, reading the browser tab during a Pomodoro (distraction meter), and opening Terminal or iTerm for an AI agent. |
| Calendar and Reminders | Showing events, meetings and todos in the notch. |
| Contacts | The caller's photo and number for incoming calls. |
| Camera | The mirror in the notch. Nothing is recorded. |
| Microphone and Speech Recognition | Cuely following your voice while you read a script. Nothing is recorded or saved. |
| Full Disk Access | Reading macOS's notification database so the inbox has every app's notifications. |
| Screen Recording | Screenshots for the screen assistant, when you take one. |
| Bluetooth | Showing when audio devices connect, with their battery level. |
| Location | Local weather on the lock screen. |

## When NotchFlow talks to the internet

Only for features you turn on, and only to the service that feature needs:

- **Updates**: once a day it reads `appcast.xml` from NotchFlow's GitHub releases.
- **Weather**: Open-Meteo, with your approximate location.
- **Lyrics and artwork**: lyrics and artwork services for the song that is playing.
- **Smart replies**: MiniMax, with the message you are replying to, only when you tap the sparkles button.
- **Screen assistant**: the AI provider you chose, with what you ask and the screenshot you take.
- **Build watcher**: GitHub, with your token, for the repositories you list.
- **WhatsApp**: the GOWA gateway runs on your Mac and talks to WhatsApp for your linked account.
- **LLM usage**: model prices from NotchFlow's repository, and the usage pages of the AI tools you connect.
- **AI agents**: the bridge listens on this Mac only (127.0.0.1) and checks a token only your account can read.

## Questions

Open an issue at https://github.com/dhruvv620/notchflow/issues.
