#!/bin/bash
#
# Observe what Ekos ACTUALLY launched, while it is running.
#
# Run this from a terminal (or a Claude Code session -- no root needed) with a
# KStars/Ekos simulator profile started. Optional args: control port (default
# 7627) and control socket name (default /tmp/indiserver-ekos-control); both
# exist only so the control cannot collide with the server Ekos is running. It answers, from the filesystem rather
# than from a screenshot, three questions the GUI cannot:
#
#   * which indiserver binary did Ekos spawn?
#   * which driver binaries did that server exec?
#   * which libindi libraries did those processes map?
#
# Why this and not "the driver list looked like the distro's": the Ekos list
# CANNOT distinguish the two installs. That conclusion still holds, but the
# reason it holds changed when the catalogue gained absolute paths, and this
# comment said the old one until 2026-08-26.
#
# It used to be that the two drivers.xml files were byte-identical and both
# named drivers by bare name. They are no longer identical -- ours rewrites 288
# entries to /opt/indi-stable/bin (DESIGN.md, "Resolution -- absolute paths in
# our drivers.xml"), the distribution's rewrites none, and the two files hash
# differently. Measured on fedoraastro:
#
#   ours   <driver name="CCD Simulator">/opt/indi-stable/bin/indi_simulator_ccd</driver>
#   distro <driver name="CCD Simulator">indi_simulator_ccd</driver>
#
# What Ekos DISPLAYS, though, is the name= label, not the binary path -- and
# the label sets are identical, 290 apiece, checked by comparing them directly.
# So the visible list is the same in both cases while the thing that actually
# differs is hidden inside the element. A GUI check would look like it was
# working and be reading the one field that cannot answer.
#
# The identity of the running processes can. LESSONS_LEARNED.md #11 -- ask the
# question that has a filesystem answer, not the one answered by a label.
#
# What counts as the expected result depends on ONE setting -- Ekos's "INDI
# drivers XML directory" (kstarsrc, [indi], indiDriversDir):
#
#   /usr/share/indi (the default)   -> everything must resolve to /usr.
#                                      Anything under /opt would mean we are
#                                      reaching into a session that did not
#                                      ask for us.
#   /opt/indi-stable/share/indi     -> the drivers must resolve to /opt.
#                                      Our catalogue carries absolute paths,
#                                      so this is the opt-in working.
#
# Both are correct outcomes; the script reports which one it saw rather than
# guessing which was intended. Note indiserver stays the DISTRIBUTION's in
# both cases -- Ekos spawns it, and it links no INDI library, so it is not
# the thing that decides which build gets used.
#
set -u

PORT=${1:-7627}
# The control server needs its OWN abstract socket. indiserver binds
# @/tmp/indiserver by default (`-u path`, machine-global, NOT per-port), so a
# second indiserver started while Ekos has a profile running dies instantly
# with "Local server: bind: Address already in use" no matter what -p says.
# See DESIGN.md, "One indiserver per machine unless -u says otherwise".
USOCK=${2:-/tmp/indiserver-ekos-control}
CLOG=$(mktemp)
FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }

# Scan /proc by exe path rather than by command-line pattern. `pgrep -af indi`
# would also match this script's own argv (LESSONS_LEARNED.md #9); an exe
# readlink cannot.
scan() {
  local pid exe base
  for pid in /proc/[0-9]*; do
    pid=${pid#/proc/}
    exe=$(readlink -e "/proc/$pid/exe" 2>/dev/null) || continue
    base=${exe##*/}
    case $base in
      indiserver|indi_*) echo "$pid $exe" ;;
    esac
  done
}

report() {
  local pid=$1 exe=$2 owner libs
  owner=$(rpm -qf "$exe" 2>/dev/null) || owner="(no package owns it)"
  printf '  pid %-7s %s\n' "$pid" "$exe"
  printf '           owned by: %s\n' "$owner"
  libs=$(grep -oE '/[^ ]*/libindi[^ ]*\.so[^ ]*' "/proc/$pid/maps" 2>/dev/null | sort -u)
  if test -n "$libs"; then
    while IFS= read -r l; do printf '           maps: %s\n' "$l"; done <<< "$libs"
  else
    printf '           maps: (no libindi library -- expected for indiserver itself)\n'
  fi
  case $exe$libs in
    *"/opt/indi-stable"*) echo "           ^^ resolves into OUR prefix" ;;
  esac
}

