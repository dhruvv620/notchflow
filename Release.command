#!/bin/bash
#
# Publishes a NotchFlow release that friends can install and update from.
#
#   bash Release.command            # next version (VERSION file, or next patch)
#   bash Release.command 2.5.0      # a version you choose
#
# What it does:
#   1. Builds a signed Release copy with Build.command (your installed copy is untouched).
#   2. Packages NotchFlow.dmg (drag to Applications) and NotchFlow.zip (installer and updates).
#   3. Signs the update with your private update key, which stays in your login Keychain.
#   4. Publishes a GitHub release with the DMG, the zip, install.sh and appcast.xml.
#      The app's Check for Updates reads that appcast.xml, so everyone who has
#      NotchFlow is offered the new version.
#
# Needs: Xcode 26, the GitHub CLI (brew install gh, then gh auth login),
# and a clean git tree (a release is built from what is committed).

set -Eeuo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="dhruvv620/notchflow"
BUILD_ROOT="$HOME/Library/Caches/NotchFlowFresh"
INFO_PLIST="$SOURCE_DIR/DynamicIsland/Info.plist"

fail() { printf '\n%s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# Returns success if version $1 is greater than version $2 (x.y.z).
version_gt() {
    local IFS=.
    local a=($1) b=($2) i
    for i in 0 1 2; do
        if [ "${a[i]:-0}" -gt "${b[i]:-0}" ]; then return 0; fi
        if [ "${a[i]:-0}" -lt "${b[i]:-0}" ]; then return 1; fi
    done
    return 1
}

next_patch() {
    local IFS=.
    local v=($1)
    printf '%s.%s.%s' "${v[0]:-0}" "${v[1]:-0}" "$(( ${v[2]:-0} + 1 ))"
}

# --- Checks -------------------------------------------------------------------

[ "$(/usr/bin/uname -s)" = Darwin ] || fail "Release.command needs a Mac with Xcode."
command -v gh >/dev/null 2>&1 || fail "Install the GitHub CLI first:  brew install gh   then:  gh auth login"
gh auth status >/dev/null 2>&1 || fail "Sign in to GitHub first:  gh auth login"
cd "$SOURCE_DIR"
[ -z "$(git status --porcelain)" ] || fail "Commit or stash your changes first; a release is built from what is committed."
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != HEAD ] || fail "Check out a branch first."
git fetch --tags origin >/dev/null 2>&1 || true

# --- Version --------------------------------------------------------------------

LATEST_TAG="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || true)"
LATEST_VERSION="${LATEST_TAG#v}"
if [ $# -ge 1 ]; then
    VERSION="${1#v}"
else
    VERSION="$(/usr/bin/tr -d '[:space:]' < VERSION)"
    if [ -n "$LATEST_VERSION" ] && ! version_gt "$VERSION" "$LATEST_VERSION"; then
        VERSION="$(next_patch "$LATEST_VERSION")"
    fi
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Use a version like 2.5.0 (got '$VERSION')."
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    fail "v$VERSION is already released. Pass a newer version, e.g.  bash Release.command $(next_patch "$VERSION")"
fi

# Sparkle offers an update only when its build number is higher than the
# installed one, so it must beat every published build and local builds.
PUBLISHED_BUILD="$(/usr/bin/curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
    | /usr/bin/sed -n 's:.*<sparkle\:version>\([0-9][0-9]*\)</sparkle\:version>.*:\1:p' | /usr/bin/sort -n | /usr/bin/tail -1 || true)"
PROJECT_BUILD="$(/usr/bin/sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);.*/\1/p' DynamicIsland.xcodeproj/project.pbxproj | /usr/bin/sort -n | /usr/bin/tail -1)"
BUILD_NUMBER="$(git rev-list --count HEAD)"
for floor in "${PUBLISHED_BUILD:-0}" "${PROJECT_BUILD:-0}"; do
    if [ "$floor" -ge "$BUILD_NUMBER" ]; then BUILD_NUMBER=$((floor + 1)); fi
done

printf 'Releasing NotchFlow %s (build %s) from %s to github.com/%s\n' "$VERSION" "$BUILD_NUMBER" "$BRANCH" "$REPO"

# --- Update signing key -----------------------------------------------------------

step "Preparing Sparkle's signing tools"
/usr/bin/xcodebuild -resolvePackageDependencies \
    -project "$SOURCE_DIR/DynamicIsland.xcodeproj" -scheme DynamicIsland \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/Packages" \
    -onlyUsePackageVersionsFromResolvedFile >/dev/null
SIGN_UPDATE="$(/usr/bin/find "$BUILD_ROOT/Packages/artifacts" -type f -name sign_update -path '*parkle*' 2>/dev/null | /usr/bin/head -1)"
[ -n "$SIGN_UPDATE" ] || fail "Sparkle's sign_update tool was not found under $BUILD_ROOT/Packages/artifacts."
SPARKLE_BIN="$(/usr/bin/dirname "$SIGN_UPDATE")"

# The private key lives in your login Keychain (created once); only the
# public half goes into the app, so updates signed on this Mac are trusted.
PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
if [ -z "$PUBLIC_KEY" ]; then
    step "Creating your update signing key in the login Keychain (one time)"
    "$SPARKLE_BIN/generate_keys" >/dev/null
    PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"
