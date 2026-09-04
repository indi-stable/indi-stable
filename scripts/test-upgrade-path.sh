#!/bin/bash
#
# Upgrade-path test -- the branch that the verified uninstall NEVER took.
#
# Why this needs its own test. %postun is guarded:
#
#     %postun
#     if [ $1 -eq 0 ]; then
#         alternatives --remove indiserver-stable .../indiserver
#     fi
#
# $1 is the number of copies of this package that will remain. On a true
# removal it is 0 and the guard fires. On an UPGRADE it is 1, and the guard
# must NOT fire -- because RPM runs scriptlets in this order:
#
#     new %pre($1=2) -> new files -> new %post($1=2)
#       -> old %preun($1=1) -> old files removed -> old %postun($1=1)
#
# The OLD package's %postun runs LAST, after the new package has already
# registered its alternative. An unguarded --remove there would tear down the
# link the new %post had just installed, leaving /usr/bin/indiserver-stable
# dangling into a prefix that still exists -- a broken command with no failed
# transaction to point at. The guard is present in the spec but has never been
# executed, because every test so far has either installed or fully removed.
#
# Run as: sudo bash scripts/test-upgrade-path.sh <old-rpm-dir> <new-rpm-dir>
#
# Standing rules for root-run tests (LESSONS_LEARNED.md #4, #5): absolute paths;
# and assert the setup landed before measuring it.
#
set -u

OLD_DIR=${1:?usage: test-upgrade-path.sh <old-rpm-dir> <new-rpm-dir>}
NEW_DIR=${2:?usage: test-upgrade-path.sh <old-rpm-dir> <new-rpm-dir>}

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

LINK=/usr/bin/indiserver-stable
ADMIN=/var/lib/alternatives/indiserver-stable

echo "############ STEP 0: two genuinely different builds ############"
ls $OLD_DIR/indi-stable-core-2*.x86_64.rpm >/dev/null 2>&1 || die "no RPMs in $OLD_DIR"
ls $NEW_DIR/indi-stable-core-2*.x86_64.rpm >/dev/null 2>&1 || die "no RPMs in $NEW_DIR"
OLD_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $OLD_DIR/indi-stable-core-2*.x86_64.rpm 2>/dev/null | head -1)
NEW_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $NEW_DIR/indi-stable-core-2*.x86_64.rpm 2>/dev/null | head -1)
echo "  old: $OLD_NVR"
echo "  new: $NEW_NVR"
[ "$OLD_NVR" != "$NEW_NVR" ] \
  || die "both directories hold the SAME NVR -- an 'upgrade' to an identical package is a reinstall, not an upgrade, and would not exercise the scriptlet ordering this test exists for"

echo "############ STEP 0b: start from a clean slate ############"
rpm -q indi-stable-core >/dev/null 2>&1 && {
  dnf remove -y indi-stable-core indi-stable-core-libs indi-stable-core-devel 2>/dev/null
}
rpm -q indi-stable-core >/dev/null 2>&1 && die "could not remove a pre-existing indi-stable-core"
test -e "$LINK"  && die "$LINK survived removal -- stale state, clean it before testing"
test -e "$ADMIN" && die "$ADMIN survived removal -- stale alternatives admin record"
pass "no indi-stable installed, no stale alternative"

# The distribution's binary is the bystander this whole project exists to protect.
DISTRO_PRE=""
if [ -e /usr/bin/indiserver ]; then
  DISTRO_PRE=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
  echo "  distro /usr/bin/indiserver sha256: $DISTRO_PRE"
else
  echo "  (no distro /usr/bin/indiserver on this box)"
fi

echo "############ STEP 1: install the OLD build ############"
dnf install -y $OLD_DIR/indi-stable-core-2*.x86_64.rpm $OLD_DIR/indi-stable-core-libs-2*.x86_64.rpm \
  || die "installing the old build failed"
rpm -q indi-stable-core || die "old build is not installed"
INSTALLED_OLD=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}' indi-stable-core)
echo "  installed: $INSTALLED_OLD"

OLD_TARGET=$(readlink -e "$LINK") || die "$LINK does not resolve after the OLD install -- the alternative never worked, so an upgrade test would be meaningless"
echo "  $LINK -> $OLD_TARGET"
test -e "$ADMIN" || die "no alternatives admin record after the old install"
pass "the alternative is live before the upgrade -- the test has something to break"

