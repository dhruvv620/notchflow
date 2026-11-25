# Plan: a private repository now, our own code later

This is the plan for two things, in order:

1. **Now:** move NotchFlow from a public fork of Atoll into a private repository of its own.
2. **Later:** rewrite every part that came from Atoll and boring.notch, so the whole app is ours and
   can be sold under our own license.

It is general guidance, not legal advice. Before selling anything, an hour with an IP lawyer is worth it.

---

## Where we stand (measured 2026-11-25)

`bash tools/provenance.sh` counts each line of code by who last wrote it:

| | Lines | Share |
|---|---:|---:|
| Ours (Dhruv and Claude) | 44,432 | 34% |
| Inherited (Atoll, boring.notch and their contributors) | 86,477 | 66% |

- **Fully ours already:** Orbit, AI Agents, WhatsApp, Glance, Productivity (time, promises, workspaces,
  stash), Notifications & Calls, Optimizer, Smart Tools, the Settings kit, and almost all `*Policy.swift`
  files and their tests.
- **Mostly inherited:** the notch window itself, music, HUDs, battery and Bluetooth, calendar and
  timers, shelf, lock screen, stats, clipboard, color picker, screen assistant, and most of
  `SettingsView.swift`.
- Lines we only renamed or reformatted inside inherited files count as "ours" in the script but are
  **not** clean-room code. The rewrite replaces whole files, so this caveat goes away as we go.

### What the license means until the rewrite is done

The app contains GPL v3 code, so **the whole app is GPL v3** until the inherited code is gone.

- **Private for your own use:** fine. The GPL puts no duties on code nobody else receives.
- **Giving or selling the app to anyone** (even a free download): they must get the matching source
  code under the GPL, and they may share it. A private repository does not change that; it only hides
  the work in progress and history.
- **Closed-source selling:** only after the rewrite (Phase 4) is complete.
- Your own code (the "fully ours" list) is your copyright. You can relicense it for the new product.
  Versions already published under the GPL stay GPL for whoever has them.

---

## Phase 0: Decisions (5 minutes, you)

| # | Decision | Recommendation |
|---|---|---|
| D1 | Clean personal details out of the old history while moving? | **Yes.** It is free to do during the move and impossible to do well later. |
| D2 | How do you get new versions on your Mac while the repo is private? | **Build locally with `Build.command`** until the rewrite. No public downloads means no GPL duty to publish source. |
| D3 | Keep the name "NotchFlow"? | Fine **privately**. Another commercial Mac notch app already uses it, so choose the real product name before selling (Phase 3). |
| D4 | Keep GitHub Actions CI? | Keep it, but only on pull requests. macOS runner minutes are limited on a private repo (they count ten times). |

If you later want public downloads before the rewrite is done (D2 "public releases"), use a separate
public repository that holds only the releases, and attach a source zip to every release. That's the
GPL's "equivalent access" rule. Section 1.6 covers it.

---

## Phase 1: Prepare the code for a private home (Claude, one session)

A private repository breaks everything that downloads from `github.com/dhruvv620/notchflow` without
logging in. These are all the places:

| Where | What it fetches | Change |
|---|---|---|
| `DynamicIsland/Info.plist` `SUFeedURL` | update feed (appcast.xml) | read from one setting (1.1) |
| `DynamicIsland/models/UpdateChannel.swift` | update feed | same setting |
| `install.sh` `DOWNLOAD_URL` | the app zip | same setting |
| `Release.command` `REPO` | where releases are published | split into source repo and releases repo |
| `managers/LLMUsage/ModelPricingManager.swift` | `pricing.json` from raw.githubusercontent.com | use the bundled copy only (it already ships one) |
| `strings/constants.swift` `productPage`, `privacyPage` | About links | point to a page that stays public, or remove |
| `helpers/AIProviderPolicy.swift` | OpenRouter `HTTP-Referer` | neutral value (just a label, nothing breaks) |
| `ReadMe.md`, `CONTRIBUTING.md`, `docs/PRIVACY.md`, `install.sh` header | public links and issues | update text |
| `.github/workflows/notchflow-ci.yml` | CI on every push | run on pull requests and by hand only (D4) |