fi
[ -n "$PUBLIC_KEY" ] || fail "Could not read the update signing key from the Keychain."
CURRENT_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null || true)"
if [ "$CURRENT_KEY" != "$PUBLIC_KEY" ]; then
    step "Putting your public update key into the app"
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$INFO_PLIST"
    git add "$INFO_PLIST"
    git commit -q -m "Use this Mac's update signing key for NotchFlow releases"
fi

if [ "$(/usr/bin/tr -d '[:space:]' < VERSION)" != "$VERSION" ]; then
    printf '%s\n' "$VERSION" > VERSION
    git add VERSION
    git commit -q -m "Release v$VERSION"
fi

# --- Build ---------------------------------------------------------------------------

step "Building and signing (this runs the regression checks too)"
NOTCHFLOW_CONFIGURATION=Release NOTCHFLOW_SKIP_INSTALL=1 \
NOTCHFLOW_MARKETING_VERSION="$VERSION" NOTCHFLOW_BUILD_NUMBER="$BUILD_NUMBER" \
    /bin/bash "$SOURCE_DIR/Build.command"
APP="$(/bin/cat "$BUILD_ROOT/last-built-app.txt")"
IDENTITY="$(/bin/cat "$BUILD_ROOT/last-signing-identity.txt")"
[ -d "$APP" ] || fail "The build did not produce an app."
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILT_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[ "$BUILT_VERSION" = "$VERSION" ] && [ "$BUILT_NUMBER" = "$BUILD_NUMBER" ] \
    || fail "The app says $BUILT_VERSION ($BUILT_NUMBER), expected $VERSION ($BUILD_NUMBER)."
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo 14.0)"
if [ "$IDENTITY" = "-" ]; then
    printf '\nWarning: this build is ad-hoc signed. Friends will have to grant permissions\n'
    printf 'again after every update. Add a certificate in Xcode > Settings > Accounts >\n'
    printf 'Manage Certificates (Apple Development) and release again to fix that.\n'
fi

# --- Package ---------------------------------------------------------------------------

OUT="$BUILD_ROOT/Releases/v$VERSION"
/bin/rm -rf "$OUT"
/bin/mkdir -p "$OUT"

step "Packaging NotchFlow.zip and NotchFlow.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/NotchFlow.zip"
STAGE="$OUT/dmg-contents"
/bin/mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/NotchFlow.app"
/bin/ln -s /Applications "$STAGE/Applications"
/usr/bin/hdiutil create -quiet -volname "NotchFlow $VERSION" -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO -ov "$OUT/NotchFlow.dmg"
/bin/rm -rf "$STAGE"
if [ "$IDENTITY" != "-" ]; then
    /usr/bin/codesign --force --sign "$IDENTITY" "$OUT/NotchFlow.dmg"
fi
/bin/cp "$SOURCE_DIR/install.sh" "$OUT/install.sh"

step "Signing the update"
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$OUT/NotchFlow.zip")"
[[ "$SIGNATURE" == *edSignature=* && "$SIGNATURE" == *length=* ]] || fail "sign_update did not return a signature: $SIGNATURE"

# Release notes: the Unreleased section of the changelog.
NOTES="$OUT/notes.md"
/usr/bin/awk '/^## \[Unreleased\]/{found=1; next} /^## \[/{if (found) exit} found' CHANGELOG.md > "$NOTES"
if [ -z "$(/usr/bin/tr -d '[:space:]' < "$NOTES")" ]; then
    printf 'NotchFlow %s\n' "$VERSION" > "$NOTES"
fi
ESCAPED_NOTES="$(/usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$NOTES")"
PUB_DATE="$(LC_ALL=C /bin/date -u '+%a, %d %b %Y %H:%M:%S +0000')"

/bin/cat > "$OUT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>NotchFlow</title>
        <item>
            <title>NotchFlow $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
            <description><![CDATA[<pre style="white-space: pre-wrap; font: 12px -apple-system, sans-serif;">$ESCAPED_NOTES</pre>]]></description>
            <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/NotchFlow.zip" type="application/octet-stream" $SIGNATURE/>
        </item>
    </channel>
</rss>
APPCAST
/usr/bin/xmllint --noout "$OUT/appcast.xml" || fail "The generated appcast.xml is not valid XML."

# --- Publish -----------------------------------------------------------------------------

step "Publishing v$VERSION on GitHub"
git tag -a "v$VERSION" -m "NotchFlow $VERSION"
git push origin "$BRANCH"
git push origin "v$VERSION"
gh release create "v$VERSION" \
    "$OUT/NotchFlow.dmg" "$OUT/NotchFlow.zip" "$OUT/install.sh" "$OUT/appcast.xml" \
    --repo "$REPO" --title "NotchFlow $VERSION" --notes-file "$NOTES" --latest --verify-tag

printf '\nNotchFlow %s is out. Send your friends either of these:\n\n' "$VERSION"
printf '  Install with one line (Terminal):\n'
printf '    curl -fsSL https://github.com/%s/releases/latest/download/install.sh | bash\n\n' "$REPO"
printf '  Or the disk image:\n'
printf '    https://github.com/%s/releases/latest/download/NotchFlow.dmg\n\n' "$REPO"
printf 'Anyone who already has NotchFlow gets it from Check for Updates (and an automatic\n'
printf 'check once a day).\n'
