#!/bin/bash
#
# Compile, link and RUN a third-party consumer against the -devel subpackage,
# inside a mock chroot that also carries the distribution's libindi-devel.
#
# Why a chroot and not the host: pkg-config RESOLUTION alone cannot see either
# of the two libindi.pc defects this test exists to check -- both were found on
# the DEB side only when something was actually compiled and run
# (LESSONS_LEARNED.md #15). scripts/test-devel-coexist.sh does the resolution
# half on the host and deliberately keeps the host free of a compiler, because
# "the distribution package is untouched" only means something on a box that
# was never given a toolchain (STATUS.md, machine state). A mock chroot has
# gcc already, so the compile costs the host nothing.
#
# Run as the build user (a member of the mock group), NOT as root:
#     bash scripts/test-devel-compile-mock.sh [resultdir]
#
# What it measures, mirroring the DEB run of 2026-08-25:
#   1. the Libs:/Cflags: lines of the INSTALLED libindi.pc -- the artifact, not
#      the %install log (LESSONS_LEARNED.md #2)
#   2. a consumer built with PKG_CONFIG_PATH=<ours> links, and RUNS, and
#      resolves libindiclient.so.2 to /opt/indi-stable
#   3. both include spellings -- <indiversion.h> and <libindi/indiversion.h> --
#      open OUR headers under PKG_CONFIG_PATH, and the DISTRIBUTION's without it
#   4. CONTROL: the same consumer built against a scratch .pc carrying
#      upstream's unfixed lines must behave differently. A check that passes by
#      finding nothing has to be shown able to find something
#      (LESSONS_LEARNED.md #1); here the "something" is the pre-fix defect.
#
# DATA_INSTALL_DIR is the probe that tells the two trees apart: ours says
# /opt/indi-stable/share/indi/, the distribution's /usr/share/indi/. Version
# strings cannot -- both are 2.2.4 (FEDORA.md, checklist item 6).
set -u

CFG=${MOCK_CFG:-fedora-44-x86_64}
R=${1:-$HOME/mock-result-pcfix}
W=$(mktemp -d /tmp/pcfix-compile.XXXXXX)

die() { echo; echo "*** ABORT: $* ***"; exit 1; }

echo "############ STEP 0: preconditions, on the HOST ############"
test "$(id -u)" -ne 0 || die "run as the build user, not root -- mock refuses to run as root"
id -nG | tr ' ' '\n' | grep -qx mock || die "$(id -un) is not in the mock group"

# Anchored on .x86_64.rpm: a mock resultdir keeps the .src.rpm beside the
# binaries (LESSONS_LEARNED.md #3).
OURS_DEVEL=$(ls "$R"/indi-stable-core-devel-2*.x86_64.rpm 2>/dev/null | head -1)
OURS_LIBS=$(ls "$R"/indi-stable-core-libs-2*.x86_64.rpm 2>/dev/null | grep -v debuginfo | head -1)
OURS_MAIN=$(ls "$R"/indi-stable-core-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource -e '\.src\.rpm' | head -1)
test -f "$OURS_DEVEL" || die "no indi-stable-core-devel-*.x86_64.rpm under $R"
test -f "$OURS_LIBS"  || die "no indi-stable-core-libs-*.x86_64.rpm under $R"
test -f "$OURS_MAIN"  || die "no indi-stable-core-*.x86_64.rpm under $R"
echo "  RPMs under $R:"
for f in "$OURS_MAIN" "$OURS_LIBS" "$OURS_DEVEL"; do echo "    $(basename "$f")"; done

# The .pc fixes live in %install, so an RPM built before them would test the
# old behaviour and read as the fix failing. Check the payload, not the date.
rpm2cpio "$OURS_DEVEL" | cpio -i --quiet --to-stdout './opt/indi-stable/lib/pkgconfig/libindi.pc' > "$W/pc-in-rpm" 2>/dev/null
test -s "$W/pc-in-rpm" || die "could not read libindi.pc out of $(basename "$OURS_DEVEL")"
grep -qF -- '-Wl,-rpath,${libdir}' "$W/pc-in-rpm" \
  || die "$(basename "$OURS_DEVEL") predates the libindi.pc RPATH fix -- rebuild through mock first (FEDORA.md)"
