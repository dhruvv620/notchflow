#!/bin/bash
set -Eeuo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_LOG="$PACKAGE_DIR/Build.log"
exec > >(/usr/bin/tee "$BUILD_LOG") 2>&1
trap 'code=$?; printf "\nBuild stopped. Read the last error above. Log: %s\n" "$BUILD_LOG"; exit "$code"' ERR

if [ "$(/usr/bin/uname -s)" != "Darwin" ]; then
    printf 'This build script requires macOS and full Xcode.\n'
    exit 1
fi

if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
    printf 'Install full Xcode, open it once, and select its Command Line Tools in Xcode Settings > Locations.\n'
    exit 1
fi
XCODE_MAJOR="$(/usr/bin/xcodebuild -version | /usr/bin/awk '/^Xcode / { split($2,v,"."); print v[1]; exit }')"
if [ "${XCODE_MAJOR:-0}" -lt 26 ]; then
    printf 'Use Xcode 26 or newer for the Swift syntax in this pinned Atoll source.\n'
    exit 1
fi

SOURCE_DIR="$PACKAGE_DIR"
BUILD_ROOT="$HOME/Library/Caches/NotchFlow"
DERIVED_DIR="$BUILD_ROOT/DerivedData"
/bin/mkdir -p "$BUILD_ROOT"
printf 'Building source: %s\nBuild cache: %s\n' "$SOURCE_DIR" "$BUILD_ROOT"

printf '\nChecking AI process handling...\n'
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
    "$SOURCE_DIR/DynamicIsland/managers/NotchFlow/NotchCLIRunner.swift" \
    "$SOURCE_DIR/NotchFlow/Tests/NotchCLIRunnerTests.swift" -o "$BUILD_ROOT/NotchCLITests"
"$BUILD_ROOT/NotchCLITests"

printf '\nResolving the pinned Swift packages...\n'
/usr/bin/xcodebuild -resolvePackageDependencies \
    -project "$SOURCE_DIR/DynamicIsland.xcodeproj" -scheme DynamicIsland \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/Packages" \
    -onlyUsePackageVersionsFromResolvedFile

printf '\nBuilding NotchFlow...\n'
/usr/bin/xcodebuild \
    -project "$SOURCE_DIR/DynamicIsland.xcodeproj" \
    -scheme DynamicIsland -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DIR" \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/Packages" \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    DEVELOPMENT_TEAM='' \
    build

BUILT_APP="$DERIVED_DIR/Build/Products/Release/NotchFlow.app"
if [ ! -d "$BUILT_APP" ]; then
    printf 'Xcode did not produce the expected app at %s\n' "$BUILT_APP"
    exit 1
fi

printf '\nSigning the local build...\n'
# Sign nested Mach-O executables first, then their containers, then the app.
# Uses an ad-hoc local signature; no developer certificate or account is used.
while IFS= read -r -d '' item; do
    if /usr/bin/file -b "$item" | /usr/bin/grep -q 'Mach-O'; then
        /usr/bin/codesign --force --sign - "$item"
    fi
done < <(/usr/bin/find "$BUILT_APP/Contents" -type f -print0)

while IFS= read -r -d '' item; do
    /usr/bin/codesign --force --sign - "$item"
done < <(/usr/bin/find "$BUILT_APP/Contents" -depth -type d \
    \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) -print0)

/usr/bin/codesign --force --sign - --options runtime \
    --entitlements "$SOURCE_DIR/NotchFlow/Local.entitlements" "$BUILT_APP"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"

INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/NotchFlow.app"
/bin/mkdir -p "$INSTALL_DIR"
if [ -e "$INSTALL_APP" ]; then
    BACKUP_APP="$INSTALL_DIR/NotchFlow Backup $(/bin/date +%Y%m%d-%H%M%S).app"
    /bin/mv "$INSTALL_APP" "$BACKUP_APP"
    printf 'Previous custom build backed up at: %s\n' "$BACKUP_APP"
fi
/usr/bin/ditto "$BUILT_APP" "$INSTALL_APP"
printf '\nInstalled: %s\n' "$INSTALL_APP"
printf 'Quit your original Atoll, then open NotchFlow from the Finder window.\n'
printf 'Open Settings > Appearance to choose a notch color theme.\n'
/usr/bin/open -R "$INSTALL_APP"
