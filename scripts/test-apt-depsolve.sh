#!/bin/bash
#
# apt/dpkg depsolve test -- does the package manager still pull in the
# DISTRIBUTION's INDI when ours is installed?
#
# DEBIAN.md, "The equivalent of the tests that mattered" #1. The Fedora
# analogue is scripts/test-snapshot-a-depsolve.sh: same question, different
# mechanism, and LESSONS_LEARNED.md #12 is why the Fedora pass cannot be
# inherited.
#
# WHY THIS IS NOT A STRAIGHT PORT
#
# On Fedora the hazard is a SONAME Provides. rpm advertises
# libindiclient.so.2()(64bit) for every shared library a package ships, so dnf
# may satisfy any consumer from whichever package claims that name, and
# %__provides_exclude_from is what keeps ours from claiming it. stellarium is
# the probe there because it depends on that soname ALONE.
#
# dpkg has no soname-level dependencies whatsoever. Every Depends: names a
# PACKAGE, and that package name is baked into the consumer's control file at
# the CONSUMER's build time, chosen by dpkg-shlibdeps from the .shlibs file of
# whichever installed package owns the library. Ours could therefore shadow the
# distribution only by shipping a shlibs file or a Provides:, and core/deb/rules
# prevents the first by overriding dh_makeshlibs with an EMPTY body.
#
# That difference moves the test, and moving it is the whole point: no apt
# transaction can pick ours by soname, because apt cannot see sonames. An
# apt-only check would therefore pass on a box where the guarantee had been
# thrown away completely -- a check that cannot fail (LESSONS_LEARNED.md #12).
# So this script measures both layers and labels which is which:
#
#   STEP 2  the metadata inside OUR .debs -- no shlibs, no symbols, no
#           Provides. Read out of the .deb artifacts, not from an installed
#           state (LESSONS_LEARNED.md #2).
#           CONTROL: the identical pipeline over the distribution's libindi1
#           .deb, which MUST report a shlibs file. If it does not, the
#           pipeline is broken rather than the subject clean
#           (LESSONS_LEARNED.md #1).
#   STEP 5  what apt actually DOES -- with ours installed and the
#           distribution's INDI removed, installing a consumer must bring
#           libindi1 back.
#           CONTROL: a scratch package declaring Provides: libindi1 must make
#           apt stop needing libindi1. That is the defect this step exists to
#           catch, so seeing the step's own verdict flip proves it could catch
#           it (LESSONS_LEARNED.md #15).
#
# Run as: sudo bash scripts/test-apt-depsolve.sh [deb-dir]
#
# Standing rules for root-run tests: absolute paths, never ~ (#4); assert the
# setup landed before measuring it (#5); restore by measuring what changed
# rather than by naming it (#6).
#
set -u

BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)
D=${1:-$HOMEDIR/build}
W=$(mktemp -d /tmp/apt-depsolve.XXXXXX)

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; echo "  work dir kept: $W"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

# Package-name-and-version snapshot. Stronger than `dpkg -l | wc -l`: a
# removal balanced by an install would keep a count identical.
#
# LC_ALL=C is not tidiness. GNU comm compares lines byte by byte, while sort
# under a UTF-8 locale collates by dictionary rules that ignore punctuation --
# so `sort` output that comm then rejects as unsorted is the DEFAULT, not an
# edge case. The first run of this script hit exactly that: comm printed
# "file 1 is not in sorted order" and named two packages as left behind that
# the teardown had already removed. The box was fine; the check was lying.
snapshot() { dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort; }

echo "############ STEP 0: preconditions ############"
test "$(id -u)" -eq 0 || die "run under sudo -- this installs and removes packages"

# Anchored on the '_' that separates name from version, and on _amd64.deb so
# the .ddeb debug packages sitting in the same directory cannot match
# (LESSONS_LEARNED.md #3).
OUR_MAIN=$(ls "$D"/indi-stable-core_*_amd64.deb 2>/dev/null | head -1)
OUR_LIBS=$(ls "$D"/indi-stable-core-libs_*_amd64.deb 2>/dev/null | head -1)
OUR_DEV=$(ls  "$D"/indi-stable-core-dev_*_amd64.deb  2>/dev/null | head -1)
test -f "$OUR_MAIN" || die "no indi-stable-core_*_amd64.deb under $D -- build first (DEBIAN.md)"
test -f "$OUR_LIBS" || die "no indi-stable-core-libs_*_amd64.deb under $D"
test -f "$OUR_DEV"  || die "no indi-stable-core-dev_*_amd64.deb under $D"
echo "  our .debs:"
for f in "$OUR_MAIN" "$OUR_LIBS" "$OUR_DEV"; do echo "    $(basename "$f")"; done

