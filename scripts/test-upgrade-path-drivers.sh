#!/bin/bash
#
# Upgrade-path test for indi-stable-3rdparty-drivers -- run together with
# indi-stable-3rdparty-libs's own upgrade, not standalone, because that is
# the only upgrade this project's design actually produces: -libs and
# -drivers share one upstream tag and are always built and promoted
# together (DESIGN.md, "Resolution -- two source packages"), and -drivers's
# own BuildRequires pin the exact %{version}-%{release} of the -libs -devel
# subpackages it configures against, not just the Version. A driver upgrade
# with -libs held fixed is not a scenario this project's own release
# process can produce.
#
# Like -drivers itself, this has no scriptlet-ordering class to test (no
# %post/%postun anywhere in either spec). What actually matters, and had
# never been exercised until this test: whether the two packages' shared
# %dir ownership (LESSONS_LEARNED.md #20) and cross-package Requires stay
# correct through an UPGRADE transaction, not just a fresh install -- and
# whether the driver binaries still dynamically resolve and RUN afterward,
# which is the strongest form of "the RPATH survived" available (STATUS.md's
# coexistence pass already showed ldd + actual execution is a materially
# stronger check than RPM metadata alone).
#
# indi-stable-core is NOT part of the upgrade transaction -- it stays
# installed and unchanged throughout, exactly as it would on a real system
# where core and 3rdparty are promoted on independent schedules (DESIGN.md,
# "indi-3rdparty is a different shape of build" -- indi-3rdparty is its own
# version axis, independent of core's).
#
# Run as:
#   sudo bash scripts/test-upgrade-path-drivers.sh \
#       <old-libs-dir> <new-libs-dir> <old-drivers-dir> <new-drivers-dir> [core-dir]
#
# core-dir defaults to ~/mock-result-pcfix (STATUS.md, machine state).
#
# Standing rules for root-run tests (LESSONS_LEARNED.md #4, #5): absolute
# paths; assert the setup landed before measuring it.
#
set -u

OLD_LIBS_DIR=${1:?usage: test-upgrade-path-drivers.sh <old-libs-dir> <new-libs-dir> <old-drivers-dir> <new-drivers-dir> [core-dir]}
NEW_LIBS_DIR=${2:?usage: test-upgrade-path-drivers.sh <old-libs-dir> <new-libs-dir> <old-drivers-dir> <new-drivers-dir> [core-dir]}
OLD_DRIVERS_DIR=${3:?usage: test-upgrade-path-drivers.sh <old-libs-dir> <new-libs-dir> <old-drivers-dir> <new-drivers-dir> [core-dir]}
NEW_DRIVERS_DIR=${4:?usage: test-upgrade-path-drivers.sh <old-libs-dir> <new-libs-dir> <old-drivers-dir> <new-drivers-dir> [core-dir]}
CORE_DIR=${5:-$HOME/mock-result-pcfix}

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

# Anchored to *.x86_64.rpm and excluding debuginfo/debugsource throughout --
# a resultdir holds the .src.rpm too (LESSONS_LEARNED.md #3), and installing
# THAT installs its BuildRequires as Requires (LESSONS_LEARNED.md #21).
libs_rpms()    { ls "$1"/indi-stable-3rdparty-libs-*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource; }
drivers_rpms() { ls "$1"/indi-stable-3rdparty-drivers-*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource; }
core_rpms() {
  ls "$CORE_DIR"/indi-stable-core-2*.x86_64.rpm "$CORE_DIR"/indi-stable-core-libs-2*.x86_64.rpm \
     "$CORE_DIR"/indi-stable-core-devel-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource
}

echo "############ STEP 0: genuinely different builds, on both sides ############"
test -n "$(libs_rpms "$OLD_LIBS_DIR")"       || die "no RPMs in $OLD_LIBS_DIR"
test -n "$(libs_rpms "$NEW_LIBS_DIR")"       || die "no RPMs in $NEW_LIBS_DIR"
test -n "$(drivers_rpms "$OLD_DRIVERS_DIR")" || die "no RPMs in $OLD_DRIVERS_DIR"
test -n "$(drivers_rpms "$NEW_DRIVERS_DIR")" || die "no RPMs in $NEW_DRIVERS_DIR"
test -n "$(core_rpms)" || die "no core RPMs in $CORE_DIR -- build indi-stable-core first (FEDORA.md)"
OLD_LIBS_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(libs_rpms "$OLD_LIBS_DIR" | grep -- '-apogee-2' | grep -v devel) 2>/dev/null | head -1)
NEW_LIBS_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(libs_rpms "$NEW_LIBS_DIR" | grep -- '-apogee-2' | grep -v devel) 2>/dev/null | head -1)
OLD_DRV_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(drivers_rpms "$OLD_DRIVERS_DIR" | grep -- '-apogee-2') 2>/dev/null | head -1)
NEW_DRV_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(drivers_rpms "$NEW_DRIVERS_DIR" | grep -- '-apogee-2') 2>/dev/null | head -1)
echo "  old: $OLD_LIBS_NVR / $OLD_DRV_NVR"
echo "  new: $NEW_LIBS_NVR / $NEW_DRV_NVR"
[ -n "$OLD_LIBS_NVR" ] && [ -n "$NEW_LIBS_NVR" ] && [ -n "$OLD_DRV_NVR" ] && [ -n "$NEW_DRV_NVR" ] \
  || die "could not read an apogee NVR from one of the four directories"
