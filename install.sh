#!/bin/bash
#
# NotchFlow installer
#
# Install or update with one command:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/dhruvv620/notchflow/fresh/reminders-liquid-glass/install.sh)"
#
# Downloads the latest release from GitHub, installs NotchFlow.app into
# /Applications (falls back to ~/Applications), and removes the download
# quarantine flag so Gatekeeper does not block the first launch.

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

echo "Downloading the latest ${APP_NAME} release..."
if ! curl -fL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/${APP_NAME}.zip"; then
    echo ""
    echo "Download failed. The release may not be published yet:"
    echo "  $DOWNLOAD_URL"
    exit 1
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
ditto -x -k "$TMP_DIR/${APP_NAME}.zip" "$TMP_DIR/unzipped"

if [ ! -d "$TMP_DIR/unzipped/${APP_NAME}.app" ]; then
    echo "Install failed: ${APP_NAME}.app was not found in the download."
    exit 1
fi

rm -rf "$INSTALL_DIR/${APP_NAME}.app"
mv "$TMP_DIR/unzipped/${APP_NAME}.app" "$INSTALL_DIR/"

# Remove the quarantine flag so the first launch is not blocked.
xattr -dr com.apple.quarantine "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true

echo ""
echo "${APP_NAME} is installed. Launching it now..."
open "$INSTALL_DIR/${APP_NAME}.app"

echo "Done. macOS will ask for permissions (Reminders, Microphone,"
echo "Accessibility) the first time a feature needs them - allow the ones you want."
