#!/bin/bash
#
# CI smoke test (Debian/Ubuntu side) for indi-stable-3rdparty-libs and
# -drivers, installed on top of indi-stable-core. The Debian twin of
# scripts/smoke-test-3rdparty.sh -- same gate, same reasoning: a fresh CI
# container, not a snapshotted VM, so no baseline or coexistence assertions
# here. See that script's header for the full explanation.
#
# Run as: sudo bash scripts/smoke-test-3rdparty-deb.sh <deb-dir> [deb-dir ...]
#
# Takes any number of directories, because core, -libs and -drivers are
# genuinely separate in both places this runs: three build jobs uploading
# three artifacts in CI, and separate result directories by hand.
#
set -u

test $# -ge 1 || { echo "usage: smoke-test-3rdparty-deb.sh <deb-dir> [deb-dir ...]" >&2; exit 1; }
# Canonicalize before any path reaches apt-get. Confirmed necessary for real
# on a CI run, 2026-08-27: a relative path resolves fine in the script's own
# variables but apt-get then reports "Unable to locate package <dir>",
# consistent with it falling back to PACKAGE/RELEASE pin syntax when it does
# not recognize the argument as a file. See smoke-test-core-deb.sh.
DEB_DIRS=()
for d in "$@"; do
  abs=$(cd "$d" 2>/dev/null && pwd) || { echo "ERROR: $d is not a directory" >&2; exit 1; }
  DEB_DIRS+=("$abs")
done

PREFIX=/opt/indi-stable
FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

echo "############ STEP 1: install core, then -libs and -drivers ############"
echo "  searching: ${DEB_DIRS[*]}"
# -dev packages are deliberately excluded: this gate answers "does a clean
# RUNTIME install work". That exclusion is not incidental here -- it is the
# whole point. Shipping a vendor blob's unversioned .so symlink in -dev left
# 45 of 56 drivers unable to load on a runtime-only install, and a gate that
# installed -dev "to be safe" would have supplied the missing symlink itself
# and reported the broken packaging as clean. See LESSONS_LEARNED.md #22.
real_debs() {   # $1 = glob
  local d
  for d in "${DEB_DIRS[@]}"; do ls "$d"/$1 2>/dev/null; done | grep -v -e '-dev_' -e 'ddeb$'
}

CORE_DEBS=$( { real_debs 'indi-stable-core_*.deb'; real_debs 'indi-stable-core-libs_*.deb'; } | sort -u)
LIBS_DEBS=$(real_debs 'indi-stable-3rdparty-libs-*.deb' | sort -u)
DRV_DEBS=$( real_debs 'indi-stable-3rdparty-drivers-*.deb' | sort -u)

test -n "$CORE_DEBS" || die "no indi-stable-core .debs in ${DEB_DIRS[*]}"
test -n "$LIBS_DEBS" || die "no indi-stable-3rdparty-libs .debs in ${DEB_DIRS[*]}"
test -n "$DRV_DEBS"  || die "no indi-stable-3rdparty-drivers .debs in ${DEB_DIRS[*]}"

# Refuse to run if any package name is present at more than one version.
# Found the hard way on ubuntuastro, 2026-09-04: ~/build holds both a -1 and
# a -2 revision of every 3rdparty package (the upgrade test's two sides), so
# this script handed apt all 34, apt installed the HIGHER revision, and the
# -2 set is the older pre-fix build -- a higher version carrying older
# content, exactly the trap LESSONS_LEARNED.md #11 records. The gate then
# tested packaging nobody meant to test and reported a clean install of
# "17 -libs" where nine exist. In CI each artifact directory holds exactly
# one version, so this can only bite by hand -- which is precisely when
# nobody is watching the package count.
DUPES=$(for f in $CORE_DEBS $LIBS_DEBS $DRV_DEBS; do
          dpkg-deb -f "$f" Package Version 2>/dev/null | paste -sd' ' -
        done | sort -u | awk '{print $2}' | sort | uniq -d)
if [ -n "$DUPES" ]; then
  echo "--- these package names were found at more than one version: ---" >&2
  printf '%s\n' "$DUPES" | sed 's/^/    /' >&2
  die "refusing to guess which build to test -- pass a directory holding exactly one version of each package"
fi

# One transaction: -drivers Depends on -libs at an exact version, so
# installing them separately would only prove the solver can be worked around.
# shellcheck disable=SC2086
apt-get install -y $CORE_DEBS $LIBS_DEBS $DRV_DEBS || die "install failed"
pass "installed $(echo "$LIBS_DEBS" | wc -l) -libs and $(echo "$DRV_DEBS" | wc -l) -drivers packages on top of core"

