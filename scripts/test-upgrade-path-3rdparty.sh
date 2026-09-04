#!/bin/bash
#
# Upgrade-path test for indi-stable-3rdparty-libs -- a different risk class
# than core's own upgrade test (scripts/test-upgrade-path.sh).
#
# Why this needs its own test, and why it looks different from core's:
# indi-stable-3rdparty-libs has NO scriptlets at all -- no %post/%postun, no
# alternatives, no ldconfig (confirmed by reading the spec; RPATH-based
# libraries are deliberately absent from ld.so.conf, same as core). So core's
# %postun ordering bug class does not exist here. What DOES exist, and had
# never been exercised until this test: upgrading ONE of two independent
# source packages that share /opt/indi-stable while the OTHER
# (indi-stable-core) stays installed and untouched. Fresh install + full
# COMBINED removal (STATUS.md, 2026-08-26) does not exercise this -- that
# test erases every package in one transaction; an upgrade instead replaces
# files package-by-package while core's own %dir ownership entries
# (LESSONS_LEARNED.md #20) sit there the whole time, untouched by the
# transaction that's actually running.
#
# The other real risk for a library-only package with no scriptlets is file
# replacement correctness across a SONAME-style change: indi-3rdparty's own
# tags WILL eventually bump some vendor's SONAME (this package's Version:
# tracks indi-3rdparty's own tags -- see the spec header), and an old file
# left behind by an incomplete upgrade is a silent orphan, not a loud error.
# STEP 4 below tests for exactly that, with a real control (LESSONS_LEARNED
# #1): a check that passes by finding nothing must be shown able to find
# something.
#
# Run as:
#   sudo bash scripts/test-upgrade-path-3rdparty.sh <old-rpm-dir> <new-rpm-dir> [core-rpm-dir]
#
# core-rpm-dir defaults to ~/mock-result-pcfix (STATUS.md, machine state).
#
# Standing rules for root-run tests (LESSONS_LEARNED.md #4, #5): absolute
# paths; assert the setup landed before measuring it.
#
set -u

OLD_DIR=${1:?usage: test-upgrade-path-3rdparty.sh <old-rpm-dir> <new-rpm-dir> [core-rpm-dir]}
NEW_DIR=${2:?usage: test-upgrade-path-3rdparty.sh <old-rpm-dir> <new-rpm-dir> [core-rpm-dir]}
CORE_DIR=${3:-$HOME/mock-result-pcfix}

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

# Anchored to *.x86_64.rpm and excluding debuginfo/debugsource throughout --
# a resultdir holds the .src.rpm too (LESSONS_LEARNED.md #3), and installing
# THAT installs its BuildRequires as Requires (LESSONS_LEARNED.md #21).
old_rpms() { ls "$OLD_DIR"/indi-stable-3rdparty-libs-*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource; }
new_rpms() { ls "$NEW_DIR"/indi-stable-3rdparty-libs-*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource; }
core_rpms() {
  ls "$CORE_DIR"/indi-stable-core-2*.x86_64.rpm "$CORE_DIR"/indi-stable-core-libs-2*.x86_64.rpm \
     "$CORE_DIR"/indi-stable-core-devel-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource
}

echo "############ STEP 0: two genuinely different builds ############"
test -n "$(old_rpms)" || die "no RPMs in $OLD_DIR"
test -n "$(new_rpms)" || die "no RPMs in $NEW_DIR"
test -n "$(core_rpms)" || die "no core RPMs in $CORE_DIR -- build indi-stable-core first (FEDORA.md)"
OLD_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(old_rpms | grep -- '-apogee-2' | grep -v devel) 2>/dev/null | head -1)
NEW_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(new_rpms | grep -- '-apogee-2' | grep -v devel) 2>/dev/null | head -1)
echo "  old: $OLD_NVR"
echo "  new: $NEW_NVR"
[ -n "$OLD_NVR" ] && [ -n "$NEW_NVR" ] || die "could not read an apogee NVR from one of the two directories"
[ "$OLD_NVR" != "$NEW_NVR" ] \
  || die "both directories hold the SAME NVR -- an 'upgrade' to an identical package is a reinstall, not an upgrade"

