#!/bin/bash
#
# Compile, link and RUN a third-party consumer against the -dev package, on a
# box that also carries the distribution's libindi-dev.
#
# DEBIAN.md/STATUS.md name this as the fourth check to port: it is the one that
# found the two real libindi.pc defects in the first place, after Fedora's
# pkg-config-resolution stand-in had passed straight over them
# (LESSONS_LEARNED.md #15).
#
# WHY THIS RUNS ON THE HOST AND scripts/test-devel-compile-mock.sh DOES NOT
#
# The Fedora version runs inside a mock chroot, and STATUS.md reasoned by
# analogy that sbuild or pbuilder should take mock's place here. It should not,
# and the reason is worth stating because the analogy is very nearly right.
#
# mock is not there to provide a compiler. It is there because the Fedora VM's
# whole value is that it HAS no compiler and no build dependencies -- that
# absence is what makes "the distribution package is untouched" mean anything
# on that box, and running `dnf builddep` would spend the snapshot
# (STATUS.md, machine state). The chroot borrows a toolchain without spending
# it.
#
# ubuntuastro has no such property to protect. It builds the DEBs directly on
# the host, so it already carries gcc, libindi-dev and the rest of the
# build-dep set, and STATUS.md says so plainly. A debootstrap chroot here would
# be reproducing a condition the host already satisfies -- ceremony inherited
# from the other packaging rather than a requirement of this one, which is
# LESSONS_LEARNED.md #12 read in the direction people forget: a RATIONALE that
# holds for one implementation is not automatically the rationale for the
# other.
#
# What the chroot did give Fedora and is worth keeping is the guarantee that
# the run did not quietly change the box. STEP 4 asserts that directly instead:
# the package set is compared against a baseline taken before anything was
# installed, and the comparison is shown able to detect a planted difference.
#
# The measuring half lives in scripts/probe-devel-compile-deb.sh, separate so
# that a chroot driver can be added later and reuse it unchanged.
#
# Run as: sudo bash scripts/test-devel-compile-deb.sh [deb-dir]
#
set -u

BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)
D=${1:-$HOMEDIR/build}
W=$(mktemp -d /tmp/devel-compile-deb.XXXXXX)

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; echo "  work dir kept: $W"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

snapshot() { dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort; }

echo "############ STEP 0: preconditions ############"
test "$(id -u)" -eq 0 || die "run under sudo -- this installs and removes packages"

OUR_MAIN=$(ls "$D"/indi-stable-core_*_amd64.deb 2>/dev/null | head -1)
OUR_LIBS=$(ls "$D"/indi-stable-core-libs_*_amd64.deb 2>/dev/null | head -1)
OUR_DEV=$(ls  "$D"/indi-stable-core-dev_*_amd64.deb  2>/dev/null | head -1)
for f in "$OUR_MAIN" "$OUR_LIBS" "$OUR_DEV"; do
  test -f "$f" || die "missing one of our .debs under $D -- build first (DEBIAN.md)"
done
echo "  our .debs:"
for f in "$OUR_MAIN" "$OUR_LIBS" "$OUR_DEV"; do echo "    $(basename "$f")"; done

# The .pc fixes live in override_dh_auto_install, so a .deb built before them
# would test the old behaviour and read as the fix failing. Check the payload,
# not the filename date -- the 2.2.4.2-2 debs on this box before 2026-08-25
# were exactly that trap: a higher revision carrying older content.
dpkg-deb --fsys-tarfile "$OUR_DEV" \
  | tar -xO ./opt/indi-stable/lib/pkgconfig/libindi.pc 2>/dev/null > "$W/pc-in-deb" || true
test -s "$W/pc-in-deb" || die "could not read libindi.pc out of $(basename "$OUR_DEV")"
grep -qF -- '-Wl,-rpath,${libdir}' "$W/pc-in-deb" \
  || die "$(basename "$OUR_DEV") PREDATES the libindi.pc RPATH fix -- rebuild before testing it (DEBIAN.md, Building)"
pass "the -dev .deb's libindi.pc carries the fixes"

# Both trees have to be present or every measurement is vacuous. The
# distribution's -dev package is the one that owns /usr/include/libindi, which
# is the tree our headers must not be shadowed by.
dpkg -s libindi-dev >/dev/null 2>&1 \
  || die "libindi-dev is NOT installed -- without the distribution's headers at /usr/include/libindi there is nothing for ours to be confused with, and this test would pass because the collision cannot arise"
dpkg -s indi-stable-core >/dev/null 2>&1 && die "ours is ALREADY installed -- start from the distribution-only state"
test -e /opt/indi-stable && die "/opt/indi-stable exists before we installed anything"
command -v g++ >/dev/null 2>&1 || die "no g++ on this host -- see this file's header for why the compile is expected to happen here"
pass "distribution libindi-dev present, ours absent, compiler available"

BASELINE=$W/baseline.txt
snapshot > "$BASELINE"
info "baseline: $(wc -l < "$BASELINE") packages recorded"

echo
echo "############ STEP 1: install all three of ours ############"
# One transaction, so dpkg's file-conflict detection runs across the whole set
# against everything already installed -- the strongest form of the collision
# question.
apt-get install -y "$OUR_LIBS" "$OUR_MAIN" "$OUR_DEV" >"$W/install.log" 2>&1 \
  || { tail -30 "$W/install.log"; die "installing our packages failed -- if dpkg reported file conflicts with libindi-dev, THAT is the finding"; }
for p in indi-stable-core indi-stable-core-libs indi-stable-core-dev; do
  dpkg -s "$p" >/dev/null 2>&1 || die "$p is not installed after the install"
done
pass "all three installed alongside the distribution's libindi-dev, no file conflicts"

echo
echo "############ STEPS 1b-8: the probe ############"
HERE=$(cd "$(dirname "$0")" && pwd)
PROBE=$HERE/probe-devel-compile-deb.sh
test -f "$PROBE" || die "$PROBE missing -- it is the measuring half of this test"
PROBE_WORK=$W/probe bash "$PROBE" 2>&1 | tee "$W/probe.out"
PROBE_RC=${PIPESTATUS[0]}
test "$PROBE_RC" -eq 0 || FAIL=1

echo
echo "############ STEP 9: restore, by diffing rather than by naming ############"
TO_REMOVE=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
              indi-stable-core indi-stable-core-libs indi-stable-core-dev 2>/dev/null \
            | awk '$1 ~ /^i/ {print $2}')
info "removing what is actually installed: $(echo ${TO_REMOVE:-(nothing)} | tr '\n' ' ')"
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
  pass "the host package set matches the baseline exactly ($(wc -l < "$W/final.txt") packages) -- this run did not spend the box"
else
  fail "the host does NOT match its baseline -- differences follow"
  diff "$BASELINE" "$W/final.txt" | sed 's/^/        /'
fi
test -e /opt/indi-stable && fail "/opt/indi-stable survived the teardown" \
                         || pass "/opt/indi-stable is gone"
dpkg -V libindi-dev >/dev/null 2>&1 && pass "dpkg -V libindi-dev clean -- the distribution's headers were never touched" \
                                    || fail "dpkg -V libindi-dev reports modifications"

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "DEB -dev COMPILE: ALL CHECKS PASSED"
else
  echo "DEB -dev COMPILE: FAILURES ABOVE"
fi
echo "  logs: $W"
echo "==================================================================="
exit "$FAIL"
