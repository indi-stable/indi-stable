#!/bin/bash
#
# Configuration B coexistence test -- do two indiservers with BYTE-IDENTICAL
# library SONAMEs each map their own libraries?
#
# DEBIAN.md, "The equivalent of the tests that mattered" #2, and the Debian
# analogue of scripts/test-snapshot-b-coexist.sh. Ground truth comes from
# /proc/<pid>/maps of a LIVE driver, not from ldd, which only predicts.
#
# WHY THIS ONLY RUNS ON CONFIGURATION B
#
# On a stock Debian or Ubuntu the archive still ships 1.9.9 with
# libindiclient.so.1, so our .so.2 cannot collide and this test passes because
# the situation cannot arise -- a check that cannot fail, not a check that
# passed (DEBIAN.md, "The neighbour is not one version"; LESSONS_LEARNED.md
# #12). STEP 1 therefore reads the SONAMEs out of the ELF files of both trees
# and ABORTS unless they are genuinely identical. It reads them from the files
# rather than trusting package names, because the PPA's package is called
# libindi1 while shipping .so.2 -- the name says nothing (LESSONS_LEARNED.md
# #11: discriminate on identity, not on a self-reported label).
#
# WHY THE DRIVER AND NOT THE SERVER
#
# indiserver links no INDI library at all -- only libev/libnova/libc -- so
# checking the server proves nothing about library separation. The DRIVERS are
# what link libindidriver/libindiclient.
#
# WHY BOTH SERVERS AT ONCE
#
# indiserver binds an abstract Unix socket whose name is machine-global and
# does NOT derive from -p, so a second server dies with "Local server: bind:
# Address already in use" whatever port it is given, unless it is passed its
# own -u (DESIGN.md, "One indiserver per machine unless -u says otherwise").
# Two sequential runs would leave "both at once" inferred rather than shown, so
# STEP 4 gives each server its own -u and reads both live processes.
#
# Run as: sudo bash scripts/test-config-b-coexist.sh [deb-dir]
#
# Standing rules: absolute paths, never ~ (LESSONS_LEARNED.md #4); assert the
# setup landed before measuring it (#5); restore by diffing (#6); captured
# PIDs, never `pkill -f`, which matches the calling shell's own argv (#9).
#
set -u

BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)
D=${1:-$HOMEDIR/build}
W=$(mktemp -d /tmp/config-b-coexist.XXXXXX)

OUR_SERVER=/usr/bin/indiserver-stable
OUR_DRIVER=/opt/indi-stable/bin/indi_simulator_ccd
OUR_LIBDIR=/opt/indi-stable/lib
DISTRO_SERVER=/usr/bin/indiserver
DISTRO_DRIVER=/usr/bin/indi_simulator_ccd
DISTRO_LIBDIR=/usr/lib/x86_64-linux-gnu

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; echo "  work dir kept: $W"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

snapshot() { dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort; }

# Every server started here is recorded so the teardown kills PIDs rather than
# matching a pattern (LESSONS_LEARNED.md #9).
PIDS=""
cleanup() {
  for p in $PIDS; do kill "$p" 2>/dev/null; done
  for p in $PIDS; do wait "$p" 2>/dev/null; done
}
trap cleanup EXIT

echo "############ STEP 0: preconditions ############"
test "$(id -u)" -eq 0 || die "run under sudo -- this installs and removes packages"

OUR_MAIN=$(ls "$D"/indi-stable-core_*_amd64.deb 2>/dev/null | head -1)
OUR_LIBS=$(ls "$D"/indi-stable-core-libs_*_amd64.deb 2>/dev/null | head -1)
test -f "$OUR_MAIN" || die "no indi-stable-core_*_amd64.deb under $D -- build first (DEBIAN.md)"
test -f "$OUR_LIBS" || die "no indi-stable-core-libs_*_amd64.deb under $D"
echo "  our .debs: $(basename "$OUR_MAIN"), $(basename "$OUR_LIBS")"

