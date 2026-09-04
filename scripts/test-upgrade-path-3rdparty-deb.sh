#!/bin/bash
#
# Upgrade-path test for the Debian side of indi-stable-3rdparty-libs.
#
# Unlike scripts/test-upgrade-path-deb.sh (core), there is no maintainer-
# script-ordering class of bug to trace here: indi-stable-3rdparty-libs ships
# no postinst/prerm and registers no alternative at all -- confirmed by
# reading core/deb-3rdparty-libs itself, which has neither file. So this
# script does not need dpkg -D2 tracing or a stranded-admin-record control;
# what actually matters, mirroring scripts/test-upgrade-path-3rdparty.sh (the
# RPM equivalent of this exact test), is:
#
#   * does the upgrade transaction leave indi-stable-core alone (an
#     independent source package and an independent version axis --
#     DESIGN.md), and
#   * does file replacement across 16 binary packages leave anything
#     orphaned under /opt/indi-stable (with a planted-file control, since a
#     check that passes by finding nothing must be shown able to find
#     something -- LESSONS_LEARNED.md #1), and
#   * do the upgraded libraries still dynamically resolve via RPATH.
#
# indi-stable-3rdparty-libs ships no executable at all (pure libraries), so
# there is no "runs and prints its usage banner" check available the way
# the RPM drivers upgrade test has -- ldd is the strongest verification this
# package can offer on its own. The equivalent functional check belongs to
# indi-stable-3rdparty-drivers's own (not yet written) Debian upgrade test.
#
# Run as:
#   sudo bash scripts/test-upgrade-path-3rdparty-deb.sh [old-deb-dir] [new-deb-dir] [core-deb-dir]
#
# OLD_VER/NEW_VER environment variables override the defaults, same
# convention as test-upgrade-path-deb.sh.
#
# Standing rules: absolute paths, never ~ (LESSONS_LEARNED.md #4); assert the
# setup landed before measuring it (#5); restore by diffing (#6).
#
set -u

BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)
OLD_DIR=${1:-$HOMEDIR/build}
NEW_DIR=${2:-$OLD_DIR}
CORE_DIR=${3:-$HOMEDIR/build}
OLD_VER=${OLD_VER:-2.2.4.1-1}
NEW_VER=${NEW_VER:-2.2.4.1-2}
CORE_VER=${CORE_VER:-2.2.4.2-1}
W=$(mktemp -d /tmp/upgrade-3rdparty-deb.XXXXXX)

VENDORS="apogee asi fli playerone inovasdk micam sbig touptek"

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; echo "  work dir kept: $W"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

snapshot() { dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort; }

# _amd64.deb anchor keeps the .ddeb debug packages beside them from matching
# (LESSONS_LEARNED.md #3, the same reason core's own upgrade test anchors).
old_deb()  { echo "$OLD_DIR/indi-stable-3rdparty-libs-$1_${OLD_VER}_amd64.deb"; }
new_deb()  { echo "$NEW_DIR/indi-stable-3rdparty-libs-$1_${NEW_VER}_amd64.deb"; }
old_debs() { for v in $VENDORS; do old_deb "$v"; old_deb "$v-dev"; done; }
new_debs() { for v in $VENDORS; do new_deb "$v"; new_deb "$v-dev"; done; }
pkg_names() { for v in $VENDORS; do echo "indi-stable-3rdparty-libs-$v"; echo "indi-stable-3rdparty-libs-$v-dev"; done; }

echo "############ STEP 0: two genuinely different builds, both present ############"
test "$(id -u)" -eq 0 || die "run under sudo"
for f in $(old_debs) $(new_debs) \
         "$CORE_DIR/indi-stable-core_${CORE_VER}_amd64.deb" \
         "$CORE_DIR/indi-stable-core-libs_${CORE_VER}_amd64.deb" \
         "$CORE_DIR/indi-stable-core-dev_${CORE_VER}_amd64.deb"; do
  test -f "$f" || die "missing $f -- build it first (DEBIAN.md)"
done
test "$OLD_VER" != "$NEW_VER" \
  || die "old and new are the SAME version -- an 'upgrade' to an identical package is a reinstall and would not exercise the transaction this test exists for"
info "old: $OLD_VER    new: $NEW_VER    core (untouched throughout): $CORE_VER"

echo
echo "############ STEP 0b: clean slate ############"
dpkg -s indi-stable-3rdparty-libs-apogee >/dev/null 2>&1 && die "ours is already installed -- clean it first"
dpkg -s indi-stable-core >/dev/null 2>&1 && die "indi-stable-core is already installed -- clean it first"
test -e /opt/indi-stable && die "/opt/indi-stable exists before we installed anything"
pass "no indi-stable installed, /opt/indi-stable absent"

