#!/bin/bash
#
# CI smoke test (Debian/Ubuntu side) -- the Debian twin of
# scripts/smoke-test-core.sh. Same gate, same reasoning: a fresh CI
# container, not a snapshotted VM, so no baseline/coexistence assertions
# here -- see that script's own header for the full explanation.
#
# Run as: bash scripts/smoke-test-core-deb.sh <deb-dir>
#
set -u

DEB_DIR=${1:?usage: smoke-test-core-deb.sh <deb-dir>}
# Canonicalize to an absolute path before it ever reaches apt-get.
# Confirmed by hand, 2026-08-27, on a real CI run: a relative "debs/..."
# path resolves correctly in this script's own variables (verified with
# an explicit dump) but apt-get itself then reports "Unable to locate
# package debs" -- consistent with apt falling back to its PACKAGE/RELEASE
# pin syntax (splitting on the first /) when it doesn't recognize the
# argument as a file, something ubuntuastro's own apt-get does not do
# with the identical relative path. Absolute paths are unambiguous
# regardless of the exact mechanism.
DEB_DIR=$(cd "$DEB_DIR" && pwd) || { echo "ERROR: $DEB_DIR is not a directory" >&2; exit 1; }

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

echo "############ STEP 1: install ############"
echo "  DEB_DIR contents:"
ls -la "$DEB_DIR" 2>&1 | sed 's/^/    /'
CORE_DEB=$(ls "$DEB_DIR"/indi-stable-core_*.deb 2>/dev/null | head -1)
LIBS_DEB=$(ls "$DEB_DIR"/indi-stable-core-libs_*.deb 2>/dev/null | head -1)
printf '  CORE_DEB=[%s]\n' "$CORE_DEB"
printf '  LIBS_DEB=[%s]\n' "$LIBS_DEB"
test -n "$CORE_DEB" || die "no indi-stable-core .deb in $DEB_DIR"
test -n "$LIBS_DEB" || die "no indi-stable-core-libs .deb in $DEB_DIR"
apt-get install -y "$CORE_DEB" "$LIBS_DEB" || die "install failed"
pass "installed $(basename "$CORE_DEB")"

echo "############ STEP 2: indiserver starts ############"
LINK=/usr/bin/indiserver-stable
test -x "$LINK" || die "$LINK missing after install -- update-alternatives registration failed"
VER_OUT=$("$LINK" --version 2>&1)
echo "$VER_OUT" | sed 's/^/    /'
echo "$VER_OUT" | grep -qiE 'indi library|code' \
  && pass "indiserver-stable reports a version" \
  || fail "indiserver-stable did not report a recognizable version string"

echo "############ STEP 3: a representative driver loads ############"
DRIVER=/opt/indi-stable/bin/indi_simulator_ccd
test -x "$DRIVER" || die "$DRIVER missing -- was it built?"
# --help, not EOF-stdin -- see scripts/smoke-test-core.sh's own comment for
# the real defect that caught (confirmed by hand on this exact script,
# 2026-08-27: EOF-stdin just prints "<name>: EOF" and exits, no banner).
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
