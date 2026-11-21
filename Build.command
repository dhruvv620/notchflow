#!/bin/bash
set -Eeuo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
exec > >(/usr/bin/tee "$SOURCE_DIR/Build.log") 2>&1
trap 'code=$?; printf "\nBuild stopped. See Build.log in the repository folder.\n"; exit "$code"' ERR

if [ "$(/usr/bin/uname -s)" != Darwin ]; then
    printf 'Build.command requires a Mac with Xcode 26 or newer.\n'
    exit 1
fi
XCODE_MAJOR="$(/usr/bin/xcodebuild -version | /usr/bin/awk '/^Xcode / {split($2,v,"."); print v[1]}')"
if [ "${XCODE_MAJOR:-0}" -lt 26 ]; then
    printf 'Select Xcode 26 or newer in Xcode Settings > Locations.\n'
    exit 1
fi
if ! git lfs version >/dev/null 2>&1; then
    printf 'Install Git LFS (brew install git-lfs) to download the animation assets, then rerun this script.\n'
    exit 1
fi
git -C "$SOURCE_DIR" lfs pull
if ! /usr/bin/xcrun -f metal >/dev/null 2>&1; then
    printf 'Downloading the Metal toolchain required by the original animation/shader dependencies...\n'
    /usr/bin/xcodebuild -downloadComponent MetalToolchain
fi

CONFIGURATION="${NOTCHFLOW_CONFIGURATION:-Debug}"
case "$CONFIGURATION" in Debug|Release) ;; *) printf 'NOTCHFLOW_CONFIGURATION must be Debug or Release.\n'; exit 1 ;; esac
BUILD_ROOT="$HOME/Library/Caches/NotchFlowFresh"
DERIVED_DIR="$BUILD_ROOT/DerivedData"
mkdir -p "$BUILD_ROOT"
printf 'Building %s with cached dependencies in %s\n' "$CONFIGURATION" "$BUILD_ROOT"

printf '\nChecking settings (no dead switches, every page reachable, search results land)...\n'
(cd "$SOURCE_DIR" && /usr/bin/python3 -m unittest -q tests.test_settings_integrity)

printf '\nChecking natural-language reminder dates...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/ReminderDateParser.swift" \
    "$SOURCE_DIR/tests/ReminderDateParserRegression.swift" -o "$BUILD_ROOT/ReminderDateParserRegression"
"$BUILD_ROOT/ReminderDateParserRegression"

printf '\nChecking clipboard filters and pagination...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/CompactClipboardPolicy.swift" \
    "$SOURCE_DIR/tests/CompactClipboardRegression.swift" -o "$BUILD_ROOT/CompactClipboardRegression"
"$BUILD_ROOT/CompactClipboardRegression"

printf '\nChecking Reminders behavior without accessing your reminders...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/models/ReminderItem.swift" \
    "$SOURCE_DIR/DynamicIsland/Providers/RemindersServiceProviding.swift" \
    "$SOURCE_DIR/DynamicIsland/managers/RemindersManager.swift" \
    "$SOURCE_DIR/tests/RemindersRegression.swift" -o "$BUILD_ROOT/RemindersRegression"
"$BUILD_ROOT/RemindersRegression"

printf '\nChecking Cuely script validation and persistence...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/models/CuelyScript.swift" \
    "$SOURCE_DIR/DynamicIsland/managers/CuelyScriptPersistence.swift" \
    "$SOURCE_DIR/tests/CuelyScriptStoreRegression.swift" -o "$BUILD_ROOT/CuelyScriptStoreRegression"
"$BUILD_ROOT/CuelyScriptStoreRegression"

printf '\nChecking Cuely voice following...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/CuelyVoiceFollowPolicy.swift" \
    "$SOURCE_DIR/tests/CuelyVoiceFollowRegression.swift" -o "$BUILD_ROOT/CuelyVoiceFollowRegression"
"$BUILD_ROOT/CuelyVoiceFollowRegression"

printf '\nChecking the Optimizer...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/EnergyPolicy.swift" \
    "$SOURCE_DIR/tests/EnergyRegression.swift" -o "$BUILD_ROOT/EnergyRegression"
"$BUILD_ROOT/EnergyRegression"