# Configuration B, not A. On configuration A the distribution ships
# libindiclient.so.1 and no question here has teeth (DEBIAN.md, "So test two
# configurations").
dpkg -s libindi1 >/dev/null 2>&1 || die "libindi1 is not installed -- this is not configuration B"
DISTRO_VER=$(dpkg-query -W -f='${Version}' libindi1)
case $DISTRO_VER in
  2.*) info "distro libindi1 $DISTRO_VER" ;;
  *)   die "libindi1 is $DISTRO_VER, not a 2.x -- its soname will not collide with ours, so this box cannot fail the test (DEBIAN.md, configuration A)" ;;
esac
dpkg -s indi-bin >/dev/null 2>&1 || die "indi-bin is not installed -- it is STEP 5's consumer"
dpkg -s indi-stable-core >/dev/null 2>&1 && die "ours is ALREADY installed -- this test must start from the distribution-only state"
test -e /opt/indi-stable && die "/opt/indi-stable exists before we installed anything -- clean it first"
pass "configuration B, ours absent"

BASELINE=$W/baseline.txt
snapshot > "$BASELINE"
info "baseline: $(wc -l < "$BASELINE") packages recorded"

echo
echo "############ STEP 1: can the distribution's INDI be restored? ############"
# Asked BEFORE anything is removed. STEP 5 has to take the distribution's INDI
# away, and this box has no snapshot to fall back on (STATUS.md, machine
# state), so proving the .debs are already on disk is a precondition, not a
# formality. --download-only fills /var/cache/apt/archives.
apt-get install -y --download-only --reinstall indi-bin libindi1 libindi-dev >"$W/download.log" 2>&1 \
  || { tail -20 "$W/download.log"; die "could not pre-download the distribution's INDI -- refusing to remove what cannot be put back"; }
pass "indi-bin, libindi1, libindi-dev are in the apt cache and can be reinstalled offline"

echo
echo "############ STEP 2: the metadata in OUR .debs ############"
# The layer apt cannot show you, and the one core/deb/rules actually defends.
# dpkg-deb --control unpacks the control archive; the question is what is IN it.
check_control() {   # $1 label, $2 path to .deb, $3 expect-shlibs yes|no
  local label=$1 deb=$2 expect=$3 dir members prov
  dir=$W/ctl-$(basename "$deb" .deb)
  rm -rf "$dir"
  dpkg-deb --control "$deb" "$dir" >/dev/null 2>&1 \
    || { fail "$label: could not unpack the control archive"; return; }
  members=$(ls "$dir" | tr '\n' ' ')
  info "$label control archive: $members"
  prov=$(grep -c '^Provides:' "$dir/control")
  if ls "$dir" | grep -qxE 'shlibs|symbols'; then
    if test "$expect" = yes; then
      ctl "$label SHIPS $(ls "$dir" | grep -xE 'shlibs|symbols' | tr '\n' ' ')-- so this check can see one when it is there"
      grep -E 'libindi' "$dir"/shlibs 2>/dev/null | sed 's/^/        /'
    else
      fail "$label ships a shlibs/symbols file -- it now advertises itself as a system-wide provider of libindiclient.so.2, which is the shadowing this project exists to prevent"
    fi
  else
    if test "$expect" = yes; then
      fail "CONTROL BROKEN: $label has NO shlibs file, but the distribution's library package must have one. The check above is finding nothing because it cannot look, not because ours is clean"
    else
      pass "$label ships no shlibs and no symbols file"
    fi
  fi
  if test "$expect" = no; then
    test "$prov" -eq 0 \
      && pass "$label declares no Provides:" \
      || fail "$label declares $(grep '^Provides:' "$dir/control") -- apt could satisfy a distribution dependency from ours"
  fi
}
check_control "indi-stable-core     " "$OUR_MAIN" no
check_control "indi-stable-core-libs" "$OUR_LIBS" no
check_control "indi-stable-core-dev " "$OUR_DEV"  no