**1.1 One place for "where releases live".** Add `NotchFlowReleaseRepository` to Info.plist
(`dhruvv620/notchflow` for now). `UpdateChannel`, `SUFeedURL` (written by `Build.command` and
`Release.command`), `install.sh` and About read it. Changing hosts later is one line.

**1.2 Updates off for private builds.** With D2 = build locally, `Build.command` already makes builds
that don't check for updates. Nothing else to do. If you choose public releases, `Release.command`
publishes to the releases repository instead (1.6).

**1.3 Pricing data from the app bundle.** `ModelPricingManager` stops fetching from GitHub and uses
the `pricing.json` it ships with. `Build.command` refreshes it at build time.

**1.4 Links.** About shows "Source: private" instead of the GitHub link. Privacy text moves into the
app (Settings › About › Privacy), so it works without the website.

**1.5 CI.** The workflow runs on `pull_request` and `workflow_dispatch` only.

**1.6 Only if you choose public releases:** `Release.command` gains `RELEASES_REPO` (for example
`dhruvv620/notchflow-releases`, public, no code) and attaches `NotchFlow-source-<version>.zip`
(`git archive` of the released commit) to each release, which keeps the GPL satisfied.

**Done when:** a build from the private repo starts, About opens, the AI usage tab shows prices, and
`grep -rn "dhruvv620/notchflow" DynamicIsland` finds only the one setting.

---

## Phase 2: Move to the private repository (you, on your Mac, about 30 minutes)

Do Phase 1 first and let it merge, so the copy you move already has it.

**2.1 Stop and back up.**
- Close other Claude or Codex sessions working on the repo.
- Keep a full backup that is never touched:
  `git clone --mirror https://github.com/dhruvv620/notchflow.git ~/notchflow-backup.git`
- Optional: save old release files: `gh release download <tag> --repo dhruvv620/notchflow -D ~/notchflow-releases/<tag>`
  for each tag you care about (`gh release list --repo dhruvv620/notchflow`). Deleting the fork deletes
  its releases.

**2.2 Create the private repository** on github.com: New repository › name `notchflow-private` ›
**Private** › no README, no license, no .gitignore.

**2.3 Make the working copy** (separate from the backup):
`git clone --mirror https://github.com/dhruvv620/notchflow.git ~/notchflow-move.git`

**2.4 Clean the history (D1).**
- `brew install git-filter-repo`
- `~/replace.txt`, one rule per line (`old==>new`): the names, the WhatsApp id, the `/Users/dv/` path and
  the iMessage lines already replaced in the current code (see the 2026-11-25 cleanup commit).
- `~/mailmap.txt`: `Dhruv Dahyabhai Patel <ID+dhruvv620@users.noreply.github.com> <your Gmail>`, with
  your ID from github.com › Settings › Emails.
- `cd ~/notchflow-move.git && git filter-repo --replace-text ~/replace.txt --mailmap ~/mailmap.txt --force`
- Check: `git log --all -S"Khushii" --oneline` prints nothing; repeat for each replaced item.

**2.5 Push everything:**
`git push --mirror https://github.com/dhruvv620/notchflow-private.git`
Then on GitHub check: branches (`claude/charming-gates-vzwa2i`, `dev`, `notchflow`, …), tags, and that
the default branch is the one you build from (Settings › General › Default branch).

**2.6 Delete the public fork.** github.com/dhruvv620/notchflow › Settings › Danger Zone ›
**Delete this repository**. Not archive: an archived repository stays public. This also removes the
v1.2.2 release notes with the old message text.

**2.7 Take back the name.** Rename `notchflow-private` to `notchflow` (Settings › General). Every link
in the code keeps working, and Phase 1's single setting doesn't change.

**2.8 Your Mac.**
- History was rewritten, so start a fresh copy:
  `mv ~/notchflow ~/notchflow-old && git clone https://github.com/dhruvv620/notchflow.git ~/notchflow`