printf '\nChecking time tracking, promises and workspaces...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/TimeTrackingPolicy.swift" \
    "$SOURCE_DIR/tests/TimeTrackingRegression.swift" -o "$BUILD_ROOT/TimeTrackingRegression"
"$BUILD_ROOT/TimeTrackingRegression"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/PromisePolicy.swift" \
    "$SOURCE_DIR/tests/PromiseRegression.swift" -o "$BUILD_ROOT/PromiseRegression"
"$BUILD_ROOT/PromiseRegression"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/WorkspacePolicy.swift" \
    "$SOURCE_DIR/DynamicIsland/helpers/TimeTrackingPolicy.swift" \
    "$SOURCE_DIR/tests/WorkspaceRegression.swift" -o "$BUILD_ROOT/WorkspaceRegression"
"$BUILD_ROOT/WorkspaceRegression"

printf '\nChecking AI providers and promises in any language...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/AIProviderPolicy.swift" \
    "$SOURCE_DIR/DynamicIsland/helpers/PromisePolicy.swift" \
    "$SOURCE_DIR/DynamicIsland/helpers/PromiseAIPolicy.swift" \
    "$SOURCE_DIR/DynamicIsland/helpers/MessagesHistoryPolicy.swift" \
    "$SOURCE_DIR/tests/AIRegression.swift" -o "$BUILD_ROOT/AIRegression"
"$BUILD_ROOT/AIRegression"

printf '\nChecking where the app runs from...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/AppLocationPolicy.swift" \
    "$SOURCE_DIR/tests/AppLocationRegression.swift" -o "$BUILD_ROOT/AppLocationRegression"
"$BUILD_ROOT/AppLocationRegression"

printf '\nChecking music search...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/MusicSearchPolicy.swift" \
    "$SOURCE_DIR/tests/MusicSearchRegression.swift" -o "$BUILD_ROOT/MusicSearchRegression"
"$BUILD_ROOT/MusicSearchRegression"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/SpotifyAPIPolicy.swift" \
    "$SOURCE_DIR/tests/SpotifyAPIRegression.swift" -o "$BUILD_ROOT/SpotifyAPIRegression"
"$BUILD_ROOT/SpotifyAPIRegression"

printf '\nChecking song radio...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/SongRadioPolicy.swift" \
    "$SOURCE_DIR/tests/SongRadioRegression.swift" -o "$BUILD_ROOT/SongRadioRegression"
"$BUILD_ROOT/SongRadioRegression"

printf '\nChecking Glance...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/GlancePolicy.swift" \
    "$SOURCE_DIR/tests/GlanceRegression.swift" -o "$BUILD_ROOT/GlanceRegression"
"$BUILD_ROOT/GlanceRegression"

printf '\nChecking the window stash...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/WindowStashPolicy.swift" \
    "$SOURCE_DIR/tests/WindowStashRegression.swift" -o "$BUILD_ROOT/WindowStashRegression"
"$BUILD_ROOT/WindowStashRegression"

printf '\nChecking focus quiet...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/FocusQuietPolicy.swift" \
    "$SOURCE_DIR/tests/FocusQuietRegression.swift" -o "$BUILD_ROOT/FocusQuietRegression"
"$BUILD_ROOT/FocusQuietRegression"

printf '\nChecking the welcome chime...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/WelcomeChimePolicy.swift" \
    "$SOURCE_DIR/tests/WelcomeChimeRegression.swift" -o "$BUILD_ROOT/WelcomeChimeRegression"
"$BUILD_ROOT/WelcomeChimeRegression"

printf '\nChecking timer modes, tab ordering and visible input regions...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/TimerModeLifecycle.swift" \
    "$SOURCE_DIR/tests/TimerModeRegression.swift" -o "$BUILD_ROOT/TimerModeRegression"
"$BUILD_ROOT/TimerModeRegression"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/NotchTabOrderPolicy.swift" \
    "$SOURCE_DIR/tests/NotchTabOrderRegression.swift" -o "$BUILD_ROOT/NotchTabOrderRegression"