BASELINE=$W/baseline.txt
snapshot > "$BASELINE"
DISTRO_SHA=""
if test -e /usr/bin/indiserver; then
  DISTRO_SHA=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
  info "distro /usr/bin/indiserver sha256: $DISTRO_SHA"
else
  info "(no distribution /usr/bin/indiserver on this box)"
fi

echo
echo "############ STEP 1: install core + the OLD 3rdparty-libs build ############"
apt-get install -y \
  "$CORE_DIR/indi-stable-core_${CORE_VER}_amd64.deb" \
  "$CORE_DIR/indi-stable-core-libs_${CORE_VER}_amd64.deb" \
  "$CORE_DIR/indi-stable-core-dev_${CORE_VER}_amd64.deb" \
  $(old_debs) \
  >"$W/install-old.log" 2>&1 \
  || { tail -30 "$W/install-old.log"; die "installing core + old 3rdparty-libs failed"; }
CORE_VER_PRE=$(dpkg-query -W -f='${Version}' indi-stable-core)
test "$CORE_VER_PRE" = "$CORE_VER" || die "core installed as $CORE_VER_PRE, expected $CORE_VER"
INSTALLED_OLD=$(dpkg-query -W -f='${Package}\t${Version}\n' $(pkg_names) 2>/dev/null | LC_ALL=C sort)
info "3rdparty installed ($(echo "$INSTALLED_OLD" | wc -l) packages)"
test -n "$INSTALLED_OLD" || die "no indi-stable-3rdparty-libs packages installed after STEP 1"

echo
echo "############ STEP 2: THE UPGRADE -- 3rdparty-libs only, core untouched ############"
echo "  (core is not part of this dpkg transaction at all)"
dpkg -i $(new_debs) >"$W/upgrade.log" 2>&1
UPRC=$?
test "$UPRC" -eq 0 || { tail -30 "$W/upgrade.log"; die "the upgrade transaction itself failed (exit $UPRC)"; }
pass "the upgrade transaction succeeded"

echo
echo "############ STEP 3: did the upgrade happen, and did core survive? ############"
INSTALLED_NEW=$(dpkg-query -W -f='${Package}\t${Version}\n' $(pkg_names) 2>/dev/null | LC_ALL=C sort)
test "$INSTALLED_NEW" != "$INSTALLED_OLD" \
  && pass "the installed versions changed, so an upgrade really occurred" \
  || fail "still the OLD versions -- nothing was upgraded and later steps would prove nothing"
DUPES=$(dpkg-query -W -f='${Package}\n' $(pkg_names) 2>/dev/null | sort | uniq -d)
test -z "$DUPES" \
  && pass "exactly one copy of each 3rdparty-libs package installed" \
  || fail "more than one copy installed of: $DUPES"
CORE_VER_POST=$(dpkg-query -W -f='${Version}' indi-stable-core)
test "$CORE_VER_POST" = "$CORE_VER_PRE" \
  && pass "indi-stable-core's version unchanged ($CORE_VER_POST) -- the sibling source package was not touched" \
  || fail "core's own version changed across a 3rdparty-libs-only upgrade: $CORE_VER_PRE -> $CORE_VER_POST"
if dpkg -V indi-stable-core indi-stable-core-libs indi-stable-core-dev >"$W/core-verify.log" 2>&1; then
  pass "dpkg -V clean on core's own packages after the upgrade"
else
  fail "dpkg -V reports core packages modified by the upgrade:"
  sed 's/^/    /' "$W/core-verify.log"
fi

echo
echo "############ STEP 4: no orphaned files left under /opt/indi-stable ############"
# dpkg -S on a path answers "no path found" for anything no package owns.
orphans() {
  find /opt/indi-stable -type f 2>/dev/null | while read -r f; do
    dpkg -S "$f" >/dev/null 2>&1 || echo "$f"
  done
}
ORPHANS=$(orphans)
if test -z "$ORPHANS"; then
  pass "no orphaned files under /opt/indi-stable after the upgrade"
else
  fail "orphaned file(s) found after the upgrade:"
  echo "$ORPHANS" | sed 's/^/    /'
fi

echo
echo "############ STEP 4 CONTROL: can the orphan check find something? ############"
CANARY=/opt/indi-stable/lib/orphan-canary-$$
touch "$CANARY" 2>/dev/null || die "could not create the canary file -- STEP 4's control cannot run"
CONTROL_ORPHANS=$(orphans)
rm -f "$CANARY"
case "$CONTROL_ORPHANS" in
  *"$CANARY"*) ctl "the orphan check correctly flagged a planted stray file" ;;
  *) fail "CONTROL: the orphan check did NOT flag a planted stray file at $CANARY -- STEP 4 cannot be trusted" ;;