echo "############ STEP 0b: start from a clean slate ############"
rpm -qa | grep -q '^indi-stable-' && {
  dnf remove -y $(rpm -qa | grep '^indi-stable-') 2>/dev/null
}
rpm -qa | grep -q '^indi-stable-' && die "could not remove pre-existing indi-stable packages"
test -e /opt/indi-stable && die "/opt/indi-stable survived removal -- stale state, clean it before testing"
pass "no indi-stable installed, /opt/indi-stable absent"

DISTRO_PRE=""
if [ -e /usr/bin/indiserver ]; then
  DISTRO_PRE=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
  echo "  distro /usr/bin/indiserver sha256: $DISTRO_PRE"
fi

echo "############ STEP 1: install core + the OLD 3rdparty-libs build ############"
dnf install -y $(core_rpms) $(old_rpms) || die "installing core + old 3rdparty-libs failed"
CORE_NVR_PRE=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-core indi-stable-core-libs indi-stable-core-devel 2>&1)
INSTALLED_OLD=$(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' | grep '^indi-stable-3rdparty-libs' | sort)
echo "  core installed:"; echo "$CORE_NVR_PRE" | sed 's/^/    /'
echo "  3rdparty installed:"; echo "$INSTALLED_OLD" | sed 's/^/    /'
test -n "$INSTALLED_OLD" || die "no indi-stable-3rdparty-libs packages installed after STEP 1"

echo "############ STEP 2: THE UPGRADE -- 3rdparty-libs only, core untouched ############"
echo "  (core is not part of this dnf transaction at all)"
dnf install -y $(new_rpms) || die "the upgrade transaction itself failed"

echo "############ STEP 3: did the upgrade actually happen, and did core survive? ############"
INSTALLED_NEW=$(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' | grep '^indi-stable-3rdparty-libs' | sort)
echo "  now installed:"; echo "$INSTALLED_NEW" | sed 's/^/    /'
[ "$INSTALLED_NEW" != "$INSTALLED_OLD" ] \
  && pass "the installed NVRs changed, so an upgrade really occurred" \
  || fail "still the OLD NVRs -- nothing was upgraded and later steps would prove nothing"
DUPES=$(rpm -qa --qf '%{NAME}\n' | grep '^indi-stable-3rdparty-libs' | sort | uniq -d)
[ -z "$DUPES" ] \
  && pass "exactly one copy of each 3rdparty subpackage installed" \
  || fail "more than one copy installed of: $DUPES"
CORE_NVR_POST=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-core indi-stable-core-libs indi-stable-core-devel 2>&1)
[ "$CORE_NVR_POST" = "$CORE_NVR_PRE" ] \
  && pass "indi-stable-core/-libs/-devel NVRs unchanged -- the sibling source package was not touched" \
  || fail "core's own NVRs changed across a 3rdparty-only upgrade: $CORE_NVR_PRE -> $CORE_NVR_POST"
rpm -V indi-stable-core indi-stable-core-libs indi-stable-core-devel >/tmp/core-verify.$$ 2>&1
if [ -s /tmp/core-verify.$$ ]; then
  fail "rpm -V reports core packages modified by the 3rdparty upgrade:"
  sed 's/^/    /' /tmp/core-verify.$$
else
  pass "rpm -V clean on core's own packages after the 3rdparty upgrade"
fi
rm -f /tmp/core-verify.$$

echo "############ STEP 4: no orphaned files left under /opt/indi-stable ############"
# The real risk for a scriptlet-free library package: a SONAME bump between
# builds leaves the OLD .so behind if file replacement is ever incomplete.
# Every file physically present must be owned by a currently-installed
# package -- anything else is a silent leftover, not a loud error.
orphans() {
  find /opt/indi-stable -type f 2>/dev/null | while read -r f; do
    rpm -qf "$f" >/dev/null 2>&1 || echo "$f"
  done
}
ORPHANS=$(orphans)
if [ -z "$ORPHANS" ]; then
  pass "no orphaned files under /opt/indi-stable after the upgrade"
else
  fail "orphaned file(s) found after the upgrade:"
  echo "$ORPHANS" | sed 's/^/    /'
fi

echo "############ STEP 4 CONTROL: can the orphan check find something? ############"
# LESSONS_LEARNED.md #1: a check that passes by finding nothing must be shown
# able to find something.
CANARY=/opt/indi-stable/lib/orphan-canary-$$
touch "$CANARY" 2>/dev/null || die "could not create the canary file -- STEP 4's control cannot run"
CONTROL_ORPHANS=$(orphans)
rm -f "$CANARY"
case "$CONTROL_ORPHANS" in
  *"$CANARY"*) pass "CONTROL: the orphan check correctly flagged a planted stray file" ;;
  *) fail "CONTROL: the orphan check did NOT flag a planted stray file at $CANARY -- STEP 4 cannot be trusted" ;;
