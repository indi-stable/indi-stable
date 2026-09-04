#!/bin/bash
#
# CI smoke test (RPM/Fedora side) -- the actual gate DESIGN.md's versioning
# policy describes: clean install into a fresh container, indiserver
# starts, a representative driver loads. Distinct from
# scripts/test-config-b-coexist.sh and friends, which assert against a
# specific, deliberately non-fresh VM baseline (config B, a known package
# count) -- this script assumes NOTHING pre-exists, because
# .github/workflows/core-release.yml only ever runs it inside a
# just-started container. No coexistence check here on purpose: a bare
# CI container carries no distro INDI to coexist against in the first
# place, so that question belongs to the manual VM harnesses, not this one.
#
# Run as: bash scripts/smoke-test-core.sh <rpm-dir>
#
set -u

RPM_DIR=${1:?usage: smoke-test-core.sh <rpm-dir>}
# Canonicalize to an absolute path before it reaches dnf -- same defensive
# fix as smoke-test-core-deb.sh, which needed it for real against apt-get;
# dnf hasn't shown the equivalent problem, but there's no reason to trust
# a relative path across this boundary either.
RPM_DIR=$(cd "$RPM_DIR" && pwd) || { echo "ERROR: $RPM_DIR is not a directory" >&2; exit 1; }

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

echo "############ STEP 1: install ############"
CORE_RPM=$(ls "$RPM_DIR"/indi-stable-core-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource)
LIBS_RPM=$(ls "$RPM_DIR"/indi-stable-core-libs-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource)
test -n "$CORE_RPM" || die "no indi-stable-core RPM in $RPM_DIR"
test -n "$LIBS_RPM" || die "no indi-stable-core-libs RPM in $RPM_DIR"
dnf install -y "$CORE_RPM" "$LIBS_RPM" || die "install failed"
pass "installed $(basename "$CORE_RPM")"

echo "############ STEP 2: indiserver starts ############"
LINK=/usr/bin/indiserver-stable
test -x "$LINK" || die "$LINK missing after install -- alternatives registration failed"
VER_OUT=$("$LINK" --version 2>&1)
echo "$VER_OUT" | sed 's/^/    /'
echo "$VER_OUT" | grep -qiE 'indi library|code' \
  && pass "indiserver-stable reports a version" \
  || fail "indiserver-stable did not report a recognizable version string"

echo "############ STEP 3: a representative driver loads ############"
DRIVER=/opt/indi-stable/bin/indi_simulator_ccd
test -x "$DRIVER" || die "$DRIVER missing -- was it built?"
# --help is the reliable check here, confirmed by hand 2026-08-27: run with
# no args and stdin closed (</dev/null), an INDI driver just prints
# "<name>: EOF" and exits -- no usage banner at all, a real defect this
# script had until that was actually run and read rather than assumed from
# how a DIFFERENT driver (indi_fishcamp_ccd, checked with --help earlier
# the same day) had behaved. --help is what every INDI driver answers
# the same, reliable way, and is the same "did it actually load and run,
# not merely exist as a file" signal core's own manual testing uses
# (FEDORA.md, DEBIAN.md), not a full server-and-client round trip.
DRIVER_OUT=$(timeout 5 "$DRIVER" --help 2>&1)
echo "$DRIVER_OUT" | sed 's/^/    /'
echo "$DRIVER_OUT" | grep -qi "^Usage:" \
  && pass "indi_simulator_ccd --help prints its usage banner" \
  || fail "indi_simulator_ccd --help did not print a usage banner"

echo
if [ $FAIL -eq 0 ]; then
  echo "############ SMOKE TEST: ALL CHECKS PASSED ############"
else
  echo "############ SMOKE TEST: ONE OR MORE CHECKS FAILED ############"
fi
exit $FAIL