dpkg -s libindi1 >/dev/null 2>&1 || die "libindi1 is not installed -- this is not configuration B"
dpkg -s indi-bin >/dev/null 2>&1 || die "indi-bin is not installed -- it owns $DISTRO_SERVER and $DISTRO_DRIVER"
test -x "$DISTRO_SERVER" || die "$DISTRO_SERVER missing even though indi-bin is installed"
test -x "$DISTRO_DRIVER" || die "$DISTRO_DRIVER missing -- there is nothing to compare against"
dpkg -s indi-stable-core >/dev/null 2>&1 && die "ours is ALREADY installed -- this test must start from the distribution-only state"
test -e /opt/indi-stable && die "/opt/indi-stable exists before we installed anything -- clean it first"
pass "distribution INDI present, ours absent"

BASELINE=$W/baseline.txt
snapshot > "$BASELINE"
DISTRO_SHA=$(sha256sum "$DISTRO_SERVER" | awk '{print $1}')
info "baseline: $(wc -l < "$BASELINE") packages; $DISTRO_SERVER sha256 $DISTRO_SHA"

echo
echo "############ STEP 1: install ours, then prove the SONAMEs really collide ############"
apt-get install -y "$OUR_LIBS" "$OUR_MAIN" >"$W/install.log" 2>&1 \
  || { tail -20 "$W/install.log"; die "installing our packages failed"; }
dpkg -s indi-stable-core >/dev/null 2>&1 || die "indi-stable-core is not installed after the install"
test -x "$OUR_DRIVER" || die "$OUR_DRIVER missing after install"
readlink -e "$OUR_SERVER" >/dev/null || die "$OUR_SERVER does not resolve -- the alternative never registered"
pass "ours installed; $OUR_SERVER -> $(readlink -e "$OUR_SERVER")"

