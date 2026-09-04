#!/bin/bash
#
# CI smoke test (RPM/Fedora side) for indi-stable-3rdparty-libs and
# -drivers, installed on top of indi-stable-core. The 3rdparty analogue of
# scripts/smoke-test-core.sh, and the same kind of gate: clean install into
# a fresh container, the shipped drivers resolve their libraries, a
# representative driver actually runs.
#
# Distinct from scripts/test-3rdparty-coexist-deb.sh and the test-upgrade-*
# harnesses, which assert against a specific, deliberately non-fresh VM
# baseline (a known package count, a distro INDI to coexist against). This
# script assumes NOTHING pre-exists, because the workflow only ever runs it
# inside a just-started container. There is no coexistence check here on
# purpose: a bare CI container carries no distro INDI to coexist against, so
# that question stays with the manual VM harnesses.
#
# Run as: bash scripts/smoke-test-3rdparty.sh <rpm-dir> [rpm-dir ...]
#
# Takes any number of directories and looks for all three package classes
# (core, -libs, -drivers) across all of them. They are genuinely separate in
# both places this runs: on fedoraastro core, -libs and -drivers sit in three
# different mock result directories, and in CI each build job uploads its own
# artifact, which download-artifact then unpacks into its own path. An
# earlier single-directory version of this script aborted on its first real
# run for exactly that reason.
#
set -u

test $# -ge 1 || { echo "usage: smoke-test-3rdparty.sh <rpm-dir> [rpm-dir ...]" >&2; exit 1; }
# Canonicalize before any path reaches dnf -- same defensive fix
# smoke-test-core-deb.sh needed for real against apt-get.
RPM_DIRS=()
for d in "$@"; do
  abs=$(cd "$d" 2>/dev/null && pwd) || { echo "ERROR: $d is not a directory" >&2; exit 1; }
  RPM_DIRS+=("$abs")
done

PREFIX=/opt/indi-stable
FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

echo "############ STEP 1: install core, then -libs and -drivers ############"
echo "  searching: ${RPM_DIRS[*]}"
# -devel/-dev packages are deliberately excluded: this gate answers "does a
# clean runtime install work", and pulling the headers in would also drag
# their own dependency web into a check that is not about building.
real_rpms() {   # $1 = glob
  local d
  for d in "${RPM_DIRS[@]}"; do ls "$d"/$1 2>/dev/null; done \
    | grep -v -e debuginfo -e debugsource -e '-devel-'
}

CORE_RPMS=$( { real_rpms 'indi-stable-core-2*.x86_64.rpm'; real_rpms 'indi-stable-core-libs-2*.x86_64.rpm'; } | sort -u)
LIBS_RPMS=$(real_rpms 'indi-stable-3rdparty-libs-*.x86_64.rpm' | sort -u)
DRV_RPMS=$( real_rpms 'indi-stable-3rdparty-drivers-*.x86_64.rpm' | sort -u)

test -n "$CORE_RPMS" || die "no indi-stable-core RPMs in ${RPM_DIRS[*]}"
test -n "$LIBS_RPMS" || die "no indi-stable-3rdparty-libs RPMs in ${RPM_DIRS[*]}"
test -n "$DRV_RPMS"  || die "no indi-stable-3rdparty-drivers RPMs in ${RPM_DIRS[*]}"

# Refuse to run if any package name is present at more than one version.
# The Debian twin of this script hit exactly that on ubuntuastro,
# 2026-09-04: a result directory holding both the upgrade test's "old" and
# "new" sides let the package manager pick the HIGHER version, which was the
# older pre-fix content (LESSONS_LEARNED.md #11), so the gate tested
# packaging nobody meant to test and still reported a clean install. The
# equivalent trap exists here -- fedoraastro deliberately keeps several
# mock-result-* directories whose contents share an NVR or differ only in
# Release. In CI each artifact directory holds one version, so this can only
# bite by hand.
DUPES=$(for f in $CORE_RPMS $LIBS_RPMS $DRV_RPMS; do
          rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE}\n' "$f" 2>/dev/null
        done | sort -u | awk '{print $1}' | sort | uniq -d)
if [ -n "$DUPES" ]; then
  echo "--- these package names were found at more than one version: ---" >&2
  printf '%s\n' "$DUPES" | sed 's/^/    /' >&2
  die "refusing to guess which build to test -- pass directories holding exactly one version of each package"
fi

# One transaction: -drivers BuildRequires/Requires -libs at an exact
# version-release, so installing them separately would only ever prove the
# dependency solver can be worked around.
# shellcheck disable=SC2086
dnf install -y $CORE_RPMS $LIBS_RPMS $DRV_RPMS || die "install failed"
pass "installed $(echo "$LIBS_RPMS" | wc -l) -libs and $(echo "$DRV_RPMS" | wc -l) -drivers packages on top of core"