- Copy anything only the old folder has (untracked notes, `Orbit/`) by hand, then delete `~/notchflow-old`
  after a week.
- Use the private email for new commits:
  `git config --global user.email "ID+dhruvv620@users.noreply.github.com"`
- On github.com › Settings › Emails: tick **Keep my email addresses private** and **Block command line
  pushes that expose my email**.

**2.9 Claude and other tools.**
- github.com/settings/installations › Claude › Repository access: allow the new repository.
- Start new Claude sessions on it. Old sessions point at the deleted fork.
- Check who has access: Settings › Collaborators (should be only you).

**2.10 Check nothing public is left.**
- Signed out (a private window), open github.com/dhruvv620/notchflow: it should say 404.
- Forks of the old fork, if anyone made one, keep the old code. You can see them before deleting
  (the fork count on the repository page). Ask GitHub Support if one has personal data.

**Done when:** the private repository has every branch and tag, the old URL is 404 for others, your
Mac builds from the new clone, and Claude can open the repository.

---

## Phase 3: The product name (before any sale)

1. Short-list 5 names. For each: search the USPTO (tmsearch.uspto.gov) and your country's trademark
   office in Class 9 (software), the Mac App Store, Product Hunt, GitHub, and the `.com`/`.app` domain.
2. Pick one that is free everywhere and not close to an existing notch or productivity app.
3. Register the domain and the trademark (Class 9; in the US about $350 per class).
4. **Rename the app (Claude, one session).** Product name, bundle ID, log subsystem, Keychain service
   names and Application Support folder, with a one-time migration of settings, saved data and
   Keychain items from the old names. macOS asks again for Accessibility, Screen Recording and Full
   Disk Access, because they belong to the bundle ID.
