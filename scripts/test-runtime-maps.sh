#!/bin/bash
#
# Runtime library-mapping check -- the ground-truth form of the coexistence
# guarantee. Reads what a LIVE driver process actually mapped out of
# /proc/<pid>/maps, rather than what ldd predicts it would map.
#
# This matters because indiserver itself links NO libindi library at all (only
# libev/libnova/libc), so checking the server proves nothing about library
# separation. The DRIVERS are what link libindidriver/libindiclient.
#
# Needs no root. Run as: bash scripts/test-runtime-maps.sh
#
# DO NOT reach for `pkill -f indiserver` to clean up. That pattern matches the
# calling shell's own argv and kills the harness mid-script -- it cost a
# debugging detour on 2026-08-24 (LESSONS_LEARNED.md #9). This script uses
# captured PIDs and lives in a file so the pattern cannot appear in a caller's
# command line.
#
set -u

SERVER=${1:-/usr/bin/indiserver-stable}
DRIVER=${2:-/opt/indi-stable/bin/indi_simulator_ccd}
PORT=${3:-7625}
LOG=$(mktemp)

test -x "$SERVER" || { echo "no such server: $SERVER"; exit 1; }
test -x "$DRIVER" || { echo "no such driver: $DRIVER"; exit 1; }

echo "=== $SERVER  (port $PORT) ==="
"$SERVER" -p "$PORT" "$DRIVER" >"$LOG" 2>&1 &
SRV=$!
sleep 4

DRV=$(pgrep -P $SRV | head -1)
if [ -z "$DRV" ]; then
  echo "  *** no driver child spawned -- server log follows ***"
  cat "$LOG"
  kill $SRV 2>/dev/null; wait $SRV 2>/dev/null; rm -f "$LOG"
  exit 1
fi

echo "  server pid $SRV, driver pid $DRV"
echo "  INDI libraries mapped by the LIVE driver:"
grep -oE '/[^ ]*libindi[^ ]*' /proc/$DRV/maps | sort -u | sed 's/^/    /'

echo "  -- for contrast, what the SONAMEs resolve to system-wide:"
ldconfig -p | grep -E 'libindidriver|libindiclient|libindiAlignmentDriver' \
  | sed 's/^\s*/    /'

kill $SRV 2>/dev/null
wait $SRV 2>/dev/null
rm -f "$LOG"
echo "=== cleaned up ==="