echo "############ STEP 2: every shipped driver resolves its libraries ############"
# Driven by what the packages actually shipped (rpm -ql), not a hardcoded
# vendor list -- so adding a tenth vendor extends this check automatically
# rather than silently leaving it behind, the way the 8-to-9 fishcamp
# addition could have.
DRIVERS=$(rpm -ql $(rpm -qa 'indi-stable-3rdparty-drivers-*' | tr '\n' ' ') 2>/dev/null \
          | grep "^${PREFIX}/bin/" | sort -u)
test -n "$DRIVERS" || die "no driver binaries found under ${PREFIX}/bin from the -drivers packages"

CHECKED=0
FAIL_BEFORE_LOOP=$FAIL
for d in $DRIVERS; do
  test -x "$d" || { fail "$d is listed by rpm but not executable"; continue; }
  CHECKED=$((CHECKED + 1))
  LDD=$(ldd "$d" 2>&1)

  # A missing library is the failure that matters most: it means the driver
  # cannot load at all on a machine that has only our packages.
  if echo "$LDD" | grep -q 'not found'; then
    fail "$(basename "$d"): unresolved libraries:"
    echo "$LDD" | grep 'not found' | sed 's/^/        /'
    continue
  fi

  # Ours must resolve INTO the private prefix. In a bare container there is
  # no distro INDI to lose to, so this is not a coexistence test -- it is
  # the RPATH mechanism itself being confirmed to work, which is what makes
  # coexistence possible on a machine that does have one.
  STRAY=$(echo "$LDD" | grep -E '=> */' \
          | grep -E 'lib(indi[A-Za-z]*|apogee|ASICamera2|CAARotator|EAFFocuser|EFWFilter|USB2ST4Conv|fli|fishcamp|inovasdk|gxccd|PlayerOneCamera|PlayerOnePW|sbig|altaircam|bressercam|mallincam|meadecam|nncam|ogmacam|omegonprocam|starshootg|svbonycam|toupcam|tscam)\.so' \
          | grep -v "=> *${PREFIX}/" || true)
  if [ -n "$STRAY" ]; then
    fail "$(basename "$d"): one of our libraries resolved OUTSIDE ${PREFIX}:"
    echo "$STRAY" | sed 's/^/        /'
  fi
done
[ "$CHECKED" -gt 0 ] || die "checked no driver binaries at all -- the rpm -ql query found nothing executable"
# Only a PASS if nothing in the loop failed. An earlier version printed this
# unconditionally and reported "all libraries resolve" directly beneath 45
# FAIL lines saying otherwise -- caught on this script's first real run,
# 2026-09-04, on the same run that found the symlink defect it was reporting.
if [ "$FAIL" -eq "$FAIL_BEFORE_LOOP" ]; then
  pass "checked $CHECKED driver binaries; all libraries resolve, ours inside ${PREFIX}"
else
  echo "  ($CHECKED driver binaries checked; see the failures above)"
fi

echo "############ STEP 3: one driver from EVERY vendor actually executes ############"
# One driver per vendor package, not one driver overall. Every manual harness
# in this project used indi_apogee_ccd as "the representative driver", and
# that is precisely why the missing-runtime-symlink defect survived until
# 2026-09-04: apogee's blob carries a versioned SONAME and was never affected,
# while asi, micam and touptek were 100% broken. A per-vendor loop is what
# makes this gate able to see a defect confined to one vendor's blob.
#
# --help, not EOF-stdin: run with no args and stdin closed, an INDI driver
# just prints "<name>: EOF" and exits with no banner at all -- a real defect
# in smoke-test-core.sh, caught by running it rather than reasoning about it
# (DESIGN.md, "Release automation, v1").
#
# The assertion is "it got past the dynamic loader and ran its own code", NOT
# "it printed Usage:". Confirmed by running them, 2026-09-04: indi_apogee_ccd
# and indi_mi_ccd print a Usage: banner, but indi_toupcam_ccd and indi_asi_ccd
# print "HotPlugManager: ... initialized." instead, because they set up a
# hotplug handler before parsing argv. Requiring "^Usage:" here would fail
# two working vendors.
for pkg in $(rpm -qa 'indi-stable-3rdparty-drivers-*' | sort); do
  vendor=${pkg#indi-stable-3rdparty-drivers-}; vendor=${vendor%%-2.*}
  bin=$(rpm -ql "$pkg" | grep "^${PREFIX}/bin/" | head -1)
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