5. Never use "Dynamic Island" in the name or marketing (Apple's trademark).

---

## Phase 4: The clean-room rewrite

### Rules (apply to every stage)

1. **Write from a behaviour spec, not from the old code.** For each stage, first write
   `docs/specs/<stage>.md`: what the user sees and can do, settings, edge cases, from using the app and
   from Apple's documentation. The session that writes new code reads the spec and Apple docs, **not** the
   inherited files.
2. **New files, new structure.** New code goes in new files with new names under `DynamicIsland/Core/`,
   `DynamicIsland/Features/<Feature>/`. Don't edit inherited files into shape; replace them.
3. **Fresh sessions.** Start each rewrite stage in a new session, told to read only the spec, the
   design docs and our own code. (This session has read the inherited code.)
4. **Delete, then measure.** When a stage works, delete the inherited files it replaces and run
   `bash tools/provenance.sh`. The stage's folders must show 0 inherited lines.
5. **Record provenance.** `docs/PROVENANCE.md` gets one line per stage: date, spec, files added, files
   removed, provenance numbers before and after.
6. **Tests first where possible.** Logic goes into `*Policy.swift` files with tests run by
   `Build.command`, as the rest of the app already does.
7. **Keep, rewrite or drop.** Each stage starts by deciding per feature. Dropping a rarely used
   feature is the cheapest rewrite.

### Stages, in order

Sizes are inherited lines to replace (from `git blame`). Order follows dependencies: the shell first,
because everything sits inside it.

| Stage | What | Inherited lines | Notes |
|---|---|---:|---|
| R1 | **Notch shell**: the window over the notch, shape and sizing, hover/open/close, tabs host, closed-notch area, view model, onboarding, shared utilities | ~21,100 | Largest and most important. Our features (Orbit, Agents, Glance…) already plug into tabs; keep those interfaces. |
| R2 | **Settings window**: the remaining inherited parts of `SettingsView.swift` and the animation editor | ~7,500 | Our kit and design doc already exist; mostly re-expressing pages with it. |
| R3 | **System HUDs and status**: volume, brightness, keyboard light, battery, Bluetooth devices, Focus, camera/mic/recording, Caps Lock, external displays (BetterDisplay, Lunar) | ~13,000 | Lots of system APIs; spec each HUD's behaviour carefully. Consider dropping BetterDisplay/Lunar. |
| R4 | **Music**: player, Now Playing / Apple Music / Spotify / YouTube Music, media keys, AirPlay, visualizer, lyrics | ~9,500 | Replace the rtaudio (GPL) visualizer with our own Accelerate FFT. MediaRemoteAdapter (BSD) can stay. |
| R5 | **Calendar, reminders, timers** | ~6,700 | Our Todos/Promises logic is already ours; this is the views and EventKit glue. |
| R6 | **Shelf, LocalSend, Quick Share** | ~6,100 | Consider dropping LocalSend. |
| R7 | **Lock screen widgets, full-screen artwork** | ~6,800 | Candidate to drop or shrink: complex, private APIs, few users. |
| R8 | **Smaller tools**: Stats, Clipboard, Color Picker, Screen Assistant, Notes (+ Apple Notes sync), Terminal glue, Downloads, Mirror, AI usage | ~14,000 | Many small, separate pieces; good for parallel sessions. Stats readings came from the Stats app (MIT), fine to use with notice. |
| R9 | **Media and assets**: inherited sounds, Lottie animations, Bluetooth device animations, sample images | n/a | Replace with our own or commercially licensed files. |
| R10 | **Finish**: provenance 0, NOTICE/README credits updated, new LICENSE/EULA, third-party notices file | n/a | See "Ready to sell" below. |

Rough effort: R1 and R8 take several sessions each; R2 to R7 about one or two sessions each, plus your
testing on the Mac after every stage.

### Each stage, step by step

1. **Spec session:** a fresh session writes `docs/specs/<stage>.md` from the running app and Apple
   docs. You review it and add anything you use that's missing.
2. **Decide** keep / rewrite / drop per feature in the spec.
3. **Build session (fresh):** implement from the spec in new files; add policy tests; wire it into the
   app next to the old code behind a temporary switch if the change is large.
4. **You test** on your Mac with the checklist at the end of the spec.
5. **Swap and delete:** remove the switch and the inherited files; `Build.command` passes;
   `tools/provenance.sh` shows the stage's folders at 0.
6. **Record** the stage in `docs/PROVENANCE.md` and the changelog.

### Third-party code that may stay

These have permissive licenses and can ship in a commercial app with their notices (keep a
`THIRD_PARTY_NOTICES.md`): Sparkle, Defaults, KeyboardShortcuts, LaunchAtLogin, Lottie,
swift-collections, SwiftUI-Introspect, SwiftTerm, MediaRemoteAdapter, GOWA (MIT, but see WhatsApp
below), Stats-derived readings (MIT). Check each one's license file once more in R10.

**Must go:** rtaudio-derived visualizer (GPL), everything from Atoll and boring.notch, inherited media.

### Ready to sell: checklist

- [ ] `tools/provenance.sh` shows 0 inherited lines
- [ ] No inherited sounds, animations or images left
- [ ] `THIRD_PARTY_NOTICES.md` lists every library with its license
- [ ] New name chosen, checked and registered (Phase 3)
- [ ] New license: proprietary EULA for the app (old GPL versions stay GPL)
- [ ] WhatsApp: off by default and clearly "unofficial", or removed. WhatsApp's terms forbid unofficial
      clients, so selling it as a feature is a risk
- [ ] Spotify, Linear and AI providers: their API terms allow your use
- [ ] Sales channel picked (Paddle, Lemon Squeezy or Gumroad; direct download, notarized). The Mac App
      Store is out while the app uses private macOS APIs
- [ ] A lawyer has looked at the license, EULA and name

---

## Tracking

| Phase | Who | Status |
|---|---|---|
| 0 Decisions | You | to do |
| 1 Prepare code for private repo | Claude | to do |
| 2 Move to private repo | You (commands above) | to do |
| 3 Product name | You, then Claude for the rename | before selling |
| 4 Rewrite R1 to R10 | Claude sessions + your testing | after Phase 2 |