"$BUILD_ROOT/NotchTabOrderRegression"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/NotchInputRegionPolicy.swift" \
    "$SOURCE_DIR/DynamicIsland/components/Notch/NotchShape.swift" \
    "$SOURCE_DIR/tests/NotchInputRegionRegression.swift" -o "$BUILD_ROOT/NotchInputRegionRegression"
"$BUILD_ROOT/NotchInputRegionRegression"

printf '\nChecking Shelf cleanup reconciliation...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/components/Shelf/Models/ShelfCleanupPolicy.swift" \
    "$SOURCE_DIR/tests/ShelfCleanupRegression.swift" -o "$BUILD_ROOT/ShelfCleanupRegression"
"$BUILD_ROOT/ShelfCleanupRegression"

printf '\nChecking live system media updates...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/models/PlaybackState.swift" \
    "$SOURCE_DIR/DynamicIsland/helpers/SystemNowPlayingSnapshot.swift" \
    "$SOURCE_DIR/DynamicIsland/helpers/JSONLinesPipeHandler.swift" \
    "$SOURCE_DIR/tests/SystemMediaRegression.swift" -o "$BUILD_ROOT/SystemMediaRegression"
"$BUILD_ROOT/SystemMediaRegression"

printf '\nChecking native hosting and communications...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library "$SOURCE_DIR/DynamicIsland/helpers/NotchHostingView.swift" "$SOURCE_DIR/tests/NotchHostingSizeRegression.swift" -o "$BUILD_ROOT/NotchHostingSizeRegression"
"$BUILD_ROOT/NotchHostingSizeRegression"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library "$SOURCE_DIR/DynamicIsland/Communications/CommunicationModels.swift" "$SOURCE_DIR/DynamicIsland/Communications/CommunicationsPolicy.swift" "$SOURCE_DIR/DynamicIsland/Communications/CallClassificationPolicy.swift" "$SOURCE_DIR/tests/CommunicationsRegression.swift" -o "$BUILD_ROOT/CommunicationsRegression"
"$BUILD_ROOT/CommunicationsRegression"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library "$SOURCE_DIR/DynamicIsland/Communications/CommunicationModels.swift" "$SOURCE_DIR/DynamicIsland/Communications/NotificationCardPolicy.swift" "$SOURCE_DIR/tests/NotificationCardRegression.swift" -o "$BUILD_ROOT/NotificationCardRegression"
"$BUILD_ROOT/NotificationCardRegression"

printf '\nChecking up next...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/UpNextPolicy.swift" \
    "$SOURCE_DIR/tests/UpNextRegression.swift" -o "$BUILD_ROOT/UpNextRegression"
"$BUILD_ROOT/UpNextRegression"

printf '\nChecking karaoke lyrics...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/LyricsKaraokePolicy.swift" \
    "$SOURCE_DIR/tests/LyricsKaraokeRegression.swift" -o "$BUILD_ROOT/LyricsKaraokeRegression"
"$BUILD_ROOT/LyricsKaraokeRegression"

printf '\nChecking focus history...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/FocusHistoryPolicy.swift" \
    "$SOURCE_DIR/tests/FocusHistoryRegression.swift" -o "$BUILD_ROOT/FocusHistoryRegression"
"$BUILD_ROOT/FocusHistoryRegression"

printf '\nChecking todo capture and today progress...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/TodoCapturePolicy.swift" \
    "$SOURCE_DIR/tests/TodoCaptureRegression.swift" -o "$BUILD_ROOT/TodoCaptureRegression"
"$BUILD_ROOT/TodoCaptureRegression"

printf '\nChecking call replies...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/Communications/CallReplyPolicy.swift" \
    "$SOURCE_DIR/DynamicIsland/Communications/NotchNotificationModels.swift" \
    "$SOURCE_DIR/tests/CallReplyRegression.swift" -o "$BUILD_ROOT/CallReplyRegression"
"$BUILD_ROOT/CallReplyRegression"

printf '\nChecking meeting timing and join links...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/MeetingPolicy.swift" \
    "$SOURCE_DIR/tests/MeetingPolicyRegression.swift" -o "$BUILD_ROOT/MeetingPolicyRegression"
"$BUILD_ROOT/MeetingPolicyRegression"

printf '\nChecking context-aware tab choice...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/NotchContextTabPolicy.swift" \
    "$SOURCE_DIR/tests/NotchContextTabRegression.swift" -o "$BUILD_ROOT/NotchContextTabRegression"
