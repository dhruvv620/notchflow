#!/bin/bash
#
# Publishes a NotchFlow release that friends can install and update from.
#
#   bash Release.command            # next version (VERSION file, or next patch)
#   bash Release.command 2.5.0      # a version you choose
#
# What it does:
#   1. Builds a signed Release copy with Build.command.
#   2. Packages NotchFlow.dmg (drag to Applications) and NotchFlow.zip (installer and updates).
#   3. Signs the update with your private update key, which stays in your login Keychain.
#   4. Publishes a GitHub release with the DMG, the zip, install.sh and appcast.xml.
#      Its notes are what's under "Unreleased" in CHANGELOG.md, which becomes this
#      version's dated section (a new, empty Unreleased starts above it). Friends
#      see the same notes in the update window.
#      The app's Check for Updates reads that appcast.xml, so everyone who has
#      NotchFlow is offered the new version.
#   5. Installs the released copy on this Mac, replacing a development build.
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
# Release from the latest pushed code, so the commits made below never leave
# your branch out of step with GitHub.
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    git pull -q --ff-only origin "$BRANCH" || fail "Your $BRANCH has commits GitHub doesn't have (or the other way round).
To match GitHub exactly:  git fetch origin && git reset --hard origin/$BRANCH"
fi

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
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    fail "v$VERSION is already released. Pass a newer version, e.g.  bash Release.command $(next_patch "$VERSION")"
fi
# A tag left by a run that stopped before publishing is made again below.
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    git tag -d "v$VERSION" >/dev/null
    git push -q origin ":refs/tags/v$VERSION" >/dev/null 2>&1 || true
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
# A valid key is base64 for exactly 32 bytes; anything else (a message from
# generate_keys, for example) must never be written into the app.
is_valid_key() {
    [ "$(printf '%s' "$1" | /usr/bin/base64 -D 2>/dev/null | /usr/bin/wc -c | /usr/bin/tr -d ' ')" = 32 ]
}
read_public_key() {
    "$SPARKLE_BIN/generate_keys" -p 2>/dev/null | /usr/bin/grep -Eo '[A-Za-z0-9+/]{43}=' | /usr/bin/tail -1 || true
}
PUBLIC_KEY="$(read_public_key)"
NEW_KEY=0
if ! is_valid_key "$PUBLIC_KEY"; then
    step "Creating your update signing key in the login Keychain (one time)"
    "$SPARKLE_BIN/generate_keys" >/dev/null 2>&1 || true
    PUBLIC_KEY="$(read_public_key)"
    NEW_KEY=1
fi
is_valid_key "$PUBLIC_KEY" || fail "Could not read a valid update signing key from Sparkle's generate_keys (got '$PUBLIC_KEY'). Run \"$SPARKLE_BIN/generate_keys\" yourself to see what it says."
CURRENT_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null || true)"
if [ "$CURRENT_KEY" != "$PUBLIC_KEY" ]; then
    step "Putting your public update key into the app"
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$INFO_PLIST"
    git add "$INFO_PLIST"
    git commit -q -m "Use this Mac's update signing key for NotchFlow releases"
fi

# --- What's new -------------------------------------------------------------------
# The Unreleased section of CHANGELOG.md becomes this version's section, so the
# next release lists only what came after it.
step "Release notes for v$VERSION (from CHANGELOG.md)"
PENDING="$(/bin/bash tools/changelog.sh pending)"
if [ -z "$PENDING" ] && ! /usr/bin/grep -q "^## \[$VERSION\]" CHANGELOG.md; then
    printf 'Nothing is listed under "## [Unreleased]" in CHANGELOG.md, so the notes will say\n'
    printf '"Improvements and fixes." Add lines there and run this again for real notes.\n'
else
    printf '%s\n' "${PENDING:-$(/bin/bash tools/changelog.sh notes "$VERSION")}"
fi
/bin/bash tools/changelog.sh roll "$VERSION" "$(/bin/date '+%Y-%m-%d')"

if [ "$(/usr/bin/tr -d '[:space:]' < VERSION)" != "$VERSION" ]; then
    printf '%s\n' "$VERSION" > VERSION
