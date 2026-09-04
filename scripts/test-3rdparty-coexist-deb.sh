#!/bin/bash
#
# Configuration B coexistence test for the Debian side of 3rdparty -- does
# indi-stable-3rdparty-libs + indi-stable-3rdparty-drivers, installed
# alongside indi-stable-core, actually keep the coexistence guarantee CLAUDE.md
# states, and is the collision it defends against real rather than assumed?
#
# This is the harness STATUS.md's "3rdparty -- remaining" section named as
# outstanding: core has four scripted Debian harnesses (DEBIAN.md, "The
# equivalent of the tests that mattered"); 3rdparty had its upgrade path
# scripted (scripts/test-upgrade-path-3rdparty-deb.sh,
# scripts/test-upgrade-path-drivers-deb.sh) but install/coexist/remove only
# by hand. This is the Debian analogue of scripts/test-config-b-coexist.sh
# (core), applied to a 3rdparty driver instead of the simulator.
#
# WHY THIS FINDS A REAL COLLISION WHERE FEDORA COULD NOT
#
# FEDORA.md and STATUS.md both record that Fedora ships no distribution
# indi-3rdparty package at all, so RPM coexistence could only be checked
# against distro CORE INDI, never against a real competing 3rdparty artifact.
# Ubuntu's *archive* (not the PPA) is different: `apt-cache show indi-apogee`
# resolves to a real package, `libapogee3t64` ships `libapogee.so.3` --
# BYTE-IDENTICAL SONAME to indi-stable-3rdparty-libs-apogee's own
# libapogee.so.3 (confirmed 2026-08-26 by extracting the actual archive .deb
# and reading its SONAME with readelf, not by trusting the package name --
# LESSONS_LEARNED.md #11). This is the genuine collision case DESIGN.md's
# private-prefix rationale predicts; unlike core's own config-B test, no
# forced empty-directory stand-in is needed, because Ubuntu's archive already
# ships the colliding artifact for real.
#
# WHY THE ARCHIVE PACKAGE IS DOWNLOADED, NEVER INSTALLED
#
# `apt-get install --dry-run indi-apogee` on this box (checked 2026-08-26)
# shows it would REMOVE indi-bin and libindi1 to satisfy indi-apogee's pin to
# libindidriver1 (>= 1.9.9+dfsg) -- the archive's own indi-3rdparty is
# incompatible with ppa:mutlaqja/ppa's newer libindi1, i.e. it is orphaned in
# the same shape README.md already documents for Fedora's indi-3rdparty
# packaging, just discovered from the opposite direction. Installing it would
# both destroy configuration B's own precondition and misrepresent what this
# project's packaging is being tested against. `apt-get download` plus
# `dpkg-deb -x` into a scratch directory gets the real artifact's bytes
# without ever touching dpkg/apt state -- it is not recorded in the baseline
# snapshot and needs no teardown.
#
# WHAT STEP 5's FORCED CONTROL PROVES THAT core's OWN CANNOT
#
# test-config-b-coexist.sh's STEP 4 control forces LD_LIBRARY_PATH at the
# DISTRIBUTION's OWN libdir, which already holds a real colliding library
# (distro core INDI is actually installed in configuration B). No 3rdparty
# vendor library is installed system-wide anywhere on this box -- the
# archive's indi-apogee cannot coexist with the PPA and so is never actually
# present -- so this script's control instead forces LD_LIBRARY_PATH at the
# scratch directory holding the extracted distro libapogee.so.3, proving the
# same RUNPATH-vs-LD_LIBRARY_PATH precedence mechanism has teeth against a
# real SONAME-colliding artifact even though that artifact is never installed.
#
# Run as:
#   sudo bash scripts/test-3rdparty-coexist-deb.sh [libs-dir] [drivers-dir] [core-dir]
#
# LIBS_VER/DRIVERS_VER/CORE_VER environment variables override the defaults,
# same convention as this project's other Debian test scripts. Needs network
# access for STEP 2's `apt-get download` -- there is no offline substitute,
# because the point is to read a real distro artifact rather than assume its
# shape (LESSONS_LEARNED.md #10).
#
# Standing rules: absolute paths, never ~ (LESSONS_LEARNED.md #4); assert the
# setup landed before measuring it (#5); restore by diffing (#6); captured
# PIDs, never `pkill -f` (#9); give any check that passes by finding nothing a
# positive control (#1).
#
set -u

BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)
LIBS_DIR=${1:-$HOMEDIR/build}
DRIVERS_DIR=${2:-$HOMEDIR/build}
CORE_DIR=${3:-$HOMEDIR/build}
LIBS_VER=${LIBS_VER:-2.2.4.1-1}
DRIVERS_VER=${DRIVERS_VER:-2.2.4.1-1}
CORE_VER=${CORE_VER:-2.2.4.2-1}
W=$(mktemp -d /tmp/3rdparty-coexist-deb.XXXXXX)

VENDORS="apogee asi fli playerone inovasdk micam sbig touptek"

OUR_SERVER=/usr/bin/indiserver-stable
OUR_DRIVER=/opt/indi-stable/bin/indi_apogee_ccd
OUR_LIBDIR=/opt/indi-stable/lib
DISTRO_SERVER=/usr/bin/indiserver
DISTRO_LIBDIR=/usr/lib/x86_64-linux-gnu

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; echo "  work dir kept: $W"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

snapshot() { dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort; }

libs_deb()    { echo "$LIBS_DIR/indi-stable-3rdparty-libs-$1_${LIBS_VER}_amd64.deb"; }
drivers_deb() { echo "$DRIVERS_DIR/indi-stable-3rdparty-drivers-$1_${DRIVERS_VER}_amd64.deb"; }
libs_debs()    { for v in $VENDORS; do libs_deb "$v"; libs_deb "$v-dev"; done; }
drivers_debs() { for v in $VENDORS; do drivers_deb "$v"; done; }
pkg_names() {
  for v in $VENDORS; do
    echo "indi-stable-3rdparty-libs-$v"; echo "indi-stable-3rdparty-libs-$v-dev"
    echo "indi-stable-3rdparty-drivers-$v"
  done
}

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

for f in $(libs_debs) $(drivers_debs) \
         "$CORE_DIR/indi-stable-core_${CORE_VER}_amd64.deb" \
         "$CORE_DIR/indi-stable-core-libs_${CORE_VER}_amd64.deb" \
         "$CORE_DIR/indi-stable-core-dev_${CORE_VER}_amd64.deb"; do
  test -f "$f" || die "missing $f -- build it first (DEBIAN.md)"
done

dpkg -s libindi1 >/dev/null 2>&1 || die "libindi1 is not installed -- this is not configuration B"
dpkg -s indi-bin >/dev/null 2>&1 || die "indi-bin is not installed -- it owns $DISTRO_SERVER"
test -x "$DISTRO_SERVER" || die "$DISTRO_SERVER missing even though indi-bin is installed"
dpkg -s indi-stable-core >/dev/null 2>&1 && die "ours is ALREADY installed -- start from the distribution-only state"
test -e /opt/indi-stable && die "/opt/indi-stable exists before we installed anything -- clean it first"
pass "distribution INDI present, ours absent"

BASELINE=$W/baseline.txt
snapshot > "$BASELINE"
DISTRO_SHA=$(sha256sum "$DISTRO_SERVER" | awk '{print $1}')
info "baseline: $(wc -l < "$BASELINE") packages; $DISTRO_SERVER sha256 $DISTRO_SHA"

echo
echo "############ STEP 1: install core + all 8 vendors' libs and drivers ############"
apt-get install -y \
  "$CORE_DIR/indi-stable-core_${CORE_VER}_amd64.deb" \
  "$CORE_DIR/indi-stable-core-libs_${CORE_VER}_amd64.deb" \
  "$CORE_DIR/indi-stable-core-dev_${CORE_VER}_amd64.deb" \
  $(libs_debs) $(drivers_debs) \
  >"$W/install.log" 2>&1 \
  || { tail -40 "$W/install.log"; die "installing our packages failed"; }
INSTALLED=$(dpkg-query -W -f='${Package}\n' $(pkg_names) 2>/dev/null | wc -l)
test "$INSTALLED" -eq 24 || die "expected 24 3rdparty packages installed, got $INSTALLED"
test -x "$OUR_DRIVER" || die "$OUR_DRIVER missing after install"
readlink -e "$OUR_SERVER" >/dev/null || die "$OUR_SERVER does not resolve -- the alternative never registered"
pass "24 3rdparty packages installed; $OUR_SERVER -> $(readlink -e "$OUR_SERVER")"