"$BUILD_ROOT/NotchContextTabRegression"

printf '\nChecking adaptive tab heights...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/sizing/NotchTabHeightPolicy.swift" \
    "$SOURCE_DIR/tests/NotchTabHeightRegression.swift" -o "$BUILD_ROOT/NotchTabHeightRegression"
"$BUILD_ROOT/NotchTabHeightRegression"

printf '\nChecking the notification inbox...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/Communications/NotchNotificationModels.swift" \
    "$SOURCE_DIR/tests/NotificationHubRegression.swift" -o "$BUILD_ROOT/NotificationHubRegression"
"$BUILD_ROOT/NotificationHubRegression"

printf '\nChecking AI agent hooks (Claude Code events, approvals, settings.json install)...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/AgentHookPolicy.swift" \
    "$SOURCE_DIR/tests/AgentHookRegression.swift" -o "$BUILD_ROOT/AgentHookRegression"
"$BUILD_ROOT/AgentHookRegression"

printf '\nChecking agent conversations (Claude Code and Codex session files, resume commands)...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/AgentHookPolicy.swift" \
    "$SOURCE_DIR/DynamicIsland/helpers/AgentTranscriptPolicy.swift" \
    "$SOURCE_DIR/tests/AgentTranscriptRegression.swift" -o "$BUILD_ROOT/AgentTranscriptRegression"
"$BUILD_ROOT/AgentTranscriptRegression"

printf '\nChecking smart tools (distraction meter, copy-to-action, replies, build watcher)...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/helpers/SmartToolsPolicy.swift" \
    "$SOURCE_DIR/tests/SmartToolsRegression.swift" -o "$BUILD_ROOT/SmartToolsRegression"
"$BUILD_ROOT/SmartToolsRegression"

printf '\nChecking WhatsApp message parsing...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/managers/WhatsApp/WhatsAppModels.swift" \
    "$SOURCE_DIR/DynamicIsland/managers/WhatsApp/WhatsAppGatewayClient.swift" \
    "$SOURCE_DIR/DynamicIsland/managers/WhatsApp/WhatsAppGatewayInstaller.swift" \
    "$SOURCE_DIR/tests/WhatsAppRegression.swift" -o "$BUILD_ROOT/WhatsAppRegression"
"$BUILD_ROOT/WhatsAppRegression"

/usr/bin/xcodebuild -resolvePackageDependencies \
    -project "$SOURCE_DIR/DynamicIsland.xcodeproj" -scheme DynamicIsland \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/Packages" \
    -onlyUsePackageVersionsFromResolvedFile

# Release.command sets the version shown to users and the build number
# Sparkle compares; local builds keep the project's own values.
VERSION_SETTINGS=()
# A Release build made here (not by Release.command) checks for updates. Give
# it the current version and a build number from the commit count, so the
# updater never offers an older published release as an "update".
if [ "$CONFIGURATION" = Release ] && [ -z "${NOTCHFLOW_BUILD_NUMBER:-}" ]; then
    NOTCHFLOW_BUILD_NUMBER="$(git -C "$SOURCE_DIR" rev-list --count HEAD 2>/dev/null || true)"
    if [ -z "${NOTCHFLOW_MARKETING_VERSION:-}" ] && [ -f "$SOURCE_DIR/VERSION" ]; then
        NOTCHFLOW_MARKETING_VERSION="$(/usr/bin/tr -d '[:space:]' < "$SOURCE_DIR/VERSION")"
    fi
fi
if [ -n "${NOTCHFLOW_MARKETING_VERSION:-}" ]; then VERSION_SETTINGS+=("MARKETING_VERSION=$NOTCHFLOW_MARKETING_VERSION"); fi
if [ -n "${NOTCHFLOW_BUILD_NUMBER:-}" ]; then VERSION_SETTINGS+=("CURRENT_PROJECT_VERSION=$NOTCHFLOW_BUILD_NUMBER"); fi

/usr/bin/xcodebuild build \
    -project "$SOURCE_DIR/DynamicIsland.xcodeproj" -scheme DynamicIsland \
    -configuration "$CONFIGURATION" -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DIR" \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/Packages" \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM='' \
    ${VERSION_SETTINGS[@]+"${VERSION_SETTINGS[@]}"}