echo "############ STEP 2: every shipped driver resolves its libraries ############"
# Driven by what the packages actually shipped (dpkg -L), not a hardcoded
# vendor list, so a tenth vendor extends this check automatically.
DRV_PKGS=$(dpkg-query -W -f='${Package}\n' 'indi-stable-3rdparty-drivers-*' 2>/dev/null)
test -n "$DRV_PKGS" || die "no installed indi-stable-3rdparty-drivers-* packages found"
# shellcheck disable=SC2086
DRIVERS=$(dpkg -L $DRV_PKGS 2>/dev/null | grep "^${PREFIX}/bin/" | sort -u)
test -n "$DRIVERS" || die "no driver binaries found under ${PREFIX}/bin from the -drivers packages"

CHECKED=0
FAIL_BEFORE_LOOP=$FAIL
for d in $DRIVERS; do
  test -x "$d" || continue
  CHECKED=$((CHECKED + 1))
  LDD=$(ldd "$d" 2>&1)

  if echo "$LDD" | grep -q 'not found'; then
    fail "$(basename "$d"): unresolved libraries:"
    echo "$LDD" | grep 'not found' | sed 's/^/        /'
    continue
  fi

  # Ours must resolve INTO the private prefix. In a bare container there is
  # no distro INDI to lose to, so this is not a coexistence test -- it is the
  # RPATH mechanism itself being confirmed, which is what makes coexistence
  # possible on a machine that does have one.
  STRAY=$(echo "$LDD" | grep -E '=> */' \
          | grep -E 'lib(indi[A-Za-z]*|apogee|ASICamera2|CAARotator|EAFFocuser|EFWFilter|USB2ST4Conv|fli|fishcamp|inovasdk|gxccd|PlayerOneCamera|PlayerOnePW|sbig|altaircam|bressercam|mallincam|meadecam|nncam|ogmacam|omegonprocam|starshootg|svbonycam|toupcam|tscam)\.so' \
          | grep -v "=> *${PREFIX}/" || true)
  if [ -n "$STRAY" ]; then
    fail "$(basename "$d"): one of our libraries resolved OUTSIDE ${PREFIX}:"
    echo "$STRAY" | sed 's/^/        /'
  fi
done
[ "$CHECKED" -gt 0 ] || die "checked no driver binaries at all -- the dpkg -L query found nothing executable"
if [ "$FAIL" -eq "$FAIL_BEFORE_LOOP" ]; then
  pass "checked $CHECKED driver binaries; all libraries resolve, ours inside ${PREFIX}"
else
  echo "  ($CHECKED driver binaries checked; see the failures above)"
fi

echo "############ STEP 3: one driver from EVERY vendor actually executes ############"
# One driver per vendor, not one overall -- see smoke-test-3rdparty.sh's own
# comment and LESSONS_LEARNED.md #22 for why a single "representative driver"
# is exactly how a per-vendor fault stays invisible.
#
# Asserts the driver got past the dynamic loader and ran its own code, NOT
# that it printed "Usage:": only 4 of the 9 vendors do that -- asi, playerone
# and touptek print "HotPlugManager: ... initialized." and sbig prints
# "OpenDriver: ...", all working. Confirmed by running them, 2026-09-04.
for pkg in $(echo "$DRV_PKGS" | sort); do
  vendor=${pkg#indi-stable-3rdparty-drivers-}
  bin=$(dpkg -L "$pkg" 2>/dev/null | grep "^${PREFIX}/bin/" | head -1)
  [ -n "$bin" ] && [ -x "$bin" ] || { fail "$vendor: no executable driver found in $pkg"; continue; }

  OUT=$(timeout 10 "$bin" --help 2>&1); RC=$?
  if echo "$OUT" | grep -qi 'error while loading shared libraries\|cannot open shared object'; then
    fail "$vendor: $(basename "$bin") died in the dynamic loader:"
    echo "$OUT" | head -2 | sed 's/^/        /'
  elif [ -z "$OUT" ]; then
    fail "$vendor: $(basename "$bin") --help produced no output at all (rc=$RC)"
  else
    pass "$vendor: $(basename "$bin") ran -- $(echo "$OUT" | head -1 | cut -c1-60)"
  fi
done

echo
if [ $FAIL -eq 0 ]; then
  echo "############ SMOKE TEST: ALL CHECKS PASSED ############"
else
  echo "############ SMOKE TEST: ONE OR MORE CHECKS FAILED ############"
fi
exit $FAIL
