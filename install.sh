#!/bin/bash
#
# NotchFlow installer
#
# Install or update with one command:
#   curl -fsSL https://github.com/dhruvv620/notchflow/releases/latest/download/install.sh | bash
#
# Release.command publishes this file with every release, next to
# NotchFlow.zip, NotchFlow.dmg and the appcast.xml the app's updater reads.
#
# Downloads the latest release from GitHub, installs NotchFlow.app into
# /Applications (falls back to ~/Applications), and removes the download
# quarantine flag so Gatekeeper does not block the first launch.
#
# Release.command runs it with the zip it just published (bash install.sh
# path/to/NotchFlow.zip) so the developer's Mac gets the released copy too.

set -e

APP_NAME="NotchFlow"
DOWNLOAD_URL="https://github.com/dhruvv620/notchflow/releases/latest/download/NotchFlow.zip"
MIN_MACOS="14.6"

# Returns success (0) if version $1 is lower than version $2.
version_lt() {
    local IFS=.
    local a=($1) b=($2)
    local i x y
    for i in 0 1 2; do
        x=${a[i]:-0}
        y=${b[i]:-0}
        if [ "$x" -lt "$y" ]; then return 0; fi
        if [ "$x" -gt "$y" ]; then return 1; fi
    done
    return 1
}

echo "Installing ${APP_NAME}..."

# --- Checks ---------------------------------------------------------------

# Current builds are Apple Silicon only.
if [ "$(uname -m)" != "arm64" ]; then
    echo "Sorry - ${APP_NAME} currently runs on Apple Silicon Macs only."
    exit 1
fi

MACOS_VERSION="$(sw_vers -productVersion)"
if version_lt "$MACOS_VERSION" "$MIN_MACOS"; then
    echo "Sorry - ${APP_NAME} needs macOS ${MIN_MACOS} or later. You have ${MACOS_VERSION}."
    exit 1
fi

# --- Download -------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ -n "${1:-}" ]; then
    cp "$1" "$TMP_DIR/${APP_NAME}.zip"
else
    echo "Downloading the latest ${APP_NAME} release..."
    if ! curl -fL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/${APP_NAME}.zip"; then
        echo ""
        echo "Download failed. The release may not be published yet:"
        echo "  $DOWNLOAD_URL"
        exit 1
    fi
fi

# --- Quit any running copy -------------------------------------------------
# A running copy keeps its old code (and can block replacing the bundle).

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Quitting the running copy..."
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

# --- Install ---------------------------------------------------------------

if [ -w "/Applications" ]; then
    INSTALL_DIR="/Applications"
else
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
fi

echo "Installing to ${INSTALL_DIR}..."
# Never let the download flag reach the app (it is what makes Gatekeeper block it).
xattr -c "$TMP_DIR/${APP_NAME}.zip" 2>/dev/null || true
ditto -x -k --noqtn "$TMP_DIR/${APP_NAME}.zip" "$TMP_DIR/unzipped"

if [ ! -d "$TMP_DIR/unzipped/${APP_NAME}.app" ]; then
    echo "Install failed: ${APP_NAME}.app was not found in the download."
    exit 1
fi

rm -rf "$INSTALL_DIR/${APP_NAME}.app"
mv "$TMP_DIR/unzipped/${APP_NAME}.app" "$INSTALL_DIR/"

# Keep a single copy: a development build left in the other Applications
# folder is moved aside (not deleted).
for OTHER_DIR in "/Applications" "$HOME/Applications"; do
    [ "$OTHER_DIR" = "$INSTALL_DIR" ] && continue
    if [ -d "$OTHER_DIR/${APP_NAME}.app" ] && [ -w "$OTHER_DIR" ]; then
        BACKUPS="$HOME/Library/Application Support/${APP_NAME}/Build Backups"
        mkdir -p "$BACKUPS"
        # Not an app bundle any more, so macOS never launches it instead.
        mv "$OTHER_DIR/${APP_NAME}.app" "$BACKUPS/${APP_NAME} Other Copy $(date +%Y%m%d-%H%M%S).app.backup"
        echo "Moved an older copy from ${OTHER_DIR} to ${BACKUPS}."
    fi
done
# Backups left by earlier versions: unregister them and stop them being apps.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
BACKUPS="$HOME/Library/Application Support/${APP_NAME}/Build Backups"
if [ -d "$BACKUPS" ]; then
    # Keep backups out of Spotlight, and only the three newest.
    touch "$BACKUPS/.metadata_never_index"
    # Newest by the date in the name; a moved bundle keeps its old modification date.
    find "$BACKUPS" -maxdepth 1 -type d -name '*.app.backup' 2>/dev/null \
        | awk '{ n = split($0, p, " "); print p[n] "\t" $0 }' | sort -r | cut -f2- \
        | tail -n +4 | while IFS= read -r old_backup; do
        rm -rf "$old_backup"
    done
    find "$BACKUPS" -maxdepth 1 -type d -name '*.app' -print0 | while IFS= read -r -d '' backup; do
        [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$backup" >/dev/null 2>&1 || true
        mv "$backup" "$backup.backup"
    done
fi
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$INSTALL_DIR/${APP_NAME}.app" >/dev/null 2>&1 || true

# Clear the quarantine flag (and any other download attributes) from every
# file in the app, so macOS does not ask Apple to verify it on first launch.
xattr -cr "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true
if xattr -r "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null | grep -q com.apple.quarantine; then
    echo ""
    echo "macOS kept the download flag on ${APP_NAME}. If it says it can't verify the app,"
    echo "run this once and open it again:"
    echo "  xattr -cr \"$INSTALL_DIR/${APP_NAME}.app\""
fi

echo ""
echo "${APP_NAME} is installed. Launching it now..."
if [ "$INSTALL_DIR" != "/Applications" ]; then
    echo "(This account can't write to /Applications, so it's in your own Applications folder:"
    echo " Finder > Go > Home > Applications. Spotlight finds it too: press Cmd-Space and type ${APP_NAME}.)"
fi
open "$INSTALL_DIR/${APP_NAME}.app"

echo ""
echo "If macOS says it could not verify ${APP_NAME}: click Done, then open"
echo "System Settings > Privacy & Security, scroll down and click Open Anyway."
echo ""
echo "Done. macOS will ask for permissions (Reminders, Microphone,"
echo "Accessibility) the first time a feature needs them - allow the ones you want."