fi
if [ -n "$(git status --porcelain VERSION CHANGELOG.md)" ]; then
    git add VERSION CHANGELOG.md
    git commit -q -m "Release v$VERSION"
fi
# Push those commits now: if a later step fails, git pull still works.
git push -q origin "$BRANCH"

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
# Sparkle refuses to start ("Unable to Check For Updates") when the app's
# public key is missing or does not decode to 32 bytes; never ship that.
BUILT_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$BUILT_KEY" = "$PUBLIC_KEY" ] || fail "The built app's update key ($BUILT_KEY) is not this Mac's key ($PUBLIC_KEY)."
KEY_BYTES="$(printf '%s' "$BUILT_KEY" | /usr/bin/base64 -D 2>/dev/null | /usr/bin/wc -c | /usr/bin/tr -d ' ')"
[ "$KEY_BYTES" = 32 ] || fail "The update key in the built app does not decode to 32 bytes (got $KEY_BYTES); Sparkle would not start."
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

# Release notes: this version's section of the changelog (moved there above).
NOTES="$OUT/notes.md"
/bin/bash "$SOURCE_DIR/tools/changelog.sh" notes "$VERSION" > "$NOTES"
if [ -z "$(/usr/bin/tr -d '[:space:]' < "$NOTES")" ]; then
    printf 'Improvements and fixes.\n' > "$NOTES"
fi
# The update window shows HTML: headings, bold titles and bullet points.
HTML_NOTES="$(/bin/bash "$SOURCE_DIR/tools/changelog.sh" html "$VERSION")"
[ -n "$HTML_NOTES" ] || HTML_NOTES="<p>Improvements and fixes.</p>"
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
            <description><![CDATA[<div style="font: 13px -apple-system, sans-serif;">$HTML_NOTES</div>]]></description>
            <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/NotchFlow.zip" type="application/octet-stream" $SIGNATURE/>
        </item>
    </channel>
</rss>
APPCAST
/usr/bin/xmllint --noout "$OUT/appcast.xml" || fail "The generated appcast.xml is not valid XML."

# --- Publish -----------------------------------------------------------------------------

step "Publishing v$VERSION on GitHub"
git tag -a "v$VERSION" -m "NotchFlow $VERSION"
# The tag carries the release's commit, so the branch itself was pushed
# earlier and may have moved on meanwhile; that must not stop the release.
git push -q origin "$BRANCH" 2>/dev/null || printf 'Note: %s on GitHub has newer commits; run git pull --ff-only afterwards.\n' "$BRANCH"
git push origin "v$VERSION"
gh release create "v$VERSION" \
    "$OUT/NotchFlow.dmg" "$OUT/NotchFlow.zip" "$OUT/install.sh" "$OUT/appcast.xml" \
    --repo "$REPO" --title "NotchFlow $VERSION" --notes-file "$NOTES" --latest --verify-tag

step "Installing the released copy on this Mac"
/bin/bash "$SOURCE_DIR/install.sh" "$OUT/NotchFlow.zip" \
    || printf 'Could not install it here; run the install line below yourself.\n'

printf '\nNotchFlow %s is out, and this Mac now runs it. Send your friends either of these:\n\n' "$VERSION"
printf '  Install with one line (Terminal):\n'
printf '    curl -fsSL https://github.com/%s/releases/latest/download/install.sh | bash\n\n' "$REPO"
printf '  Or the disk image:\n'
printf '    https://github.com/%s/releases/latest/download/NotchFlow.dmg\n\n' "$REPO"
printf 'Anyone who already has NotchFlow gets it from Check for Updates (and an automatic\n'
printf 'check once a day).\n'
if [ "$NEW_KEY" = 1 ]; then
    printf '\nImportant: your update signing key was just created. Back it up now:\n'
    printf '    "%s/generate_keys" -x ~/Desktop/notchflow-update-key.txt\n' "$SPARKLE_BIN"
    printf 'and keep that file somewhere safe (not in git). Without it, a new Mac cannot\n'
    printf 'publish updates that existing copies accept. On a new Mac, import it with:\n'
    printf '    "%s/generate_keys" -f notchflow-update-key.txt\n' "$SPARKLE_BIN"
fi