echo "  -- CONTROL: the same pipeline over the distribution's own library package --"
( cd "$W" && apt-get download libindi1 >/dev/null 2>&1 )
DISTRO_DEB=$(ls "$W"/libindi1_*_amd64.deb 2>/dev/null | head -1)
if test -f "$DISTRO_DEB"; then
  check_control "libindi1             " "$DISTRO_DEB" yes
else
  fail "could not download libindi1.deb -- STEP 2 has no positive control and its passes mean nothing"
fi

echo
echo "############ STEP 3: install ours ############"
apt-get install -y "$OUR_LIBS" "$OUR_MAIN" >"$W/install.log" 2>&1 \
  || { tail -20 "$W/install.log"; die "installing our packages failed"; }
dpkg -s indi-stable-core >/dev/null 2>&1 || die "indi-stable-core is not installed after the install"
test -d /opt/indi-stable || die "/opt/indi-stable missing after install"
pass "ours is genuinely installed -- the test now has a subject"
info "installed: $(dpkg-query -W -f='${Package} ${Version}' indi-stable-core), $(dpkg-query -W -f='${Package} ${Version}' indi-stable-core-libs)"

echo
echo "############ STEP 4: the distribution's INDI is still there and still needed ############"
dpkg -s libindi1 >/dev/null 2>&1 \
  && pass "libindi1 survived installing ours" \
  || fail "libindi1 was REMOVED by installing ours -- a conflict this project must never have"
dpkg -s indi-bin >/dev/null 2>&1 \
  && pass "indi-bin survived -- kstars depends on it" \
  || fail "indi-bin was removed by installing ours"
info "apt's view of what would satisfy indi-bin now:"
apt-cache depends indi-bin 2>/dev/null | grep -iE 'libindi' | sed 's/^/        /'

echo
echo "############ STEP 5: THE DEPSOLVE QUESTION ############"
echo "   Remove the distribution's INDI with ours left installed, then ask apt"
echo "   for a consumer. libindi1 MUST come back."
apt-get remove -y --no-autoremove libindi1 >"$W/remove-distro.log" 2>&1 \
  || { tail -20 "$W/remove-distro.log"; die "could not remove the distribution's INDI"; }
dpkg -s libindi1 >/dev/null 2>&1 && die "libindi1 is still installed after the removal -- STEP 5 would measure nothing"
dpkg -s indi-bin >/dev/null 2>&1 && die "indi-bin is still installed -- it should have gone with libindi1"
pass "distribution INDI removed; ours still installed: $(dpkg-query -W -f='${Version}' indi-stable-core)"
test -d /opt/indi-stable || fail "/opt/indi-stable vanished when the distribution's INDI was removed"

echo "  asking apt to install indi-bin ..."
apt-get install -y indi-bin >"$W/reinstall.log" 2>&1 \
  || { tail -20 "$W/reinstall.log"; die "installing indi-bin failed"; }
if dpkg -s libindi1 >/dev/null 2>&1; then
  pass "apt pulled the DISTRIBUTION's libindi1 back in, despite ours being present"
  info "$(dpkg-query -W -f='${Package} ${Version}' libindi1)"
else
  fail "apt satisfied indi-bin WITHOUT libindi1 -- something of ours is standing in for the distribution's library"
fi

echo
echo "############ STEP 6: CONTROL -- can STEP 5 detect a shadowing package? ############"
# STEP 5 passes by observing a package APPEAR. If a Provides: could not change
# that outcome, the step would pass on a box where the guarantee was gone.
# Build the defect deliberately and confirm the verdict flips.
mkdir -p "$W/broken/DEBIAN"
cat > "$W/broken/DEBIAN/control" <<CTL
Package: indi-stable-core-shadow-control
Version: 0.0
Architecture: amd64
Maintainer: test harness <root@localhost>
Provides: libindi1
Description: Scratch package for scripts/test-apt-depsolve.sh STEP 6
 Declares the Provides: our real packages must never declare, so that STEP 5
 can be shown able to detect it. Removed again before this script exits.
CTL
dpkg-deb -b "$W/broken" "$W/shadow-control.deb" >/dev/null 2>&1 \
  || fail "could not build the scratch shadowing package -- STEP 5 keeps no positive control"
