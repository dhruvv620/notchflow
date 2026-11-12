# NotchFlow fresh start

This branch starts from **Atoll v2.3.3 stable**, commit `e21cdf7b10e62e82ddbc9c23158e6e8cf5b21cf5`.
It preserves upstream layout, controls, sizing rules and animations and adds only a dedicated Apple Reminders tab and an optional expanded-notch Liquid Glass surface. The earlier custom panels, AI chat, Cuely, mascots, gestures and gradient themes are not included.

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

`Build.command` uses cached packages and a Debug build, signs locally without a paid Apple developer account, and installs `~/Applications/NotchFlow.app`. It backs up an existing app before replacement. Quit any older notch app before opening it. The full build output is saved as `Build.log` next to the script.

For the fastest edit/build/run loop, open `DynamicIsland.xcodeproj`, choose scheme **DynamicIsland**, destination **My Mac**, configuration **Debug**, and use Command-R. The product is NotchFlow.app. To build the optimized configuration with the script:

```bash
NOTCHFLOW_CONFIGURATION=Release bash Build.command
```

Native Liquid Glass requires macOS 26+. Earlier supported systems use a frosted material. The existing app's deployment target is macOS 14.6.

## Apple Reminders

In the standard layout, select the checklist tab. Allow Reminders access when requested. Choose All Lists or a specific Apple Reminders list, add a reminder with the + button, optionally set a date and time, and use the circle to complete it. The options menu can show completed reminders so they can be marked incomplete again.

Data is read and saved directly through Apple's EventKit store; there is no separate task database or account login. Cloud synchronization follows the account configured in Apple Reminders. Undated reminders are included. Read-only lists remain visible, and creation uses a writable list. The panel refreshes after saves, when EventKit reports a change, and when the app becomes active.

Use **Settings > Calendar > Show Reminders tab** to control visibility. The tab bar is part of Standard UI; if Minimalistic UI is enabled, switch back to Standard to use it. Existing calendar/reminder live activities are retained.

If access is denied, open **System Settings > Privacy & Security > Reminders**, grant access and reopen or refresh the tab. If no lists exist, create one in Apple Reminders first. Errors stay visible and failed saves do not hide reminder rows.

## Liquid Glass

Enable **Settings > Appearance > Liquid Glass expanded notch**. The original layout and dimensions remain. On macOS 26+, the background uses SwiftUI's public native Liquid Glass API; older systems use a frosted material. The physical camera strip and closed notch remain black. **Reduce Transparency** restores the opaque classic surface.

The option defaults off to preserve the original appearance. Turn it off at any time to compare with the unchanged classic background. SwiftUI previews in `ExpandedNotchSurface.swift` show classic and glass treatments; test Reduce Transparency through macOS Accessibility settings.

## Verification

GitHub's **NotchFlow Native Build** workflow compiles Debug and Release on macOS with pinned packages, checks privacy declarations, and runs the isolated Reminders regression executable. Build logs and Xcode result bundles are retained as workflow artifacts. These are compile and logic checks, not a claim of visual or account-sync validation.

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

- Classic appearance matches the original Atoll release; original media, calendar, shelf and open/close interactions still work.
- Glass readability on bright/dark wallpapers, Reduce Transparency, older-macOS fallback, physical notch and external-display pill.
- Reminders permission grant/denial/revocation, zero lists, read-only lists, very long titles, undated and date-only reminders, timed reminders, completed toggle, create/complete failures and changes made in Apple Reminders.
- Scrolling remains inside reminder content, typing does not close the composer, tab changes resize without clipping, and sleep/wake/fullscreen do not leave stale panels.

The editing environment is Linux. It cannot provide a real notch screenshot or verify iCloud synchronization; those remain explicit Mac acceptance checks.
