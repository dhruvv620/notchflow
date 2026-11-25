#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 dhruvv620
#
# How much of the app's code is still inherited from Atoll / boring.notch.
# Counts each line by who last wrote it (git blame), so a line we rewrote
# counts as ours. Run it after each rewrite stage; the goal is 0 inherited.
#
#   bash tools/provenance.sh            # totals and the biggest folders
#   bash tools/provenance.sh --files    # every file that still has inherited lines
#
# "Ours" means commits by the emails listed in OUR_EMAILS (a regular expression).
# Note: a line we only renamed or reformatted still counts as ours here, but it
# is NOT clean-room code. The rewrite plan (docs/PLAN_PRIVATE_AND_REWRITE.md)
# replaces whole files, which this script then shows as 0 inherited.

set -euo pipefail
cd "$(dirname "$0")/.."
OUR_EMAILS="${OUR_EMAILS:-dhr|noreply@anthropic\.com|users\.noreply\.github\.com}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

git ls-files -z 'DynamicIsland/*.swift' 'DynamicIsland/*.metal' 'DynamicIsland/*.cpp' \
    'DynamicIsland/*.hpp' 'DynamicIsland/*.mm' 'DynamicIsland/*.h' |
while IFS= read -r -d '' file; do
    git blame -w -M --line-porcelain -- "$file" 2>/dev/null |
        awk -v f="$file" -v ours="$OUR_EMAILS" '
            /^author-mail / { if ($2 ~ ours) o++; else i++ }
            END { printf "%s\t%d\t%d\n", f, o + 0, i + 0 }'
done > "$TMP"

awk -F'\t' '{ o += $2; i += $3 }
    END { t = o + i; if (t == 0) t = 1
          printf "Ours:      %7d lines\nInherited: %7d lines (%.0f%%)\n\n", o, i, 100 * i / t }' "$TMP"

if [ "${1:-}" = "--files" ]; then
    awk -F'\t' '$3 > 0 { printf "%6d  %s\n", $3, $1 }' "$TMP" | sort -rn
else
    echo "Inherited lines by folder:"
    awk -F'\t' '{ d = $1; sub(/^DynamicIsland\//, "", d); n = split(d, p, "/")
                  k = (n > 2) ? p[1] "/" p[2] : (n == 2 ? p[1] : "(app root)")
                  i[k] += $3 }
        END { for (k in i) if (i[k] > 0) printf "%6d  %s\n", i[k], k }' "$TMP" | sort -rn | head -30
fi
