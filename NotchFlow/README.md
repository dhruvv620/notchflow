# NotchFlow fresh start

This branch starts from **Atoll v2.3.3 stable**, commit `e21cdf7b10e62e82ddbc9c23158e6e8cf5b21cf5`.
It preserves upstream layout, controls, sizing rules and animations and adds compact Apple Reminders and Clipboard tabs, expanded trackpad tab navigation, and an optional Liquid Glass surface. The earlier custom panels, AI chat, Cuely, mascots and gradient themes are not included.

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

The Allow button brings NotchFlow forward for the macOS prompt. It shows a waiting state, reports refusals/errors, and offers Open Privacy Settings and Check Access even if the prompt stalls. If access is denied, open **System Settings > Privacy & Security > Reminders**, grant access and choose Check Access. If no lists exist, create one in Apple Reminders first. Errors stay visible and failed saves do not hide reminder rows.

## Compact clipboard and gestures

Clipboard keeps the latest 20 recent copied items, with All/Links/Colors/Images/Code/Text filters and a paginated row of compact preview cards. Click a card to copy the original content again; a green check confirms success. Copying a card does not create another history entry. Re-copying the same content in another app moves it to the front. Clear asks for confirmation. Previously pinned items remain available in the legacy clipboard interface separately.

Clipboard and Reminders use the same panel width and height as Music. Their contents scroll or paginate instead of expanding the notch. Additional tabs use tighter icon spacing or an overflow menu to stay within the original header width.

With gestures enabled, a two-finger horizontal swipe over the expanded panel selects the next/previous visible tab; one gesture selects one tab and momentum is ignored. Direction respects Reverse swipe gestures. Vertical content scrolling remains inside the tab, and closed-notch media swipes retain their existing behavior.

Glass has a shape-matched near-transparent backing so the inside of the expanded panel receives clicks, while clipped corners and outer margins remain transparent. Root click-to-open applies only to the closed notch. Mouse drag recognition starts only after actual movement, preserving button clicks. These input changes still require verification against real windows on the Mac.

## Liquid Glass

Enable **Settings > Appearance > Liquid Glass expanded notch**. The original layout and dimensions remain. On macOS 26+, the background uses SwiftUI's public native Liquid Glass API; older systems use a frosted material. The physical camera strip and closed notch remain black. **Reduce Transparency** restores the opaque classic surface.

The option defaults off to preserve the original appearance. Turn it off at any time to compare with the unchanged classic background. SwiftUI previews in `ExpandedNotchSurface.swift` show classic and glass treatments; test Reduce Transparency through macOS Accessibility settings.

## Verification

GitHub's **NotchFlow Native Build** workflow compiles Debug on macOS 15 and Release on macOS 26 with Xcode 26+ and pinned packages, checks privacy declarations, and runs the isolated Reminders regression executable. Build logs and Xcode result bundles are retained as workflow artifacts. These are compile and logic checks, not a claim of visual or account-sync validation.

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
- Clipboard retains exactly the latest 20 recent items after 21 external copies, repeated external copies move to the front, clicking a card preserves full original content without adding duplicates, filters/pages remain valid, and clear requires confirmation.
- A quick horizontal flick changes one tab, vertical scrolling does not navigate, disabled tabs are skipped, and reverse direction works. Clipboard/Reminders match Music's panel dimensions.
- Place a clickable control behind the expanded glass: interior clicks must stay in the notch, nested buttons must work, and transparent corners/margins must still pass clicks through.
- Scrolling remains inside reminder content, typing does not close the composer, permission denial or a slow prompt offers actionable feedback, manual Check Access accepts changed permissions, and sleep/wake/fullscreen do not leave stale panels.

The editing environment is Linux. It cannot provide a real notch screenshot or verify iCloud synchronization; those remain explicit Mac acceptance checks.