echo "############ STEP 2: THE UPGRADE ############"
echo "   Watch for the old package's %postun. If the \$1 -eq 0 guard is wrong,"
echo "   it removes the alternative the new %post just installed."
dnf install -y $NEW_DIR/indi-stable-core-2*.x86_64.rpm $NEW_DIR/indi-stable-core-libs-2*.x86_64.rpm \
  || die "the upgrade transaction itself failed"

echo "############ STEP 3: did the upgrade actually happen? ############"
INSTALLED_NEW=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}' indi-stable-core)
echo "  now installed: $INSTALLED_NEW"
[ "$INSTALLED_NEW" != "$INSTALLED_OLD" ] \
  && pass "the installed NVR changed, so an upgrade really occurred" \
  || fail "still $INSTALLED_OLD -- nothing was upgraded and STEP 4 would prove nothing"
[ "$(rpm -q indi-stable-core | wc -l)" -eq 1 ] \
  && pass "exactly one copy installed" \
  || fail "more than one indi-stable-core is installed: $(rpm -q indi-stable-core | tr '\n' ' ')"

echo "############ STEP 4: THE POINT -- the alternative survived ############"
if NEW_TARGET=$(readlink -e "$LINK"); then
  echo "  $LINK -> $NEW_TARGET"
  pass "the command still resolves after the upgrade"
  case "$NEW_TARGET" in
    /opt/indi-stable/*) pass "and still points into the private prefix" ;;
    *) fail "it now points OUTSIDE the private prefix: $NEW_TARGET" ;;
  esac
else
  fail "$LINK IS DANGLING OR GONE after the upgrade -- this is exactly the %postun ordering bug the guard exists to prevent"
  ls -l "$LINK" 2>&1 | sed 's/^/    /'
fi
if test -e "$ADMIN"; then
  pass "the alternatives admin record survived"
  alternatives --display indiserver-stable 2>&1 | sed 's/^/    /'
else
  fail "$ADMIN is gone -- the old %postun withdrew the alternative mid-upgrade"
fi

echo "############ STEP 5: it still runs ############"
if "$LINK" --version 2>&1 | grep -E 'INDI Library|Code' | sed 's/^/    /'; then
  pass "the upgraded indiserver-stable executes"
else
  fail "the upgraded indiserver-stable did not report a version"
fi

echo "############ STEP 6: the distro binary is still a bystander ############"
if [ -n "$DISTRO_PRE" ]; then
  DISTRO_POST=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
  [ "$DISTRO_PRE" = "$DISTRO_POST" ] \
    && pass "/usr/bin/indiserver unchanged across the upgrade" \
    || fail "/usr/bin/indiserver CHANGED across the upgrade"
  rpm -V libindi >/dev/null 2>&1 && pass "rpm -V libindi still exits 0" \
                                 || fail "rpm -V libindi now reports modifications"
fi

echo "############ STEP 7: CONTROL -- can STEP 4 detect a missing link? ############"
# STEP 4 passes by FINDING something, but the failure it guards against is an
# absence. Remove the package for real ($1 -eq 0, the guard fires) and confirm
# the very same checks now report the link gone. If they did not, STEP 4's pass
# would have meant nothing.
dnf remove -y indi-stable-core indi-stable-core-libs 2>&1 | tail -3
if readlink -e "$LINK" >/dev/null 2>&1; then
  fail "CONTROL: $LINK STILL resolves after a full removal -- the guard did not fire on \$1 -eq 0, and STEP 4 cannot be trusted"
else
  pass "CONTROL: after a real removal the link is gone, so STEP 4 was a genuine check"
fi
test -e "$ADMIN" \
  && fail "CONTROL: the admin record $ADMIN survived a full removal" \
  || pass "CONTROL: the admin record was cleaned up too"
test -d /opt/indi-stable \
  && fail "/opt/indi-stable survived removal" \
  || pass "/opt/indi-stable fully removed"

echo
if [ $FAIL -eq 0 ]; then
  echo "############ UPGRADE PATH: ALL CHECKS PASSED ############"
else
  echo "############ UPGRADE PATH: ONE OR MORE CHECKS FAILED ############"
fi
exit $FAIL