echo "############ STEP 1: what is Ekos running right now? ############"
MAP=$(scan)
test -n "$MAP" \
  || die "no indiserver or indi_* process found. Start KStars, open Ekos, and START a simulator profile before running this -- a test that cannot tell 'passed' from 'never ran' is worse than no test (LESSONS_LEARNED.md #5)."

COUNT=$(wc -l <<< "$MAP")
echo "  found $COUNT INDI process(es)"
echo
while read -r pid exe; do report "$pid" "$exe"; done <<< "$MAP"

echo
echo "############ STEP 2: did any of it come from our prefix? ############"
OURS=$(while read -r pid exe; do
         { echo "$exe"; cat "/proc/$pid/maps" 2>/dev/null; } | grep -q '/opt/indi-stable' && echo "$pid $exe"
       done <<< "$MAP")
if test -z "$OURS"; then
  pass "nothing Ekos launched touches /opt/indi-stable -- the distribution's INDI is what Ekos is using"
else
  echo "  Ekos is using OUR build for:"; echo "$OURS"
  echo "  EXPECTED if Ekos's INDI drivers XML directory points at"
  echo "  /opt/indi-stable/share/indi -- our catalogue carries absolute paths, so"
  echo "  this is the opt-in working. UNEXPECTED if it still points at"
  echo "  /usr/share/indi, which would mean something is reaching our prefix"
  echo "  without being asked to. Check: kreadconfig6 --file kstarsrc --group indi --key indiDriversDir"
fi

echo
echo "############ STEP 3: CONTROL -- could this scanner see /opt at all? ############"
# STEP 2 passes by finding nothing, so prove the machinery can find something
# (LESSONS_LEARNED.md #1). Start OUR server with OUR driver, by absolute path,
# on a spare port, and confirm the same scan reports /opt for it.
if test -x /opt/indi-stable/bin/indiserver && test -x /opt/indi-stable/bin/indi_simulator_ccd; then
  # Keep the log. Sending this to /dev/null is what turned a one-line
  # "Address already in use" into a debugging detour (LESSONS_LEARNED.md #2 --
  # the artifact was available and had been thrown away).
  /opt/indi-stable/bin/indiserver -u "$USOCK" -p "$PORT" \
      /opt/indi-stable/bin/indi_simulator_ccd > "$CLOG" 2>&1 &
  SRV=$!
  # Kill by captured PID, never by pattern (LESSONS_LEARNED.md #9).
  trap 'kill "$SRV" 2>/dev/null' EXIT
  # Wait for the DRIVER, not just the server. indiserver links no libindi
  # library at all, so a control that only ever saw /opt/.../bin/indiserver
  # would not have shown that the scanner can spot our *libraries* being
  # mapped -- which is the thing STEP 2 is claiming did not happen.
  for _ in 1 2 3 4 5 6 7 8; do
    kill -0 "$SRV" 2>/dev/null || break
    CMAP=$(scan | grep '/opt/indi-stable' || true)
    grep -q '/opt/indi-stable/bin/indi_' <<< "$CMAP" && break
    sleep 1
  done
  if grep -q '/opt/indi-stable/bin/indi_' <<< "${CMAP:-}"; then
    ctl "the same scan sees our prefix when it is genuinely running:"
    while read -r pid exe; do report "$pid" "$exe"; done <<< "$CMAP"
  else
    fail "started our indiserver on port $PORT but the scanner never saw a driver under /opt -- STEP 2's PASS proves nothing"
    echo "  what the scan did see: ${CMAP:-(nothing)}"
    echo "  --- control server log ($CLOG) ---"; sed 's/^/  /' "$CLOG"
  fi
  kill "$SRV" 2>/dev/null
  wait "$SRV" 2>/dev/null
  trap - EXIT
  rm -f "$CLOG"
else
  fail "/opt/indi-stable/bin/indiserver or indi_simulator_ccd missing -- ours is not installed, so STEP 2 could not have found it either way and its PASS is vacuous"
fi

echo
echo "==================================================================="
test "$FAIL" -eq 0 && echo "OBSERVATION COMPLETE -- see STEP 2 for the verdict." \
                   || echo "FAILURES ABOVE."
echo "==================================================================="
exit "$FAIL"
