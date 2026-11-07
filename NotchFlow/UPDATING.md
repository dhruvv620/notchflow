# Maintaining NotchFlow

## Baseline

Initial upstream base: Atoll v2.3.3-beta.3, commit `c7305ecd1522ae8eb15b20d64c11d2105c62aa31`.
Custom branch: `notchflow`. Keep `dev` as the upstream reference. A normal `git pull` only retrieves changes already published to your custom branch.

## Integrate an upstream release

Do this in a clean clone with no uncommitted edits. Fetch upstream, then create a review branch from NotchFlow:

```bash
git remote add upstream https://github.com/Ebullioscopic/Atoll.git
git fetch upstream --tags
git switch notchflow
git pull --ff-only origin notchflow
git switch -c update-atoll
```

Add the upstream remote only once. Select a specific release tag after reviewing its release notes. Merge that tag using `git merge --no-commit --no-ff TAG`, substituting the selected tag. Resolve conflicts before committing. Use `git merge --abort` to abandon a conflicted integration and return to the pre-merge state.

Inspect these integration points carefully:

- DynamicIsland/ContentView.swift: gradient surface and expanded tab swipe routing.
- DynamicIsland/models/DynamicIslandViewModel.swift: interaction state and window dimensions.
- DynamicIsland/DynamicIslandApp.swift: app lifecycle, updater and extension-server behavior.
- DynamicIsland/components/Notch/NotchFlowSurface.swift: expanded surface themes.
- DynamicIsland/components/Tabs/TabSelectionView.swift: shared visible-tab ordering and navigation.
- DynamicIsland/extensions/PanGesture.swift: horizontal trackpad filtering and momentum handling.
- DynamicIsland.xcodeproj/project.pbxproj and shared scheme: NotchFlow app identity and product paths.
- Package.resolved, privacy settings, entitlements and inherited workflow changes.

Run `bash Build.command` on a Mac, then follow the interaction and theme validation checklist in ReadMe.md. Confirm the full build/sign/install succeeds before merging. Update the baseline recorded here once integration is accepted.

Do not blindly merge `dev` or enable the official Atoll updater: either can replace custom behavior or app identity. Automatic upstream updates are disabled. The inherited release, mirror and nightly-merge workflow files are absent from the custom branch; no replacement updater or publishing pipeline is configured.

The pinned legacy RPC/XPC extension servers are disabled in the initial custom build. Keep that decision until updated upstream implementations have been reviewed; the restored built-in interface does not need them.