esac

echo
echo "############ STEP 5: the upgraded libraries still resolve ############"
# No executable to run and confirm functionally the way the RPM drivers
# upgrade test does (indi-stable-3rdparty-libs ships no binaries at all) --
# ldd is the strongest check available to this package on its own, and it
# applies to every vendor library uniformly: whatever a library actually
# links against (private or system) must still resolve after the upgrade.
for so in /opt/indi-stable/lib/libapogee.so.* /opt/indi-stable/lib/libtoupcam.so.*; do
  test -e "$so" || { fail "expected library missing after upgrade: $so"; continue; }
  LDD_OUT=$(ldd "$so" 2>&1)
  if echo "$LDD_OUT" | grep -qi "not found"; then
    fail "$(basename "$so") has an unresolved dependency after the upgrade:"
    echo "$LDD_OUT" | grep -i "not found" | sed 's/^/    /'
  else
    pass "$(basename "$so"): all dynamic dependencies resolve after the upgrade"
  fi
done
# RUNPATH is checked on apogee specifically, not blanket across every vendor
# library. Found running this test the first time, 2026-08-26: libtoupcam.so
# genuinely carries no RUNPATH at all (readelf -d NEEDED shows only libc,
# libpthread, libm, librt, libdl -- ordinary system libraries always
# resolvable via the standard search path, nothing under /opt/indi-stable),
# and that is correct, not a defect -- the same asymmetry
# core/rpm/indi-stable-3rdparty-libs.spec's own check-rpaths run already
# showed (only 3 of the bundled libraries ever carried RPATH). Asserting
# RUNPATH presence on a library that never needed one was this script's own
# mistake on the first run, not a packaging defect; ldd above is the check
# that actually applies uniformly.
readelf -d /opt/indi-stable/lib/libapogee.so.3 2>/dev/null | grep -q "RUNPATH.*opt/indi-stable/lib" \
  && pass "libapogee.so.3: RUNPATH into the private prefix survived the upgrade" \
  || fail "libapogee.so.3: RUNPATH missing or wrong after upgrade"

echo
echo "############ STEP 6: the distro binary is still a bystander ############"
if test -n "$DISTRO_SHA"; then
  test "$(sha256sum /usr/bin/indiserver | awk '{print $1}')" = "$DISTRO_SHA" \
    && pass "/usr/bin/indiserver unchanged across the upgrade" \
    || fail "/usr/bin/indiserver CHANGED across the upgrade"
  for p in indi-bin libindi1; do
    dpkg -V "$p" >/dev/null 2>&1 && pass "dpkg -V $p still clean" \
                                 || fail "dpkg -V $p now reports modifications"
  done
fi

echo
echo "############ STEP 7: full removal, then restore by diffing ############"
TO_REMOVE=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
              indi-stable-core indi-stable-core-libs indi-stable-core-dev $(pkg_names) 2>/dev/null \
            | awk '$1 ~ /^i/ {print $2}')
info "removing what is actually installed: $(echo "$TO_REMOVE" | wc -w) packages"
test -n "$TO_REMOVE" && apt-get remove -y --no-autoremove $TO_REMOVE >"$W/teardown.log" 2>&1

snapshot > "$W/after.txt"
ADDED=$(LC_ALL=C comm -13 "$BASELINE" "$W/after.txt")
GONE=$(LC_ALL=C comm -23 "$BASELINE" "$W/after.txt")
if test -n "$ADDED"; then
  echo "  packages this run ADDED and has not removed:"; echo "$ADDED" | sed 's/^/    /'
  apt-get remove -y --no-autoremove $(echo "$ADDED" | cut -f1) >>"$W/teardown.log" 2>&1
fi
if test -n "$GONE"; then
  echo "  packages this run REMOVED and has not restored:"; echo "$GONE" | sed 's/^/    /'
  apt-get install -y $(echo "$GONE" | cut -f1) >>"$W/teardown.log" 2>&1
fi

# Same control as core's own upgrade test: prove the added/removed
# comparison can actually see a planted difference before trusting its
# silence (LESSONS_LEARNED.md #1).
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
  diff "$BASELINE" "$W/final.txt" | sed 's/^/    /'
fi
test -e /opt/indi-stable && fail "/opt/indi-stable survived the teardown" \
                         || pass "/opt/indi-stable fully removed, even after an upgrade in between"

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "3RDPARTY-LIBS DEB UPGRADE PATH: ALL CHECKS PASSED"
else
  echo "3RDPARTY-LIBS DEB UPGRADE PATH: ONE OR MORE CHECKS FAILED"
fi
echo "  logs: $W"
echo "==================================================================="
exit "$FAIL"