# The teeth of this test. Read from the ELF files of BOTH trees.
COLLIDE=0
for lib in libindidriver libindiclient libindiAlignmentDriver; do
  OS=$(readelf -d "$OUR_LIBDIR/$lib.so.2"    2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p')
  DS=$(readelf -d "$DISTRO_LIBDIR/$lib.so.2" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p')
  printf '  %-26s ours=%-22s distro=%s\n' "$lib" "${OS:-<absent>}" "${DS:-<absent>}"
  test -n "$OS" && test "$OS" = "$DS" && COLLIDE=$((COLLIDE + 1))
done
test "$COLLIDE" -ge 1 \
  || die "no SONAME is shared between the two trees -- this is configuration A, where our .so.2 cannot collide with the archive's .so.1 and every check below would pass because the situation cannot arise (DEBIAN.md, 'So test two configurations')"
pass "$COLLIDE SONAMEs are byte-identical across the two trees -- the collision is real and the test has teeth"

echo
echo "############ STEP 2: scripts/test-runtime-maps.sh, unchanged ############"
# STATUS.md claims this Fedora harness is package-manager-agnostic and should
# work here unchanged. That is a claim about a tool, so it gets run rather than
# recalled (LESSONS_LEARNED.md #10). It starts ONE server per invocation and
# kills it, so the two calls below are sequential and do not need -u.
HERE=$(cd "$(dirname "$0")" && pwd)
MAPS=$HERE/test-runtime-maps.sh
test -f "$MAPS" || die "$MAPS missing"
echo "  -- ours --"
bash "$MAPS" "$OUR_SERVER" "$OUR_DRIVER" 7625 2>&1 | sed 's/^/    /'
test "${PIPESTATUS[0]}" -eq 0 && pass "test-runtime-maps.sh runs unchanged against ours" \
                              || fail "test-runtime-maps.sh failed against ours"
echo "  -- the distribution's --"
bash "$MAPS" "$DISTRO_SERVER" "$DISTRO_DRIVER" 7626 2>&1 | sed 's/^/    /'
test "${PIPESTATUS[0]}" -eq 0 && pass "test-runtime-maps.sh runs unchanged against the distribution's" \
                              || fail "test-runtime-maps.sh failed against the distribution's"

echo
echo "############ STEP 3: BOTH SERVERS ALIVE AT ONCE ############"
# Distinct -u, or the second dies on the abstract socket whatever port it gets.
start_server() {   # $1 label, $2 server, $3 driver, $4 port, $5 socket, [$6 LD_LIBRARY_PATH]
  local label=$1 srv=$2 drv=$3 port=$4 sock=$5 ldp=${6:-}
  local log=$W/$label.log srvpid drvpid
  if test -n "$ldp"; then
    LD_LIBRARY_PATH=$ldp "$srv" -u "$sock" -p "$port" "$drv" >"$log" 2>&1 &
  else
    "$srv" -u "$sock" -p "$port" "$drv" >"$log" 2>&1 &
  fi
  srvpid=$!
  PIDS="$PIDS $srvpid"
  sleep 4
  if ! kill -0 "$srvpid" 2>/dev/null; then
    echo "  *** $label: server died -- log follows ***"; sed 's/^/      /' "$log"
    echo ""; return
  fi
  drvpid=$(pgrep -P "$srvpid" | head -1)
  if test -z "$drvpid"; then
    echo "  *** $label: no driver child spawned -- log follows ***"; sed 's/^/      /' "$log"
    echo ""; return
  fi
  echo "$drvpid"
}

OUR_DRV=$(start_server ours    "$OUR_SERVER"    "$OUR_DRIVER"    7625 /tmp/indiserver-ours)
DIS_DRV=$(start_server distro  "$DISTRO_SERVER" "$DISTRO_DRIVER" 7626 /tmp/indiserver-distro)
test -n "$OUR_DRV" || die "our driver never started -- nothing to measure"
test -n "$DIS_DRV" || die "the distribution's driver never started -- the comparison would be one-sided"
info "our driver pid $OUR_DRV, distribution driver pid $DIS_DRV -- both live simultaneously"

maps_of() { grep -oE '/[^ ]*libindi[^ ]*' /proc/"$1"/maps | sort -u; }

echo "  INDI libraries mapped by OUR live driver:"
maps_of "$OUR_DRV" | sed 's/^/      /'
echo "  INDI libraries mapped by the DISTRIBUTION's live driver:"
maps_of "$DIS_DRV" | sed 's/^/      /'

OUR_MAPPED=$(maps_of "$OUR_DRV")
DIS_MAPPED=$(maps_of "$DIS_DRV")
test -n "$OUR_MAPPED" || die "our driver mapped NO libindi library at all -- the grep found nothing, so nothing below can be concluded"
test -n "$DIS_MAPPED" || die "the distribution's driver mapped NO libindi library at all"

echo "$OUR_MAPPED" | grep -q "^$OUR_LIBDIR/" \
  && pass "our driver maps out of $OUR_LIBDIR" \
  || fail "our driver maps nothing from $OUR_LIBDIR"
echo "$OUR_MAPPED" | grep -q "^$DISTRO_LIBDIR/" \
  && fail "our driver ALSO maps the distribution's libraries from $DISTRO_LIBDIR -- the private prefix is not separating them" \
  || pass "our driver maps NOTHING from $DISTRO_LIBDIR"
echo "$DIS_MAPPED" | grep -q "^$DISTRO_LIBDIR/" \
  && pass "the distribution's driver maps out of $DISTRO_LIBDIR" \
  || fail "the distribution's driver does not map from $DISTRO_LIBDIR"
echo "$DIS_MAPPED" | grep -q "^$OUR_LIBDIR/" \
  && fail "the distribution's driver maps OUR libraries -- we have shadowed it, which is the one thing this project must never do" \
  || pass "the distribution's driver maps NOTHING from $OUR_LIBDIR"

cleanup; PIDS=""

echo
echo "############ STEP 4: CONTROL -- can the maps reading detect the wrong answer? ############"
# Every assertion above passes by NOT finding the other tree's path, so the
# reading has to be shown able to find it (LESSONS_LEARNED.md #1). Our drivers
# carry DT_RUNPATH, not DT_RPATH -- CMake's --enable-new-dtags default -- and
# LD_LIBRARY_PATH takes precedence over RUNPATH. Forcing it therefore makes our
# own driver map the distribution's libraries, which is exactly the failure
# STEP 3 is looking for (DESIGN.md, "The measurement was shown able to fail").
TAG=$(readelf -d "$OUR_DRIVER" | grep -oE 'RPATH|RUNPATH' | head -1)
info "our driver's dynamic tag: DT_${TAG:-<none>}"
CTL_DRV=$(start_server control "$OUR_SERVER" "$OUR_DRIVER" 7627 /tmp/indiserver-ctl "$DISTRO_LIBDIR")
if test -n "$CTL_DRV"; then
  echo "  our driver, forced with LD_LIBRARY_PATH=$DISTRO_LIBDIR:"
  maps_of "$CTL_DRV" | sed 's/^/      /'
  if maps_of "$CTL_DRV" | grep -q "^$DISTRO_LIBDIR/"; then
    ctl "forcing LD_LIBRARY_PATH makes our driver map the DISTRIBUTION's libraries -- so STEP 3's 'nothing from $DISTRO_LIBDIR' was a real result, not a reading that cannot see the other tree"
    info "DT_RUNPATH is overridden by LD_LIBRARY_PATH. The guarantee holds against the default search order and ldconfig, not against a user who exports LD_LIBRARY_PATH -- DESIGN.md says the same, and that is an explicit opt-out rather than a defect."
  else
    fail "CONTROL: even with LD_LIBRARY_PATH=$DISTRO_LIBDIR our driver did not map a single distribution library. Either the reading cannot see that path, or DT_$TAG is not what it appears -- either way STEP 3 proves less than it claims"
  fi
else
  fail "CONTROL: the forced server never produced a driver -- STEP 3 keeps no positive control"
fi
cleanup; PIDS=""

echo
echo "############ STEP 5: the distribution is still a bystander ############"
test "$(sha256sum "$DISTRO_SERVER" | awk '{print $1}')" = "$DISTRO_SHA" \
  && pass "$DISTRO_SERVER is byte-identical to before ($DISTRO_SHA)" \
  || fail "$DISTRO_SERVER CHANGED"
for p in indi-bin libindi1 libindi-data libindi-dev; do
  if dpkg -V "$p" >/dev/null 2>&1; then pass "dpkg -V $p clean"
  else fail "dpkg -V $p reports modifications:"; dpkg -V "$p" | sed 's/^/        /'; fi
done

echo
echo "############ STEP 6: restore, by diffing rather than by naming ############"
TO_REMOVE=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
              indi-stable-core indi-stable-core-libs indi-stable-core-dev 2>/dev/null \
            | awk '$1 ~ /^i/ {print $2}')
info "removing what is actually installed: ${TO_REMOVE:-(nothing)}"
test -n "$TO_REMOVE" && apt-get remove -y --no-autoremove $TO_REMOVE >"$W/teardown.log" 2>&1

snapshot > "$W/after.txt"
ADDED=$(LC_ALL=C comm -13 "$BASELINE" "$W/after.txt")
GONE=$(LC_ALL=C comm -23 "$BASELINE" "$W/after.txt")
if test -n "$ADDED"; then
  echo "  packages this run ADDED and has not removed:"; echo "$ADDED" | sed 's/^/        /'
  apt-get remove -y --no-autoremove $(echo "$ADDED" | cut -f1) >>"$W/teardown.log" 2>&1
fi
if test -n "$GONE"; then
  echo "  packages this run REMOVED and has not restored:"; echo "$GONE" | sed 's/^/        /'
  apt-get install -y $(echo "$GONE" | cut -f1) >>"$W/teardown.log" 2>&1
fi

{ printf 'zzz-not-a-real-package\t9.9\n'; cat "$BASELINE"; } | LC_ALL=C sort > "$W/perturbed.txt"
SEEN=$(LC_ALL=C comm -13 "$BASELINE" "$W/perturbed.txt" | cut -f1)
test "$SEEN" = "zzz-not-a-real-package" \
  && ctl "the added/removed comparison reports a planted difference, so its silence above is a real result" \
  || fail "CONTROL BROKEN: the comparison did not report a planted package (got '${SEEN:-nothing}')"

snapshot > "$W/final.txt"
if diff -q "$BASELINE" "$W/final.txt" >/dev/null; then
  pass "the package set matches the baseline exactly ($(wc -l < "$W/final.txt") packages)"
else
  fail "the box does NOT match its baseline -- differences follow"
  diff "$BASELINE" "$W/final.txt" | sed 's/^/        /'
fi
test -e /opt/indi-stable && fail "/opt/indi-stable survived the teardown" \
                         || pass "/opt/indi-stable is gone"
readlink -e "$OUR_SERVER" >/dev/null 2>&1 \
  && fail "$OUR_SERVER still resolves after teardown" \
  || pass "no indiserver-stable alternative left behind"

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "CONFIGURATION B COEXISTENCE: ALL CHECKS PASSED"
else
  echo "CONFIGURATION B COEXISTENCE: ONE OR MORE CHECKS FAILED"
fi
echo "  logs: $W"
echo "==================================================================="
exit "$FAIL"