esac

echo "############ STEP 5: the upgraded libraries actually work ############"
APOGEE_SO=$(ls /opt/indi-stable/lib/libapogee.so.* 2>/dev/null | head -1)
FLI_SO=$(ls /opt/indi-stable/lib/libfli.so.* 2>/dev/null | head -1)
for so in "$APOGEE_SO" "$FLI_SO"; do
  test -n "$so" || { fail "expected library missing after upgrade"; continue; }
  RUNPATH=$(readelf -d "$so" 2>/dev/null | grep -c "RUNPATH.*opt/indi-stable/lib")
  [ "$RUNPATH" -ge 1 ] \
    && pass "$(basename "$so"): RUNPATH into the private prefix survived the upgrade" \
    || fail "$(basename "$so"): RUNPATH missing or wrong after upgrade"
  ldd "$so" 2>&1 | grep -qi "not found" \
    && fail "$(basename "$so"): ldd reports an unresolved dependency after upgrade" \
    || pass "$(basename "$so"): all dependencies resolve"
done

echo "############ STEP 6: the distro binary is still a bystander ############"
if [ -n "$DISTRO_PRE" ]; then
  DISTRO_POST=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
  [ "$DISTRO_PRE" = "$DISTRO_POST" ] \
    && pass "/usr/bin/indiserver unchanged across the upgrade" \
    || fail "/usr/bin/indiserver CHANGED across the upgrade"
fi
rpm -V libindi libindi-libs kstars >/tmp/distro-verify.$$ 2>&1
if [ -s /tmp/distro-verify.$$ ]; then
  fail "rpm -V reports distro INDI modified:"
  sed 's/^/    /' /tmp/distro-verify.$$
else
  pass "rpm -V clean on libindi/libindi-libs/kstars"
fi
rm -f /tmp/distro-verify.$$

echo "############ STEP 7: full removal still cleans up completely ############"
dnf remove -y $(rpm -qa | grep '^indi-stable-') 2>&1 | tail -3
if [ -e /opt/indi-stable ]; then
  fail "/opt/indi-stable survived a full removal after an upgrade -- see LESSONS_LEARNED.md #20"
  find /opt/indi-stable 2>&1 | sed 's/^/    /'
else
  pass "/opt/indi-stable fully removed, even after an upgrade in between"
fi

echo
if [ $FAIL -eq 0 ]; then
  echo "############ 3RDPARTY UPGRADE PATH: ALL CHECKS PASSED ############"
else
  echo "############ 3RDPARTY UPGRADE PATH: ONE OR MORE CHECKS FAILED ############"
fi
exit $FAIL
