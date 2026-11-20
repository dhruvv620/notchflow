#!/bin/bash
#
# Release notes from CHANGELOG.md, used by Release.command.
#
#   bash tools/changelog.sh roll 1.2.2 2026-11-21   # Unreleased becomes "## [1.2.2] - 2026-11-21",
#                                                  # with a new, empty Unreleased above it
#   bash tools/changelog.sh notes 1.2.2            # that version's notes (empty headings left out)
#   bash tools/changelog.sh html 1.2.2             # the same notes as simple HTML (for the update window)
#   bash tools/changelog.sh pending                # what's under Unreleased right now
#
# Write changes under "## [Unreleased]" as you go (### Added, ### Changed, ### Fixed).

set -euo pipefail
FILE="${CHANGELOG:-$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md}"

section() { # $1: the heading's text inside [ ], e.g. Unreleased or 1.2.2
    /usr/bin/awk -v want="$1" '
        /^## \[/ { if (on) exit; on = (index($0, "## [" want "]") == 1); next }
        on' "$FILE"
}

# Drops headings with nothing under them, and blank lines at the ends.
tidy() {
    /usr/bin/awk '
        /^### / { heading = $0; next }
        /^[[:space:]]*$/ { if (printed) blank = 1; next }
        { if (heading != "") { if (printed) print ""; print heading; heading = "" ; blank = 0 }
          else if (blank) { print ""; blank = 0 }
          print; printed = 1 }'
}

case "${1:-}" in
    pending)
        section Unreleased | tidy
        ;;
    notes)
        [ -n "${2:-}" ] || { echo "usage: $0 notes VERSION" >&2; exit 2; }
        section "$2" | tidy
        ;;
    html)
        [ -n "${2:-}" ] || { echo "usage: $0 html VERSION" >&2; exit 2; }
        section "$2" | tidy | /usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | /usr/bin/awk '
            function inline(text) {
                while (match(text, /\*\*[^*]+\*\*/)) {
                    text = substr(text, 1, RSTART - 1) "<b>" substr(text, RSTART + 2, RLENGTH - 4) "</b>" substr(text, RSTART + RLENGTH)
                }
                while (match(text, /`[^`]+`/)) {
                    text = substr(text, 1, RSTART - 1) "<code>" substr(text, RSTART + 1, RLENGTH - 2) "</code>" substr(text, RSTART + RLENGTH)
                }
                return text
            }
            /^### / { if (list) { print "</ul>"; list = 0 } print "<h3>" substr($0, 5) "</h3>"; next }
            /^- / { if (!list) { print "<ul>"; list = 1 } print "<li>" inline(substr($0, 3)) "</li>"; next }
            /^[[:space:]]*$/ { next }
            { if (list) { print "</ul>"; list = 0 } print "<p>" inline($0) "</p>" }
            END { if (list) print "</ul>" }'
        ;;
    roll)
        [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "usage: $0 roll VERSION DATE" >&2; exit 2; }
        if grep -q "^## \[$2\]" "$FILE"; then exit 0; fi   # already rolled (a re-run)
        tmp="$(mktemp)"
        /usr/bin/awk -v version="$2" -v date="$3" '
            /^## \[Unreleased\]/ && !done {
                print; print ""; print "### Added"; print ""; print "### Changed"; print ""; print "### Fixed"; print ""
                print "## [" version "] - " date
                done = 1; next
            }
            { print }' "$FILE" > "$tmp"
        /bin/mv "$tmp" "$FILE"
        ;;
    *)
        echo "usage: $0 pending | notes VERSION | html VERSION | roll VERSION DATE" >&2
        exit 2
        ;;
esac