BUILT_APP="$DERIVED_DIR/Build/Products/$CONFIGURATION/NotchFlow.app"
[ -d "$BUILT_APP" ] || { printf 'Expected app was not produced: %s\n' "$BUILT_APP"; exit 1; }

# Preserve entitlements needed for Camera, Calendar, Automation, and Cuely's
# explicitly started microphone/Speech Recognition session.
LOCAL_ENTITLEMENTS="$(mktemp "$BUILD_ROOT/local-entitlements.XXXXXX")"
trap 'rm -f "$LOCAL_ENTITLEMENTS"' EXIT
cp "$SOURCE_DIR/DynamicIsland/DynamicIsland.entitlements" "$LOCAL_ENTITLEMENTS"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP/Contents/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:0 $BUNDLE_ID-spks" "$LOCAL_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:1 $BUNDLE_ID-spki" "$LOCAL_ENTITLEMENTS"

# Accessibility grants are tied to a code identity, not merely the visible app
# name. Reusing an installed development identity prevents each local rebuild
# from looking like another NotchFlow copy to TCC. Fall back to ad-hoc signing
# only on Macs without any usable code-signing identity.
SIGNING_IDENTITY="${NOTCHFLOW_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/awk '/"Apple Development:/{print $2; exit}' || true)"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
        | /usr/bin/awk '/"Developer ID Application:/{print $2; exit}' || true)"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY='-'
    printf '\nWarning: no stable code-signing identity was found; using ad-hoc signing.\n'
    printf 'Accessibility may need to be granted again after a rebuild. Add an Apple Development certificate in Xcode Accounts to make the grant stable.\n'
else
    printf '\nSigning with a stable local identity: %s\n' "$SIGNING_IDENTITY"
fi

while IFS= read -r -d '' item; do
    if /usr/bin/file -b "$item" | /usr/bin/grep -q 'Mach-O'; then
        /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$item"
    fi
done < <(/usr/bin/find "$BUILT_APP/Contents" -type f -print0)
while IFS= read -r -d '' item; do
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$item"
done < <(/usr/bin/find "$BUILT_APP/Contents" -depth -type d \
    \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) -print0)
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --entitlements "$LOCAL_ENTITLEMENTS" "$BUILT_APP"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"

# Release.command packages the signed app itself and leaves your installed copy alone.
if [ "${NOTCHFLOW_SKIP_INSTALL:-0}" = 1 ]; then
    printf '%s\n' "$BUILT_APP" > "$BUILD_ROOT/last-built-app.txt"
    printf '%s\n' "$SIGNING_IDENTITY" > "$BUILD_ROOT/last-signing-identity.txt"
    printf '\nBuilt and signed %s (not installed).\n' "$BUILT_APP"
    exit 0
fi

# Keep one NotchFlow on this Mac. A released copy (installed by install.sh or
# Release.command) lives in /Applications; this build replaces it there, and
# the next release or Check for Updates replaces this build again.
if [ -d "/Applications/NotchFlow.app" ] && [ -w "/Applications" ]; then
    INSTALL_APP="/Applications/NotchFlow.app"
    OTHER_APP="$HOME/Applications/NotchFlow.app"
else
    INSTALL_APP="$HOME/Applications/NotchFlow.app"
    OTHER_APP="/Applications/NotchFlow.app"
fi
BACKUP_ROOT="$HOME/Library/Application Support/NotchFlow/Build Backups"
mkdir -p "$(/usr/bin/dirname "$INSTALL_APP")"
mkdir -p "$BACKUP_ROOT"

# Never rename an application bundle while its executable is still running.
# Doing so changes the path macOS associates with the live process (for example,
# to "NotchFlow Backup …") and leaves Accessibility attached to the wrong copy.
# Production, former `.dev`, and timestamped backup bundles all use the same
# CFBundleExecutable, so one exact process-name check covers every local copy.
CURRENT_USER_ID="$(/usr/bin/id -u)"
running_notchflow_pids() {
    /usr/bin/pgrep -u "$CURRENT_USER_ID" -x NotchFlow 2>/dev/null || true
}