echo
echo "############ STEP 2: get a REAL colliding artifact from the archive, without installing it ############"
( cd "$W" && apt-get download libapogee3t64 >download.log 2>&1 )
DISTRO_APOGEE_DEB=$(ls "$W"/libapogee3t64_*.deb 2>/dev/null | head -1)
test -f "$DISTRO_APOGEE_DEB" \
  || { cat "$W/download.log"; die "apt-get download libapogee3t64 failed -- needs network access, see this script's header"; }
dpkg-deb -x "$DISTRO_APOGEE_DEB" "$W/distro-apogee" \
  || die "dpkg-deb -x on the downloaded archive package failed"
DISTRO_LIBAPOGEE=$(find "$W/distro-apogee" -name 'libapogee.so.3*' -type f | head -1)
test -f "$DISTRO_LIBAPOGEE" || die "the downloaded archive package does not contain libapogee.so.3 -- cannot prove a real collision"
dpkg -s libapogee3t64 >/dev/null 2>&1 && die "libapogee3t64 got INSTALLED somehow -- this step must only download, never install"
pass "real distro libapogee.so.3 extracted to $W/distro-apogee, never installed via dpkg"

OUR_SONAME=$(readelf -d "$OUR_LIBDIR/libapogee.so.3" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p')
DISTRO_SONAME=$(readelf -d "$DISTRO_LIBAPOGEE" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p')
info "ours: soname=$OUR_SONAME  archive's: soname=$DISTRO_SONAME"
test -n "$OUR_SONAME" && test "$OUR_SONAME" = "$DISTRO_SONAME" \
  || die "SONAMEs do not collide (ours='$OUR_SONAME' archive's='$DISTRO_SONAME') -- this is not the collision case and everything below would prove nothing"
OUR_SHA=$(sha256sum "$OUR_LIBDIR/libapogee.so.3" | awk '{print $1}')
DISTRO_SHA_LIB=$(sha256sum "$DISTRO_LIBAPOGEE" | awk '{print $1}')
test "$OUR_SHA" != "$DISTRO_SHA_LIB" \
  && pass "SONAMEs collide ($OUR_SONAME) but the two files are genuinely different builds (different sha256) -- a real, distinguishable collision, not the same file twice" \
  || fail "ours and the archive's libapogee.so.3 are byte-identical -- STEP 5/6 could not tell them apart even if the guarantee failed"

echo
echo "############ STEP 3: neither our own -dev headers nor any packaged file lands where CLAUDE.md forbids ############"
BAD=0
for p in $(pkg_names); do
  OFFENDING=$(dpkg -L "$p" 2>/dev/null | grep -E '^/usr/bin/|^/usr/include/')
  if test -n "$OFFENDING"; then
    fail "$p ships file(s) under a forbidden path:"; echo "$OFFENDING" | sed 's/^/        /'
    BAD=1
  fi
done
test "$BAD" -eq 0 && pass "none of the 24 3rdparty packages ship anything under /usr/bin or /usr/include"

echo
echo "############ STEP 4: distribution core INDI is a clean bystander after 3rdparty installs on top ############"
test "$(sha256sum "$DISTRO_SERVER" | awk '{print $1}')" = "$DISTRO_SHA" \
  && pass "$DISTRO_SERVER is byte-identical to before ($DISTRO_SHA)" \
  || fail "$DISTRO_SERVER CHANGED"
for p in indi-bin libindi1 libindi-data libindi-dev; do
  if dpkg -V "$p" >/dev/null 2>&1; then pass "dpkg -V $p clean"
  else fail "dpkg -V $p reports modifications:"; dpkg -V "$p" | sed 's/^/        /'; fi
done

echo
echo "############ STEP 5: our driver, run normally, maps ONLY our own private-prefix libraries ############"
start_server() {   # $1 label, $2 port, $3 socket, [$4 LD_LIBRARY_PATH]
  local label=$1 port=$2 sock=$3 ldp=${4:-}
  local log=$W/$label.log srvpid drvpid
  if test -n "$ldp"; then
    LD_LIBRARY_PATH=$ldp "$OUR_SERVER" -u "$sock" -p "$port" "$OUR_DRIVER" >"$log" 2>&1 &
  else
    "$OUR_SERVER" -u "$sock" -p "$port" "$OUR_DRIVER" >"$log" 2>&1 &
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
maps_of() { grep -oE '/[^ ]*libapogee[^ ]*' /proc/"$1"/maps | sort -u; }

NORMAL_DRV=$(start_server normal 7628 /tmp/indiserver-3rdparty-normal)
test -n "$NORMAL_DRV" || die "our driver never started under normal conditions -- nothing to measure"
NORMAL_MAPPED=$(maps_of "$NORMAL_DRV")
echo "  libapogee mapped by our live driver (unforced):"; echo "$NORMAL_MAPPED" | sed 's/^/      /'
test -n "$NORMAL_MAPPED" || die "our driver mapped NO libapogee at all -- the grep found nothing, so nothing here can be concluded"
echo "$NORMAL_MAPPED" | grep -q "^$OUR_LIBDIR/" \
  && pass "our driver maps libapogee out of $OUR_LIBDIR" \
  || fail "our driver does not map libapogee from $OUR_LIBDIR"
echo "$NORMAL_MAPPED" | grep -qv "^$OUR_LIBDIR/" \
  && fail "our driver mapped a libapogee copy from somewhere other than $OUR_LIBDIR" \
  || pass "no libapogee copy mapped from anywhere but $OUR_LIBDIR"
cleanup; PIDS=""

echo
echo "############ STEP 6: CONTROL -- forced at the REAL archive artifact, does precedence still make sense? ############"
# Same idiom as test-config-b-coexist.sh's own STEP 4, but forced at a real
# downloaded distro artifact (STEP 2) rather than the distribution's own live
# libdir, since no 3rdparty vendor library is ever actually installed
# system-wide on this box (STEP 2's header note explains why).
DISTRO_APOGEE_DIR=$(dirname "$DISTRO_LIBAPOGEE")
TAG=$(readelf -d "$OUR_DRIVER" | grep -oE 'RPATH|RUNPATH' | head -1)
info "our driver's dynamic tag: DT_${TAG:-<none>}"
CTL_DRV=$(start_server control 7629 /tmp/indiserver-3rdparty-ctl "$DISTRO_APOGEE_DIR")
if test -n "$CTL_DRV"; then
  echo "  our driver, forced with LD_LIBRARY_PATH=$DISTRO_APOGEE_DIR:"
  maps_of "$CTL_DRV" | sed 's/^/      /'
  if maps_of "$CTL_DRV" | grep -q "^$DISTRO_APOGEE_DIR/"; then
    ctl "forcing LD_LIBRARY_PATH at the REAL archive libapogee.so.3 makes our driver load THAT one -- so STEP 5's result was a real outcome of RUNPATH search order, not a reading that cannot see a colliding library"
    info "DT_RUNPATH is overridden by LD_LIBRARY_PATH, same finding as core's own harness. The guarantee holds against the default search order, not against a user who exports LD_LIBRARY_PATH -- an explicit opt-out, not a defect (DESIGN.md)."
  else
    fail "CONTROL: even with LD_LIBRARY_PATH=$DISTRO_APOGEE_DIR our driver did not map the archive's libapogee.so.3. Either the reading cannot see that path, or DT_$TAG is not what it appears -- either way STEP 5 proves less than it claims"
  fi
else
  fail "CONTROL: the forced server never produced a driver -- STEP 5 keeps no positive control"
fi
cleanup; PIDS=""

echo
echo "############ STEP 7: restore, by diffing rather than by naming ############"
TO_REMOVE=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
              indi-stable-core indi-stable-core-libs indi-stable-core-dev $(pkg_names) 2>/dev/null \
            | awk '$1 ~ /^i/ {print $2}')
info "removing what is actually installed: $(echo "$TO_REMOVE" | wc -w) packages"
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
  echo "3RDPARTY DEB CONFIGURATION B COEXISTENCE: ALL CHECKS PASSED"
else
  echo "3RDPARTY DEB CONFIGURATION B COEXISTENCE: ONE OR MORE CHECKS FAILED"
fi
echo "  logs: $W"
echo "==================================================================="
exit "$FAIL"
