#!/bin/bash
#
# Snapshot A depsolve test -- does dnf still pull in the DISTRIBUTION's INDI
# when ours is already installed?
#
# This is the test that exercises the package-metadata layer of the coexistence
# guarantee (DESIGN.md, "A private path is not enough"). FEDORA.md's checklist
# item 7 asks what our RPM ADVERTISES; this asks what dnf actually DOES with it,
# which is where the bug would really have happened.
#
# Why stellarium: it requires libindiclient.so.2()(64bit) by SONAME ALONE, with
# no package-name dependency on libindi, and only libindi-libs provides that
# name in the Fedora repositories. If our package advertised that soname, dnf
# would be free to satisfy stellarium from us and skip libindi-libs entirely.
#
# Run as: sudo bash scripts/test-snapshot-a-depsolve.sh [rpm-dir]
#
# The optional directory is where the built RPMs live, matching
# test-snapshot-b-coexist.sh. It defaults to the rpmbuild tree, but that
# directory is EMPTY on fedoraastro -- the builds happen through mock and land
# in ~/mock-result-pcfix (STATUS.md, machine state), so without an argument
# this script aborts at STEP 0 and can never run on the machine it was written
# for. The glob below is already anchored on .x86_64.rpm, which is what makes a
# mock resultdir safe to point at: it keeps the .src.rpm beside the binaries
# (LESSONS_LEARNED.md #3).
#
# TWO PROPERTIES THIS SCRIPT MUST KEEP -- the first version lacked both and
# "passed" while testing nothing (LESSONS_LEARNED.md #4 and #5):
#   1. Absolute paths. Under sudo HOME is /root, so ~/rpmbuild silently misses.
#   2. Assert the setup landed before measuring it. A test that cannot tell
#      "passed" from "never ran" is worse than no test.
#
set -u

# Absolute, and derived from the invoking user rather than root's HOME.
BUILD_USER=${SUDO_USER:-$(id -un)}
R=${1:-$(getent passwd "$BUILD_USER" | cut -d: -f6)/rpmbuild/RPMS/x86_64}

die() { echo; echo "*** ABORT: $* ***"; exit 1; }

echo "############ STEP 0: RPMs present ############"
echo "  looking in: $R"
ls $R/indi-stable-core-2*.x86_64.rpm $R/indi-stable-core-libs-2*.x86_64.rpm \
  || die "built RPMs not found under $R -- build them first (see FEDORA.md)"

echo "############ STEP 0b: reset to a Snapshot-A-equivalent INDI state ############"
# --no-autoremove deliberately KEEPS stellarium-data (613 MiB) installed. dnf5
# defaults to keepcache=0, so letting it go would re-download the whole thing
# for no benefit; it is data files with no bearing on soname resolution.
dnf remove -y --no-autoremove stellarium libindi-libs 2>/dev/null
rpm -q libindi-libs     >/dev/null 2>&1 && die "libindi-libs still installed after removal"
rpm -q stellarium       >/dev/null 2>&1 && die "stellarium still installed after removal"
rpm -q indi-stable-core >/dev/null 2>&1 && die "indi-stable-core already installed -- reset it first"
echo "  OK: no INDI of any kind installed"

echo "############ STEP 1: install ours (MUST succeed) ############"
dnf install -y $R/indi-stable-core-2*.x86_64.rpm $R/indi-stable-core-libs-2*.x86_64.rpm \
  || die "installing our packages failed"
rpm -q indi-stable-core indi-stable-core-libs || die "our packages are not installed"
test -d /opt/indi-stable || die "/opt/indi-stable missing after install"
echo "  OK: indi-stable is genuinely installed -- the test now has a subject"

echo "############ STEP 2: libindi-libs must still be absent ############"
rpm -q libindi-libs && die "libindi-libs appeared unexpectedly" \
                    || echo "  OK: not installed"

echo "############ STEP 3: install stellarium ############"
echo "   THE WHOLE TEST: libindi-libs MUST appear in this transaction."
dnf install -y stellarium || die "stellarium install failed"

echo "############ STEP 4: libindi-libs MUST now be installed ############"
if rpm -q libindi-libs; then
  echo "  PASS: dnf pulled in the distro INDI despite ours being present"
else
  echo "  *** FAIL: dnf satisfied stellarium from OUR package -- shadowing bug ***"
  exit 1
fi

echo "############ STEP 5: stellarium must link the DISTRO's INDI, not /opt ############"
ldd "$(command -v stellarium)" | grep -i indi

echo "############ STEP 6: coexistence spot-checks ############"
# readlink -e, NOT -f: -f prints a path whether or not the target exists, which
# read as "resolves to itself" for an absent /usr/bin/indiserver on 2026-08-24.
echo -n "  distro indiserver: "
readlink -e /usr/bin/indiserver \
  || echo "<absent -- expected when only libindi-libs is installed; it ships no binaries>"
echo -n "  ours:              "
readlink -e /usr/bin/indiserver-stable || echo "<MISSING -- our alternative is broken>"
rpm -V libindi-libs; echo "  rpm -V libindi-libs exit=$?  (0 = distro files unmodified)"
echo "############ DONE ############"