echo "  OK: the -devel RPM's libindi.pc carries the fixes."

HOST_GCC=no; command -v gcc >/dev/null 2>&1 && HOST_GCC=yes
HOST_PKGS=$(rpm -qa | wc -l)
echo "  host at start: gcc=$HOST_GCC, $HOST_PKGS packages, /opt/indi-stable $(test -e /opt/indi-stable && echo PRESENT || echo absent)"

echo
echo "############ STEP 1: build the chroot ############"
echo "  config: $CFG (host is Fedora $(rpm -E %fedora))"
sg mock -c "mock -r $CFG --init" >"$W/init.log" 2>&1 || { tail -20 "$W/init.log"; die "mock --init failed"; }
echo "  chroot initialised."

# One transaction, ours and the distribution's -devel together: rpm's file
# conflict detection runs across the whole transaction, so this is also the
# strongest form of the collision question.
sg mock -c "mock -r $CFG --install gcc-c++ pkgconf-pkg-config libindi libindi-libs libindi-devel '$OURS_MAIN' '$OURS_LIBS' '$OURS_DEVEL'" \
  >"$W/install.log" 2>&1 || { tail -30 "$W/install.log"; die "installing both -devel packages into the chroot failed -- if rpm reported file conflicts, THAT is the finding"; }
echo "  installed (in one transaction): gcc-c++, pkgconf, the distribution's libindi/-libs/-devel, and all three of ours."
# libindi-libs and libindi are named explicitly because -devel pulls neither on
# Fedora: the distribution splits libindi (indiserver and drivers), libindi-libs
# (the .so.2 set) and libindi-devel (headers and .pc). A chroot with only
# -devel has no distribution libindiclient.so.2 at all -- which is the very
# library the pre-fix control has to be able to find.

echo
echo "############ STEPS 2-7: inside the chroot ############"
HERE=$(cd "$(dirname "$0")" && pwd)
PROBE=$HERE/inchroot-devel-compile.sh
test -f "$PROBE" || die "$PROBE missing -- it is the in-chroot half of this test"
sg mock -c "mock -r $CFG --copyin '$PROBE' /root/probe.sh" >>"$W/install.log" 2>&1 \
  || die "could not copy the probe into the chroot"
sg mock -c "mock -r $CFG --chroot -- bash /root/probe.sh" 2>&1 | tee "$W/probe.out"
PROBE_RC=${PIPESTATUS[0]}

echo
echo "############ STEP 8: did this run spend the HOST's snapshot? ############"
# The Fedora VM's value is that it has no compiler and no build dependencies;
# a test that quietly installed one would invalidate every later "the
# distribution package is untouched" result taken on this box (STATUS.md).
NOW_GCC=no; command -v gcc >/dev/null 2>&1 && NOW_GCC=yes
NOW_PKGS=$(rpm -qa | wc -l)
test "$NOW_GCC" = "$HOST_GCC" \
  && echo "  PASS: host gcc present: $NOW_GCC (unchanged)" \
  || { echo "  *** FAIL: host gcc went $HOST_GCC -> $NOW_GCC ***"; PROBE_RC=1; }
test "$NOW_PKGS" -eq "$HOST_PKGS" \
  && echo "  PASS: host package count unchanged ($NOW_PKGS)" \
  || { echo "  *** FAIL: host package count $HOST_PKGS -> $NOW_PKGS ***"; PROBE_RC=1; }
test -e /opt/indi-stable \
  && { echo "  *** FAIL: /opt/indi-stable exists on the HOST -- nothing here should have installed it ***"; PROBE_RC=1; } \
  || echo "  PASS: /opt/indi-stable still absent on the host"

echo
echo "############ STEP 9: clean the chroot ############"
# The shared package caches survive; only the installed root goes, so the next
# mock build still starts warm.
sg mock -c "mock -r $CFG --clean" >>"$W/init.log" 2>&1 && echo "  chroot cleaned." || echo "  (mock --clean failed; see $W/init.log)"

echo
echo "==================================================================="
if test "$PROBE_RC" -eq 0; then
  echo "ALL CHECKS PASSED -- host untouched, chroot removed."
else
  echo "FAILURES ABOVE (in-chroot exit $PROBE_RC)."
fi
echo "  logs: $W"
echo "==================================================================="
exit "$PROBE_RC"