[ "$OLD_LIBS_NVR" != "$NEW_LIBS_NVR" ] && [ "$OLD_DRV_NVR" != "$NEW_DRV_NVR" ] \
  || die "old and new NVRs match on at least one side -- an 'upgrade' to an identical package is a reinstall, not an upgrade"

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

echo "############ STEP 1: install core + the OLD libs + OLD drivers ############"
dnf install -y $(core_rpms) $(libs_rpms "$OLD_LIBS_DIR") $(drivers_rpms "$OLD_DRIVERS_DIR") \
  || die "installing core + old libs + old drivers failed"
CORE_NVR_PRE=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-core indi-stable-core-libs indi-stable-core-devel 2>&1)
INSTALLED_OLD=$(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' | grep -E '^indi-stable-3rdparty-(libs|drivers)' | sort)
echo "  core installed:"; echo "$CORE_NVR_PRE" | sed 's/^/    /'
echo "  3rdparty installed ($(echo "$INSTALLED_OLD" | wc -l) packages):"
test -n "$INSTALLED_OLD" || die "no indi-stable-3rdparty packages installed after STEP 1"

# Confirm a driver actually works BEFORE the upgrade -- the control for
# STEP 5's "it still works after" needs a known-good starting point.
PRE_USAGE=$(/opt/indi-stable/bin/indi_apogee_ccd --help 2>&1)
echo "$PRE_USAGE" | grep -qi "INDI Device driver" \
  || die "indi_apogee_ccd does not report its usage banner even before the upgrade -- STEP 5 would prove nothing"

echo "############ STEP 2: THE UPGRADE -- libs+drivers together, core untouched ############"
echo "  (core is not part of this dnf transaction at all)"
dnf install -y $(libs_rpms "$NEW_LIBS_DIR") $(drivers_rpms "$NEW_DRIVERS_DIR") \
  || die "the upgrade transaction itself failed"

echo "############ STEP 3: did the upgrade happen, and did core survive? ############"
INSTALLED_NEW=$(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' | grep -E '^indi-stable-3rdparty-(libs|drivers)' | sort)
[ "$INSTALLED_NEW" != "$INSTALLED_OLD" ] \
  && pass "the installed NVRs changed, so an upgrade really occurred" \
  || fail "still the OLD NVRs -- nothing was upgraded and later steps would prove nothing"
DUPES=$(rpm -qa --qf '%{NAME}\n' | grep -E '^indi-stable-3rdparty-(libs|drivers)' | sort | uniq -d)
[ -z "$DUPES" ] \
  && pass "exactly one copy of each 3rdparty subpackage installed" \
  || fail "more than one copy installed of: $DUPES"
CORE_NVR_POST=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-core indi-stable-core-libs indi-stable-core-devel 2>&1)
[ "$CORE_NVR_POST" = "$CORE_NVR_PRE" ] \
  && pass "indi-stable-core/-libs/-devel NVRs unchanged -- the sibling source package was not touched" \
  || fail "core's own NVRs changed across a libs+drivers upgrade: $CORE_NVR_PRE -> $CORE_NVR_POST"
rpm -V indi-stable-core indi-stable-core-libs indi-stable-core-devel >/tmp/core-verify.$$ 2>&1
if [ -s /tmp/core-verify.$$ ]; then
  fail "rpm -V reports core packages modified by the upgrade:"
  sed 's/^/    /' /tmp/core-verify.$$
else
  pass "rpm -V clean on core's own packages after the upgrade"
fi
rm -f /tmp/core-verify.$$

echo "############ STEP 4: no orphaned files left under /opt/indi-stable ############"
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
CANARY=/opt/indi-stable/bin/orphan-canary-$$
touch "$CANARY" 2>/dev/null || die "could not create the canary file -- STEP 4's control cannot run"
CONTROL_ORPHANS=$(orphans)
rm -f "$CANARY"
case "$CONTROL_ORPHANS" in
  *"$CANARY"*) pass "CONTROL: the orphan check correctly flagged a planted stray file" ;;
  *) fail "CONTROL: the orphan check did NOT flag a planted stray file at $CANARY -- STEP 4 cannot be trusted" ;;
esac

echo "############ STEP 5: the upgraded driver actually resolves AND runs ############"
# Stronger than checking RPATH alone (STATUS.md's coexistence pass already
# found ldd + real execution catches things RPM metadata inspection cannot).
LDD_OUT=$(ldd /opt/indi-stable/bin/indi_apogee_ccd 2>&1)
if echo "$LDD_OUT" | grep -qi "not found"; then
  fail "indi_apogee_ccd has an unresolved dependency after the upgrade:"
  echo "$LDD_OUT" | grep -i "not found" | sed 's/^/    /'
else
  pass "indi_apogee_ccd: all dynamic dependencies resolve after the upgrade"
fi
for lib in libapogee.so libindidriver.so libindiclient.so; do
  echo "$LDD_OUT" | grep -q "$lib.*=> /opt/indi-stable/lib" \
    && pass "$lib resolves into the private prefix, not a distro copy" \
    || fail "$lib did not resolve into /opt/indi-stable/lib -- see ldd output above"
done
POST_USAGE=$(/opt/indi-stable/bin/indi_apogee_ccd --help 2>&1)
echo "$POST_USAGE" | grep -qi "INDI Device driver" \
  && pass "indi_apogee_ccd still runs and reports its usage banner after the upgrade" \
  || fail "indi_apogee_ccd no longer runs correctly after the upgrade"

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
  echo "############ DRIVERS UPGRADE PATH: ALL CHECKS PASSED ############"
else
  echo "############ DRIVERS UPGRADE PATH: ONE OR MORE CHECKS FAILED ############"
fi
exit $FAIL
