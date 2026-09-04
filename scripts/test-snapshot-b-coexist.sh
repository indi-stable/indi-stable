#!/bin/bash
#
# Snapshot B coexistence test -- the case Snapshot A structurally COULD NOT
# reach: a box carrying the distribution's `libindi` (not merely `libindi-libs`)
# and `kstars`.
#
# Why that distinction is the whole point. Snapshot A installed stellarium,
# which depends only on libindi-libs, and libindi-libs SHIPS NO BINARIES. So
# that box had the distro's libraries but no /usr/bin/indiserver, and the
# two-server comparison -- the one that asks whether two indiservers with
# IDENTICAL SONAMEs each map their own libraries -- had nothing to compare
# against. It has only ever been run on the laptop. This runs it on a machine
# whose state we control from a known-pristine snapshot.
#
# Run as: sudo bash scripts/test-snapshot-b-coexist.sh
#
# The two standing rules for any root-run test (LESSONS_LEARNED.md #4 and #5):
#   1. Absolute paths -- under sudo HOME is /root, so ~/rpmbuild silently misses.
#   2. Assert the setup landed before measuring it. A test that cannot tell
#      "passed" from "never ran" is the same defect as a check that inspects an
#      uninstalled package and reports success.
#
# And the rule that came out of checklist item 7 (LESSONS_LEARNED.md #1, "the checks have
# been wrong more often than the packaging"): where a step passes by finding
# NOTHING, prove the machinery could have found something. Positive controls
# below are marked CONTROL.
#
set -u

# Optional arg: a directory holding the built RPMs. Defaults to the rpmbuild
# tree, but a mock resultdir works too -- and note the glob below is anchored to
# .x86_64.rpm for exactly that reason. A mock resultdir keeps the .src.rpm in
# the SAME directory as the binaries, so the documented `-2*.rpm` glob matches
# indi-stable-core-2.2.4.2-1.fc44.src.rpm as well and drags the spec and the
# upstream tarball into every file listing.
BUILD_USER=${SUDO_USER:-$(id -un)}
R=${1:-$(getent passwd "$BUILD_USER" | cut -d: -f6)/rpmbuild/RPMS/x86_64}

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

echo "############ STEP 0: the Snapshot B precondition ############"
echo "  looking for RPMs in: $R"
ls $R/indi-stable-core-2*.x86_64.rpm $R/indi-stable-core-libs-2*.x86_64.rpm \
  || die "built RPMs not found under $R -- build them first (see FEDORA.md)"

# libindi, NOT libindi-libs. libindi is the package that owns /usr/bin/indiserver.
rpm -q libindi >/dev/null 2>&1 \
  || die "distro 'libindi' is NOT installed -- this is Snapshot A, not B. Run: sudo dnf install libindi kstars"
rpm -q kstars  >/dev/null 2>&1 \
  || die "'kstars' is NOT installed -- Ekos coexistence is the point of Snapshot B"
test -x /usr/bin/indiserver \
  || die "/usr/bin/indiserver missing even though libindi is installed"
rpm -q indi-stable-core >/dev/null 2>&1 \
  && die "our package is ALREADY installed -- this test must start from the distro-only state"
echo "  OK: distro libindi + kstars present, ours absent. This is Snapshot B."

echo "############ STEP 1: fingerprint the distro BEFORE we touch anything ############"
PRE_HASH=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
PRE_MTIME=$(stat -c %y /usr/bin/indiserver)
PRE_OWNER=$(rpm -qf /usr/bin/indiserver)
echo "  /usr/bin/indiserver"
echo "    sha256 : $PRE_HASH"
echo "    mtime  : $PRE_MTIME"
echo "    owner  : $PRE_OWNER"
rpm -V libindi > /tmp/snapb-verify-pre.txt 2>&1
echo "    rpm -V libindi exit=$?  (0 = pristine)"

echo "############ STEP 2: install ours alongside (MUST succeed) ############"
dnf install -y $R/indi-stable-core-2*.x86_64.rpm $R/indi-stable-core-libs-2*.x86_64.rpm \
  || die "installing our packages failed"
