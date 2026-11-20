#!/bin/bash
#
# Measures how much CPU, memory, energy and idle wake-ups NotchFlow uses.
#
#   bash tools/energy-report.sh            # 5 minutes, labelled "run"
#   bash tools/energy-report.sh 10 before  # 10 minutes, labelled "before"
#
# Run it once before a change and once after, in the same situation (for
# example: notch closed, nothing playing, same apps open, plugged in), and
# compare the two reports. Each report is saved on the Desktop.
#
# Uses only built-in tools (top, vmmap, ps, pmset); no password needed.

set -u

MINUTES="${1:-5}"
LABEL="${2:-run}"
INTERVAL=5

case "$MINUTES" in ''|*[!0-9]*) echo "Usage: bash tools/energy-report.sh [minutes] [label]"; exit 1 ;; esac
[ "$(uname -s)" = Darwin ] || { echo "Run this on the Mac that runs NotchFlow."; exit 1; }

PID="$(pgrep -x NotchFlow | head -1)"
[ -n "$PID" ] || { echo "NotchFlow is not running. Open it, wait a minute, then run this again."; exit 1; }

# The app bundle the running process comes from.
EXECUTABLE="$(ps -o comm= -p "$PID")"
APP="${EXECUTABLE%%.app/*}.app"
INFO="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO" 2>/dev/null || echo '?')"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO" 2>/dev/null || echo '?')"
if [ -e "$APP/Contents/MacOS/NotchFlow.debug.dylib" ]; then CONFIG="Debug"; else CONFIG="Release"; fi

# Helper processes NotchFlow started (media adapter, WhatsApp gateway, …).
CHILDREN="$(pgrep -P "$PID" | tr '\n' ' ')"
PIDS="$PID $CHILDREN"
PID_ARGS=""
for p in $PIDS; do PID_ARGS="$PID_ARGS -pid $p"; done

SAMPLES=$(( MINUTES * 60 / INTERVAL + 1 ))
STAMP="$(date '+%Y-%m-%d %H.%M')"
OUT="$HOME/Desktop/NotchFlow energy - $LABEL - $STAMP.txt"
RAW="$(mktemp -t notchflow-energy)"
trap 'rm -f "$RAW"' EXIT

POWER_SOURCE="$(pmset -g batt | head -1 | sed "s/Now drawing from //; s/'//g")"
LOW_POWER="$(pmset -g | awk '/lowpowermode/ {print ($2 == 1 ? "on" : "off")}')"

{
    echo "NotchFlow energy report: $LABEL"
    echo "Date:            $(date)"
    echo "App:             $APP"
    echo "Version:         $VERSION (build $BUILD), $CONFIG build"
    echo "Running for:     $(ps -o etime= -p "$PID" | tr -d ' ') (since launch)"
    echo "Mac:             $(sysctl -n hw.model), macOS $(sw_vers -productVersion)"
    echo "Power:           ${POWER_SOURCE:-unknown}, Low Power Mode ${LOW_POWER:-unknown}"
    echo "Measured:        $MINUTES min, a sample every $INTERVAL s"
    echo
} | tee "$OUT"

echo "Measuring for $MINUTES minutes. Use the Mac as you normally would for this test"
echo "(or leave it alone with the notch closed), the same way each time…"
echo

# shellcheck disable=SC2086
top -l "$SAMPLES" -s "$INTERVAL" -stats pid,command,cpu,mem,idlew,power $PID_ARGS > "$RAW" 2>/dev/null

# One row per process: pid command %cpu mem idlew power. The first sample of
# each process has no CPU history, so it is skipped for averages.
awk -v pids="$PIDS" -v interval="$INTERVAL" '
function megabytes(value,    number, unit) {
    gsub(/[+-]$/, "", value)
    number = value + 0
    unit = substr(value, length(value), 1)
    if (unit == "K") return number / 1024
    if (unit == "M") return number
    if (unit == "G") return number * 1024
    if (unit == "B") return number / 1048576
    return number / 1048576
}
BEGIN { n = split(pids, list, " "); for (i = 1; i <= n; i++) wanted[list[i]] = 1 }
$1 ~ /^[0-9]+$/ && ($1 in wanted) && NF >= 6 {
    pid = $1
    cpu = $(NF - 3) + 0; mem = megabytes($(NF - 2)); idle = $(NF - 1); power = $NF + 0
    gsub(/[^0-9]/, "", idle); idle = idle + 0
    name = $2; for (i = 3; i <= NF - 4; i++) name = name " " $i
    names[pid] = name
    count[pid]++
    if (count[pid] == 1) { firstIdle[pid] = idle; firstMem[pid] = mem; maxMem[pid] = mem; minIdle[pid] = idle; next }
    used[pid]++
    sumCPU[pid] += cpu; if (cpu > maxCPU[pid]) maxCPU[pid] = cpu
    sumPower[pid] += power; if (power > maxPower[pid]) maxPower[pid] = power
    sumIdle[pid] += idle
    if (idle < lastIdle[pid]) decreasing[pid] = 1
    lastIdle[pid] = idle; lastMem[pid] = mem; if (mem > maxMem[pid]) maxMem[pid] = mem
}
END {
    for (pid in count) {
        if (used[pid] < 1) continue
        samples = used[pid]
        # IDLEW is either a running total or a per-sample count; handle both.
        if (!decreasing[pid] && lastIdle[pid] >= firstIdle[pid] && lastIdle[pid] > 50 * samples) {
            wakeups = (lastIdle[pid] - firstIdle[pid]) / (samples * interval)
        } else {
            wakeups = sumIdle[pid] / samples / interval
        }
        printf "%s (pid %s)\n", names[pid], pid
        printf "  CPU             average %.2f %%, peak %.1f %%\n", sumCPU[pid] / samples, maxCPU[pid]
        printf "  Energy impact   average %.2f, peak %.1f\n", sumPower[pid] / samples, maxPower[pid]
        printf "  Idle wake-ups   %.1f per second\n", wakeups
        printf "  Memory          %.0f MB at start, %.0f MB at end, %.0f MB at most\n\n", firstMem[pid], lastMem[pid], maxMem[pid]
        totalCPU += sumCPU[pid] / samples; totalPower += sumPower[pid] / samples
        totalWake += wakeups; totalMem += lastMem[pid]
    }
    printf "Total (NotchFlow and its helpers)\n"
    printf "  CPU %.2f %%   Energy impact %.2f   Idle wake-ups %.1f/s   Memory %.0f MB\n", totalCPU, totalPower, totalWake, totalMem
}' "$RAW" | tee -a "$OUT"

PEAK="$(vmmap -summary "$PID" 2>/dev/null | awk -F': *' '/Physical footprint \(peak\)/ {print $2}')"
[ -n "$PEAK" ] && echo "  Peak memory since launch: $PEAK" | tee -a "$OUT"

echo
echo "Saved: $OUT"
echo "Compare it with the other report, e.g.:  diff -y \"<before file>\" \"<after file>\""