RUNNING_NOTCHFLOW_PIDS="$(running_notchflow_pids)"
if [ -n "$RUNNING_NOTCHFLOW_PIDS" ]; then
    printf '\nClosing the currently running NotchFlow before installing this build...\n'
    while IFS= read -r pid; do
        case "$pid" in
            ''|*[!0-9]*) continue ;;
        esac
        /bin/kill -TERM "$pid" 2>/dev/null || true
    done <<< "$RUNNING_NOTCHFLOW_PIDS"

    # Give AppKit time to terminate and release its bundle before any move.
    for ((attempt = 0; attempt < 40; attempt++)); do
        [ -z "$(running_notchflow_pids)" ] && break
        /bin/sleep 0.25
    done

    RUNNING_NOTCHFLOW_PIDS="$(running_notchflow_pids)"
    if [ -n "$RUNNING_NOTCHFLOW_PIDS" ]; then
        printf 'NotchFlow is still running (PID(s): %s).\n' "$(printf '%s' "$RUNNING_NOTCHFLOW_PIDS" | /usr/bin/tr '\n' ' ')"
        printf 'Quit every NotchFlow copy from the menu bar or Activity Monitor, then rerun Build.command.\n'
        printf 'The installed app and its backups were not moved.\n'
        exit 1
    fi
fi

# Older versions placed runnable backup bundles directly in ~/Applications.
# Keep those backups, but move them out of the application search path so
# macOS does not present several indistinguishable NotchFlow permission rows.
while IFS= read -r -d '' legacy_backup; do
    legacy_name="$(/usr/bin/basename "$legacy_backup")"
    destination="$BACKUP_ROOT/$legacy_name"
    if [ -e "$destination" ]; then
        destination="$BACKUP_ROOT/${legacy_name%.app}-$(date +%Y%m%d-%H%M%S).app"
    fi
    /bin/mv "$legacy_backup" "$destination"
done < <(/usr/bin/find "$HOME/Applications" -maxdepth 1 -type d -name 'NotchFlow Backup *.app' -print0)

# A second copy elsewhere would show up twice in permissions and Open With.
if [ -d "$OTHER_APP" ] && [ -w "$(/usr/bin/dirname "$OTHER_APP")" ]; then
    /bin/mv "$OTHER_APP" "$BACKUP_ROOT/NotchFlow Other Copy $(date +%Y%m%d-%H%M%S).app"
    printf 'Moved the second copy at %s to %s\n' "$OTHER_APP" "$BACKUP_ROOT"
fi

if [ -e "$INSTALL_APP" ]; then
    BACKUP_APP="$BACKUP_ROOT/NotchFlow Backup $(date +%Y%m%d-%H%M%S).app"
    /bin/mv "$INSTALL_APP" "$BACKUP_APP"
    printf 'Previous app saved as %s\n' "$BACKUP_APP"
fi
/usr/bin/ditto "$BUILT_APP" "$INSTALL_APP"

# Backups must not be launchable: macOS opens the copy with the highest build
# number, so a backed-up release (higher build number than a Debug build)
# would keep launching instead of this build. Unregister every backup and
# rename it so it is no longer an app bundle ("….app.backup"; rename it back
# to restore). Then register the installed copy as the one to launch.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
while IFS= read -r -d '' backup; do
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$backup" >/dev/null 2>&1 || true
    /bin/mv "$backup" "$backup.backup"
done < <(/usr/bin/find "$BACKUP_ROOT" -maxdepth 1 -type d -name '*.app' -print0)
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true

printf '\nInstalled %s\nAny previous running copy was stopped before its bundle was backed up.\n' "$INSTALL_APP"
if [ "$CONFIGURATION" != Release ]; then
    printf 'This is a development build: it does not check for updates. Run Release.command\n'
    printf 'to publish it, which also puts the released copy back on this Mac.\n'
fi
printf 'Reminders is a tab in Standard UI. Liquid Glass is in Settings > Appearance.\n'
printf 'Cuely is off by default; enable it in Settings > Tabs & Features > Features.\n'
# Launch exactly this copy (not whichever NotchFlow macOS picks by name).
/usr/bin/open "$INSTALL_APP"