rpm -q indi-stable-core indi-stable-core-libs || die "our packages are not installed"
test -d /opt/indi-stable || die "/opt/indi-stable missing after install"
pass "indi-stable is genuinely installed -- the test now has a subject"

echo "############ STEP 3: the distro package must be UNTOUCHED ############"
POST_HASH=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
if [ "$PRE_HASH" = "$POST_HASH" ]; then
  pass "/usr/bin/indiserver is byte-identical after our install"
else
  fail "/usr/bin/indiserver CHANGED: $PRE_HASH -> $POST_HASH"
fi
[ "$PRE_MTIME" = "$(stat -c %y /usr/bin/indiserver)" ] \
  && pass "mtime unchanged" || fail "mtime changed -- something rewrote it"
[ "$PRE_OWNER" = "$(rpm -qf /usr/bin/indiserver)" ] \
  && pass "still owned by $PRE_OWNER" || fail "ownership moved to $(rpm -qf /usr/bin/indiserver)"
if rpm -V libindi > /tmp/snapb-verify-post.txt 2>&1; then
  pass "rpm -V libindi exits 0 -- every distro file still matches its manifest"
else
  fail "rpm -V libindi reports modifications:"; cat /tmp/snapb-verify-post.txt
fi
rpm -V kstars >/dev/null 2>&1 \
  && pass "rpm -V kstars exits 0" || fail "rpm -V kstars reports modifications"

echo "############ STEP 3b: CONTROL -- can this hash check tell binaries apart? ############"
# If ours and the distro's hashed the same, every comparison above would pass
# vacuously. They are different builds and MUST differ.
OURS_HASH=$(sha256sum /opt/indi-stable/bin/indiserver | awk '{print $1}')
echo "  distro : $PRE_HASH"
echo "  ours   : $OURS_HASH"
if [ "$PRE_HASH" != "$OURS_HASH" ]; then
  pass "CONTROL: the two indiservers hash differently, so STEP 3 could have failed"
else
  fail "CONTROL: both indiservers hash the SAME -- STEP 3 proves nothing"
fi

echo "############ STEP 4: nothing of ours landed under /usr/bin ############"
# The one rule: no packaged file may land in /usr/bin. indiserver-stable is a
# SYMLINK created by alternatives at postinst time, not a packaged file, so it
# is expected here and is excluded by name.
rpm -ql indi-stable-core indi-stable-core-libs | grep '^/usr/bin' \
  && fail "a PACKAGED file landed in /usr/bin" \
  || pass "no packaged file under /usr/bin"

