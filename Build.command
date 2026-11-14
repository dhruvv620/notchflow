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
    printf 'Install Git LFS (brew install git-lfs) to download Atoll’s original animation assets, then rerun this script.\n'
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

/usr/bin/xcodebuild -resolvePackageDependencies \
    -project "$SOURCE_DIR/DynamicIsland.xcodeproj" -scheme DynamicIsland \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/Packages" \
    -onlyUsePackageVersionsFromResolvedFile

/usr/bin/xcodebuild build \
    -project "$SOURCE_DIR/DynamicIsland.xcodeproj" -scheme DynamicIsland \
    -configuration "$CONFIGURATION" -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DIR" \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/Packages" \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=''

BUILT_APP="$DERIVED_DIR/Build/Products/$CONFIGURATION/NotchFlow.app"
[ -d "$BUILT_APP" ] || { printf 'Expected app was not produced: %s\n' "$BUILT_APP"; exit 1; }

# Preserve the upstream entitlements needed for Camera, Calendar and Automation.
# The legacy Mach service is disabled and cannot be signed ad hoc.
LOCAL_ENTITLEMENTS="$(mktemp "$BUILD_ROOT/local-entitlements.XXXXXX")"
trap 'rm -f "$LOCAL_ENTITLEMENTS"' EXIT
cp "$SOURCE_DIR/DynamicIsland/DynamicIsland.entitlements" "$LOCAL_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.mach-services' "$LOCAL_ENTITLEMENTS"
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

INSTALL_APP="$HOME/Applications/NotchFlow.app"
BACKUP_ROOT="$HOME/Library/Application Support/NotchFlow/Build Backups"
mkdir -p "$HOME/Applications"
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

if [ -e "$INSTALL_APP" ]; then
    BACKUP_APP="$BACKUP_ROOT/NotchFlow Backup $(date +%Y%m%d-%H%M%S).app"
    /bin/mv "$INSTALL_APP" "$BACKUP_APP"
    printf 'Previous app saved as %s\n' "$BACKUP_APP"
fi
/usr/bin/ditto "$BUILT_APP" "$INSTALL_APP"
printf '\nInstalled %s\nAny previous running copy was stopped before its bundle was backed up.\n' "$INSTALL_APP"
printf 'Reminders is a tab in Standard UI. Liquid Glass is in Settings > Appearance.\n'
/usr/bin/open -R "$INSTALL_APP"