if test -f "$W/shadow-control.deb"; then
  apt-get remove -y --no-autoremove libindi1 >>"$W/remove-distro.log" 2>&1
  dpkg -s libindi1 >/dev/null 2>&1 && die "could not take libindi1 away again for the control"
  apt-get install -y "$W/shadow-control.deb" >"$W/shadow.log" 2>&1 \
    || { tail -10 "$W/shadow.log"; fail "could not install the scratch shadowing package"; }
  if dpkg -s indi-stable-core-shadow-control >/dev/null 2>&1; then
    SIM=$(apt-get install -s indi-bin 2>&1)
    echo "$SIM" | grep -E '^(Inst|Conf) libindi1' | sed 's/^/        /'
    if echo "$SIM" | grep -qE '^Inst libindi1'; then
      fail "CONTROL: apt STILL wants libindi1 even against a package that Provides: it -- STEP 5's pass proves nothing, because its outcome does not depend on the metadata"
    else
      ctl "apt no longer needs libindi1 once something Provides: it -- STEP 5's verdict does depend on the metadata, so its PASS above was a real result"
    fi
    apt-get remove -y --no-autoremove indi-stable-core-shadow-control >>"$W/shadow.log" 2>&1
    dpkg -s indi-stable-core-shadow-control >/dev/null 2>&1 \
      && fail "the scratch shadowing package is STILL INSTALLED -- remove it by hand: apt-get remove indi-stable-core-shadow-control"
  fi
fi

echo
echo "############ STEP 7: restore, by diffing rather than by naming ############"
# LESSONS_LEARNED.md #6: remove what the run OBSERVED itself adding, not what
# was predicted. The prediction was wrong the first time it was trusted.
# Only what is actually installed may be named. `apt-get remove a b c` aborts
# the WHOLE transaction with "E: Unable to locate package c" if c is neither
# installed nor in any repository -- and our .debs are local files, so once
# they are gone apt has never heard of the names. The first run of this script
# named indi-stable-core-dev unconditionally, apt removed NOTHING, and only the
# measured diff below noticed. That is LESSONS_LEARNED.md #6 earning its keep
# in a place the author had not predicted, so the named list is now derived
# from the dpkg database rather than written out.
TO_REMOVE=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
              indi-stable-core indi-stable-core-libs indi-stable-core-dev 2>/dev/null \
            | awk '$1 ~ /^i/ {print $2}')
info "removing what is actually installed: ${TO_REMOVE:-(nothing)}"
test -n "$TO_REMOVE" && apt-get remove -y --no-autoremove $TO_REMOVE >"$W/teardown.log" 2>&1
apt-get install -y indi-bin libindi1 libindi-dev >>"$W/teardown.log" 2>&1

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

snapshot > "$W/final.txt"

# The comparison above passes by producing NO output, so it has to be shown
# able to produce some (LESSONS_LEARNED.md #1). Perturb a copy of the baseline
# and confirm the identical pipeline names the perturbation. This control is
# why the locale bug in snapshot() was caught rather than shipped: an unsorted
# comm is silent about real differences too.
{ printf 'zzz-not-a-real-package\t9.9\n'; cat "$BASELINE"; } | LC_ALL=C sort > "$W/perturbed.txt"
SEEN=$(LC_ALL=C comm -13 "$BASELINE" "$W/perturbed.txt" | cut -f1)
test "$SEEN" = "zzz-not-a-real-package" \
  && ctl "the added/removed comparison reports a planted difference ($SEEN), so its silence above is a real result" \
  || fail "CONTROL BROKEN: the comparison did not report a planted package (got '${SEEN:-nothing}') -- STEP 7 cannot see drift and its PASS means nothing"

if diff -q "$BASELINE" "$W/final.txt" >/dev/null; then
  pass "the package set matches the baseline exactly ($(wc -l < "$W/final.txt") packages)"
else
  fail "the box does NOT match its baseline -- differences follow"
  diff "$BASELINE" "$W/final.txt" | sed 's/^/        /'
fi
test -e /opt/indi-stable \
  && fail "/opt/indi-stable survived the teardown" \
  || pass "/opt/indi-stable is gone"
readlink -e /usr/bin/indiserver-stable >/dev/null 2>&1 \
  && fail "/usr/bin/indiserver-stable still resolves after teardown" \
  || pass "no indiserver-stable alternative left behind"

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "APT DEPSOLVE: ALL CHECKS PASSED"
else
  echo "APT DEPSOLVE: ONE OR MORE CHECKS FAILED"
fi
echo "  logs: $W"
echo "==================================================================="
exit "$FAIL"