echo "############ STEP 5: the two names resolve to two different binaries ############"
# readlink -e, NOT -f. -f prints a path for a file that does not exist.
D_RESOLVED=$(readlink -e /usr/bin/indiserver)        || fail "distro indiserver does not resolve"
O_RESOLVED=$(readlink -e /usr/bin/indiserver-stable) || fail "OUR indiserver-stable does not resolve"
echo "  /usr/bin/indiserver        -> ${D_RESOLVED:-<unresolved>}"
echo "  /usr/bin/indiserver-stable -> ${O_RESOLVED:-<unresolved>}"
case "${O_RESOLVED:-}" in
  /opt/indi-stable/*) pass "ours resolves into the private prefix" ;;
  *) fail "ours resolves OUTSIDE the private prefix: ${O_RESOLVED:-<none>}" ;;
esac
[ "${D_RESOLVED:-x}" != "${O_RESOLVED:-y}" ] \
  && pass "the two names are genuinely distinct binaries" \
  || fail "both names resolve to the SAME file"

echo "############ STEP 6: alternatives registered ONLY the namespaced name ############"
alternatives --display indiserver-stable || fail "indiserver-stable not registered"
echo "  -- and the PLAIN name must not be ours:"
if [ -e /var/lib/alternatives/indiserver ]; then
  fail "an alternatives admin record exists for the PLAIN name 'indiserver'"
  cat /var/lib/alternatives/indiserver
else
  pass "no alternatives record for the plain 'indiserver' -- we never claimed it"
fi

echo "############ STEP 7: kstars links the DISTRO's INDI, not ours ############"
ldd "$(command -v kstars)" | grep -i indi | sed 's/^/    /'
if ldd "$(command -v kstars)" | grep -i indi | grep -q '/opt/indi-stable'; then
  fail "kstars links into OUR private prefix -- Ekos would be running our build"
else
  pass "kstars links no library from /opt/indi-stable"
fi

echo "############ STEP 8: the Ekos driver catalogue is the distro's, untouched ############"
# Ekos does not scan a directory of per-driver files -- it reads ONE catalogue,
# /usr/share/indi/drivers.xml, which lists every driver and the binary to exec.
# That single file is the thing that decides which drivers Ekos offers and which
# executable it launches, so it is the file that matters here, not a file count.
# If our package rewrote or replaced it, Ekos would silently launch OUR binaries.
D_CAT=/usr/share/indi/drivers.xml
O_CAT=/opt/indi-stable/share/indi/drivers.xml
echo "  distro catalogue : $D_CAT"
echo "    owner  : $(rpm -qf $D_CAT 2>&1)"
echo "    sha256 : $(sha256sum $D_CAT | awk '{print $1}')"
echo "    drivers listed: $(grep -c '<driver' $D_CAT 2>/dev/null)"
[ "$(rpm -qf $D_CAT 2>/dev/null)" = "$(rpm -q libindi)" ] \
  && pass "drivers.xml is still owned by $(rpm -q libindi)" \
  || fail "drivers.xml ownership moved to $(rpm -qf $D_CAT 2>&1)"

echo "  our catalogue    : $O_CAT"
if [ -e "$O_CAT" ]; then
  echo "    owner  : $(rpm -qf $O_CAT 2>&1)"
  echo "    drivers listed: $(grep -c '<driver' $O_CAT 2>/dev/null)"
  # Ours must point at binaries in the private prefix, not bare names that
  # would resolve through PATH to the distro's /usr/bin copies.
  pass "we ship our own catalogue inside the prefix"
else
  echo "    <absent>"
fi

rpm -ql indi-stable-core indi-stable-core-libs | grep '^/usr/share/indi' \
  && fail "we installed a file into the distro's XML catalogue directory" \
  || pass "we own nothing under /usr/share/indi"

echo "############ STEP 9: udev rules -- ours renamed, distro's intact ############"
ls /usr/lib/udev/rules.d/ | grep -i indi | sed 's/^/    /'
shopt -s nullglob
for f in /usr/lib/udev/rules.d/*indi*; do
  case "$(rpm -qf "$f" 2>/dev/null)" in
    indi-stable-core*) case "$f" in
        *indi-stable*) ;;
        *) fail "our udev rule is NOT namespaced: $f" ;;
      esac ;;
  esac
done
pass "udev rule naming checked"

echo
if [ $FAIL -eq 0 ]; then
  echo "############ SNAPSHOT B STRUCTURAL CHECKS: ALL PASSED ############"
else
  echo "############ SNAPSHOT B: ONE OR MORE CHECKS FAILED (see *** FAIL above) ############"
fi
echo
echo "Still to run BY HAND -- these are not structural and this script does not"
echo "attempt them:"
echo "  1. The two-server runtime comparison, which is the ground truth:"
echo "       bash scripts/test-runtime-maps.sh /usr/bin/indiserver-stable \\"
echo "            /opt/indi-stable/bin/indi_simulator_ccd 7625"
echo "       bash scripts/test-runtime-maps.sh /usr/bin/indiserver \\"
echo "            /usr/bin/indi_simulator_ccd 7626"
echo "     Each driver must map its OWN libindidriver.so.2.2.4 despite the"
echo "     shared SONAME. Needs no root."
echo "  2. Ekos itself, which needs a graphical session. BOTH cases are"
echo "     verified as of 2026-08-26 -- see DESIGN.md, 'Resolution --"
echo "     absolute paths in our drivers.xml'. To re-check after a change,"
echo "     start a simulator profile and run:"
echo "       bash scripts/observe-ekos-live.sh"
echo "     It reports which case it saw rather than guessing. Do NOT judge"
echo "     it from the Ekos driver list: both catalogues carry the same 290"
echo "     labels, and the GUI shows the label, not the binary path that is"
echo "     the only field differing between them."
exit $FAIL
