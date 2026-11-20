# NotchFlow and your privacy

NotchFlow runs on your Mac. It has no account, no analytics and no tracking, and it does not send what it reads to the developer.

## What stays on your Mac

With Full Disk Access, the promise keeper also reads new messages from the Messages app's history (`~/Library/Messages/chat.db`, from a private copy, never changed) to see what you send and the message you answered; only messages from the moment it's turned on, and nothing leaves your Mac unless "Understand any language" is on (see below). Turn it off with Settings > Productivity > See what I send in Messages.

Settings, clipboard history, notes, todos, Pomodoro history, tracked time, promises, workspaces, Cuely scripts, the notification inbox and agent sessions are stored on your Mac only (in NotchFlow's preferences and in `~/Library/Application Support/NotchFlow`). Keys you enter (your AI provider keys, GitHub) are kept in your login Keychain.

## Permissions and why they are asked for

macOS asks the first time a feature needs one of these. Every feature works without the others, so allow only what you use.

| Permission | Used for |
| --- | --- |
| Accessibility | Replacing the volume, brightness and keyboard backlight HUDs, trackpad gestures, reading notification banners so you can reply from the notch, reading the front window's title for time tracking's projects, and arranging a workspace's windows. |
| Automation (Apple Events) | Controlling Spotify and Apple Music, syncing with Notes, sending replies through Messages, reading the front browser tab's address (distraction meter, time tracking, saving a workspace), and opening Terminal or iTerm for an AI agent or a workspace. |
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
- **Music search**: what you type in the Music tab's search goes to Apple's public song catalog (the iTunes Search API, no account) to list songs; a song you pick is played in the Music app; for Spotify and YouTube Music, its Apple Music link goes to song.link (Odesli, no account) to find the same song there.
- **Smart replies**: the AI provider you choose in Settings > Smart Tools (MiniMax, OpenAI, Claude, Gemini, Groq, OpenRouter, DeepSeek, Mistral, xAI, Together, or a custom server), with the message you are replying to, only when you tap the sparkles button. With Ollama or LM Studio nothing leaves your Mac.
- **Promise keeper, Understand any language** (off by default): the same AI provider, with messages that contain a word hinting at a promise or a time, a few at a time and at most 300 a day. Other messages stay on your Mac.
- **Screen assistant**: the AI provider you chose, with what you ask and the screenshot you take.
- **Build watcher**: GitHub, with your token, for the repositories you list.
- **WhatsApp**: the GOWA gateway runs on your Mac and talks to WhatsApp for your linked account.
- **LLM usage**: model prices from NotchFlow's repository, and the usage pages of the AI tools you connect.
- **AI agents**: the bridge listens on this Mac only (127.0.0.1) and checks a token only your account can read.

## Questions

Open an issue at https://github.com/dhruvv620/notchflow/issues.
