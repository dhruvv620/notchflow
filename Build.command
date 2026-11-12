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

while IFS= read -r -d '' item; do
    if /usr/bin/file -b "$item" | /usr/bin/grep -q 'Mach-O'; then
        /usr/bin/codesign --force --sign - "$item"
    fi
done < <(/usr/bin/find "$BUILT_APP/Contents" -type f -print0)
while IFS= read -r -d '' item; do
    /usr/bin/codesign --force --sign - "$item"
done < <(/usr/bin/find "$BUILT_APP/Contents" -depth -type d \
    \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) -print0)
/usr/bin/codesign --force --sign - --options runtime --entitlements "$LOCAL_ENTITLEMENTS" "$BUILT_APP"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"

INSTALL_APP="$HOME/Applications/NotchFlow.app"
mkdir -p "$HOME/Applications"
if [ -e "$INSTALL_APP" ]; then
    BACKUP_APP="$HOME/Applications/NotchFlow Backup $(date +%Y%m%d-%H%M%S).app"
    /bin/mv "$INSTALL_APP" "$BACKUP_APP"
    printf 'Previous app saved as %s\n' "$BACKUP_APP"
fi
/usr/bin/ditto "$BUILT_APP" "$INSTALL_APP"
printf '\nInstalled %s\nQuit the old notch app before opening this build.\n' "$INSTALL_APP"
printf 'Reminders is a tab in Standard UI. Liquid Glass is in Settings > Appearance.\n'
/usr/bin/open -R "$INSTALL_APP"
