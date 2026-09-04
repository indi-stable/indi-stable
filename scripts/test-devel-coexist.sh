#!/bin/bash
#
# The devel subpackage installed alongside the distribution's libindi-devel.
#
# This is the last install path never exercised on any machine. Items 1-6 of
# the FEDORA.md checklist look at the runtime packages; the -devel subpackage
# has only ever been inspected as a file, never installed.
#
# What makes it worth its own test: headers and .pc files are resolved by
# SEARCH ORDER, not by SONAME. /usr/include wins the compiler search order and
# /usr/lib64/pkgconfig wins pkg-config's, so a single leaked header or .pc file
# would silently take precedence over the distribution's -- and both packages
# ship a module named exactly `libindi`:
#
#     ours    /opt/indi-stable/lib/pkgconfig/libindi.pc
#     distro  /usr/lib64/pkgconfig/libindi.pc
#
# Run as: sudo bash scripts/test-devel-coexist.sh [resultdir]
#
# The standing rules for a root-run test in this project
# (LESSONS_LEARNED.md #4, #5, #1):
#   1. Absolute paths -- under sudo HOME is /root.
#   2. Assert each setup step landed before measuring it.
#   3. Where a step passes by finding NOTHING, prove the machinery could have
#      found something. Positive controls are marked CONTROL.
#
# It does NOT spend the VM's snapshot: no compiler and no build dependencies
# are pulled in, so the "this host has no gcc" property that makes every
# untouched-distro result on this box mean anything survives. STEP 9 asserts
# that rather than trusting it. Measured on the first real run, the transaction
# adds five packages -- libindi-devel, libindi-static and libindi-qt for the
# distribution, and erfa for ours -- and STEP 10 removes whatever it finds it
# added rather than a list written in advance.
#
# On success it puts the box back to the Snapshot B baseline. On failure it
# leaves everything installed for inspection and prints the cleanup command.
#
set -u

test "$(id -u)" -eq 0 || { echo "*** ABORT: must run as root (sudo bash $0) ***"; exit 1; }

BUILD_USER=${SUDO_USER:-$(id -un)}
BUILD_HOME=$(getent passwd "$BUILD_USER" | cut -d: -f6)
R=${1:-$BUILD_HOME/mock-result}
W=$(mktemp -d /tmp/devel-coexist.XXXXXX)

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }

echo "############ STEP 0: preconditions ############"
echo "  RPMs from: $R   (real user: $BUILD_USER)"

# Anchored on .x86_64.rpm, not on a prefix -- a mock resultdir keeps the
# .src.rpm beside the binaries (LESSONS_LEARNED.md #3).
OURS_DEVEL=$(ls "$R"/indi-stable-core-devel-2*.x86_64.rpm 2>/dev/null | head -1)
OURS_LIBS=$(ls "$R"/indi-stable-core-libs-2*.x86_64.rpm 2>/dev/null | grep -v debuginfo | head -1)
test -f "$OURS_DEVEL" || die "no indi-stable-core-devel-*.x86_64.rpm under $R -- build it first (FEDORA.md)"
test -f "$OURS_LIBS"  || die "no indi-stable-core-libs-*.x86_64.rpm under $R -- -devel requires it"
echo "  ours:   $(basename "$OURS_DEVEL")"
echo "          $(basename "$OURS_LIBS")"

rpm -q libindi >/dev/null 2>&1 \
  || die "distro 'libindi' is NOT installed -- this test needs the configuration it protects"
rpm -q libindi-devel >/dev/null 2>&1 \
  && die "'libindi-devel' is ALREADY installed -- this test installs it itself and removes it again; a pre-existing copy would be removed from under you"
rpm -qa 'indi-stable-*' | grep -q . \
  && die "one of ours is ALREADY installed -- must start from the distro-only state: $(rpm -qa 'indi-stable-*' | tr '\n' ' ')"
test -e /opt/indi-stable \
  && die "/opt/indi-stable exists but no package owns it -- clean it up before measuring"
echo "  OK: distro libindi present, libindi-devel absent, ours absent."

HAD_GCC=no; command -v gcc >/dev/null 2>&1 && HAD_GCC=yes
echo "  gcc on this host at start: $HAD_GCC"

# The baseline this run must be restored to. Recorded rather than assumed:
# the cleanup below removes exactly what the run added, because a hardcoded
# removal list cannot know what the depsolver decided to pull in.
rpm -qa --qf '%{NAME}\n' | sort > "$W/pkgs-before.txt"
test -s "$W/pkgs-before.txt" || die "could not record the installed package set"
echo "  baseline: $(wc -l < "$W/pkgs-before.txt") packages installed"

echo
echo "############ STEP 1: install the DISTRO -devel, alone ############"
dnf install -y libindi-devel || die "installing libindi-devel failed"
rpm -q libindi-devel >/dev/null 2>&1 || die "libindi-devel still not installed after dnf reported success"
echo "  added: $(rpm -q libindi-devel libindi-static 2>&1 | tr '\n' ' ')"

# Fingerprint every file it owns, by content. This is the artifact, not a log
# (LESSONS_LEARNED.md #2) -- rpm -V is checked separately below.
rpm -ql libindi-devel | sort > "$W/distro-files.txt"
# Split the payload by type first. sha256sum cannot hash a directory, and a
# bare "127 of 135" would leave it to the reader to assume the other 8 were
# harmless -- so classify them and fail on anything that is neither.
: > "$W/distro-regular.txt"; : > "$W/distro-dirs.txt"; : > "$W/distro-other.txt"
while IFS= read -r f; do
  if   test -f "$f"; then echo "$f" >> "$W/distro-regular.txt"
  elif test -d "$f"; then echo "$f" >> "$W/distro-dirs.txt"
  else                    echo "$f" >> "$W/distro-other.txt"; fi
done < "$W/distro-files.txt"
test -s "$W/distro-other.txt" && { fail "libindi-devel ships paths that are neither file nor directory:"; cat "$W/distro-other.txt"; }
xargs -a "$W/distro-regular.txt" -d '\n' sha256sum | sort -k2 > "$W/distro-sha-before.txt" \
  || die "hashing the distro payload failed -- every comparison below would be vacuous"
test "$(wc -l < "$W/distro-sha-before.txt")" -eq "$(wc -l < "$W/distro-regular.txt")" \
  || die "hashed fewer files than exist -- the measurement is incomplete"
echo "  fingerprinted $(wc -l < "$W/distro-sha-before.txt") regular files by sha256;" \
     "$(wc -l < "$W/distro-dirs.txt") of the $(wc -l < "$W/distro-files.txt") paths are directories"

echo
echo "############ STEP 2: CONTROL -- show rpm -V can actually fail ############"
# A `rpm -V` that exits 0 is the central claim of this test, and it passes by
# printing nothing. Perturb one distro file reversibly and confirm rpm -V
# notices, then restore it. Done BEFORE ours is installed so it can never be
# confused with an effect of ours.
CF=/usr/include/libindi/indidevapi.h
test -f "$CF" || die "control file $CF missing from libindi-devel"
CF_MODE=$(stat -c %a "$CF") || die "could not read mode of $CF"
rpm -V libindi-devel || die "libindi-devel is ALREADY modified before we touched it -- the control below could not distinguish our perturbation from that"
chmod 600 "$CF"
if rpm -V libindi-devel | grep -q "$CF"; then
  ctl "rpm -V reported the perturbed $CF -- the check can fail"
else
  fail "rpm -V did NOT notice a chmod on $CF -- every rpm -V result below is meaningless"
fi
chmod "$CF_MODE" "$CF"
test "$(stat -c %a "$CF")" = "$CF_MODE" || die "FAILED TO RESTORE $CF to mode $CF_MODE -- fix by hand before continuing"
if rpm -V libindi-devel; then
  ctl "restored to mode $CF_MODE; rpm -V clean again"
else
  fail "rpm -V still dirty after restoring $CF -- the box is not back to baseline"
fi

echo
echo "############ STEP 3: install OURS alongside, in one transaction ############"
# One transaction on purpose: rpm's file-conflict detection runs across the
# whole transaction, so this is the strongest form of the question.
dnf install -y "$OURS_LIBS" "$OURS_DEVEL" || die "installing ours alongside libindi-devel failed -- if rpm reported file conflicts, that IS the finding"
rpm -q indi-stable-core-devel >/dev/null 2>&1 || die "indi-stable-core-devel not installed after dnf reported success"
rpm -q indi-stable-core-libs  >/dev/null 2>&1 || die "indi-stable-core-libs not installed after dnf reported success"
test -d /opt/indi-stable/include/libindi || die "/opt/indi-stable/include/libindi absent -- the install did not land where the test expects"
echo "  installed: $(rpm -qa 'indi-stable-*' | tr '\n' ' ')"

echo
echo "############ STEP 4: is the distribution's -devel untouched? ############"
if rpm -V libindi-devel; then pass "rpm -V libindi-devel clean"; else fail "rpm -V libindi-devel reported changes (above)"; fi
if rpm -V libindi-libs;  then pass "rpm -V libindi-libs clean";  else fail "rpm -V libindi-libs reported changes (above)"; fi
if rpm -V libindi;       then pass "rpm -V libindi clean";       else fail "rpm -V libindi reported changes (above)"; fi

xargs -a "$W/distro-regular.txt" -d '\n' sha256sum | sort -k2 > "$W/distro-sha-after.txt"
test -s "$W/distro-sha-after.txt" || die "re-fingerprint produced nothing -- cannot conclude anything"
if diff -u "$W/distro-sha-before.txt" "$W/distro-sha-after.txt" > "$W/sha.diff"; then
  pass "all $(wc -l < "$W/distro-sha-after.txt") distro -devel regular files byte-identical to before"
else
  fail "distro -devel file contents CHANGED:"; sed -n 1,40p "$W/sha.diff"
fi
# CONTROL for the comparator itself, on a scratch copy -- the box is untouched.
sed '1s/^./0/' "$W/distro-sha-before.txt" > "$W/distro-sha-mutated.txt"
if diff -q "$W/distro-sha-before.txt" "$W/distro-sha-mutated.txt" >/dev/null; then
  fail "the sha comparator does not notice a changed digest -- the PASS above is worthless"
else
  ctl "sha comparator flags a one-character difference"
fi

echo
echo "############ STEP 5: who owns the header the compiler will find? ############"
for h in /usr/include/libindi/indidevapi.h /usr/include/libindi/indiapi.h; do
  test -f "$h" || { fail "$h missing"; continue; }
  OWNER=$(rpm -qf "$h")
  case $OWNER in
    libindi-devel-*) pass "$h owned by $OWNER" ;;
    *)               fail "$h owned by $OWNER -- expected the distribution's libindi-devel" ;;
  esac
done
test -e /usr/include/libindi-stable && fail "/usr/include/libindi-stable exists -- nothing of ours belongs under /usr/include"
ls /usr/lib64/pkgconfig/ | grep -i 'indi-stable' && fail "a .pc of ours landed in /usr/lib64/pkgconfig" \
  || pass "no indi-stable .pc file under /usr/lib64/pkgconfig"

echo
echo "############ STEP 6: nothing of ours outside the private prefix ############"
OUT=$(rpm -ql indi-stable-core-devel | grep -v '^/opt/indi-stable' | grep -v '^/usr/lib/\.build-id')
if test -z "$OUT"; then pass "0 files outside /opt/indi-stable"; else fail "files outside the prefix:"; echo "$OUT"; fi
# CONTROL: the same pipeline with a filter that matches nothing must show the files.
N=$(rpm -ql indi-stable-core-devel | grep -vc '^/nonexistent')
test "$N" -gt 0 && ctl "same pipeline, non-matching filter: $N files -- it can see files" \
                || fail "the file listing is empty regardless of filter -- STEP 6 tested nothing"

echo
echo "############ STEP 7: no file collisions between the two -devel packages ############"
rpm -ql indi-stable-core-devel | sort > "$W/ours-devel.txt"
sort "$W/distro-files.txt" > "$W/theirs-devel.txt"
COLL=$(comm -12 "$W/ours-devel.txt" "$W/theirs-devel.txt")
if test -z "$COLL"; then pass "0 shared paths"; else fail "shared paths:"; echo "$COLL"; fi
NC=$(comm -12 "$W/theirs-devel.txt" "$W/theirs-devel.txt" | wc -l)
test "$NC" -gt 0 && ctl "same pipeline, distro list against itself: $NC shared paths -- it can detect collisions" \
                 || fail "the collision pipeline finds nothing even against itself -- STEP 7 tested nothing"

echo
echo "############ STEP 8: pkg-config resolves to the DISTRIBUTION ############"
# The check that matters. Both packages ship a module named `libindi`; only
# search order separates them, and pkg-config's default path is the same
# /usr/lib64/pkgconfig the compiler's /usr/include mirrors.
for AS in root "$BUILD_USER"; do
  for q in --cflags --libs "--variable=includedir" "--variable=libdir"; do
    if test "$AS" = root; then OUTP=$(pkg-config "$q" libindi 2>&1); RC=$?
    else OUTP=$(runuser -l "$AS" -c "pkg-config $q libindi" 2>&1); RC=$?; fi
    if test $RC -ne 0; then fail "as $AS: pkg-config $q libindi exited $RC: $OUTP"; continue; fi
    case $OUTP in
      *"/opt/indi-stable"*) fail "as $AS: pkg-config $q libindi -> $OUTP  (resolved to OUR prefix)" ;;
      *)                    pass "as $AS: pkg-config $q libindi -> ${OUTP:-(empty)}" ;;
    esac
  done
done
# CONTROL: pointed at our prefix it MUST resolve to /opt -- proves both that
# our .pc is readable and that the /opt test above could have fired.
CO=$(PKG_CONFIG_PATH=/opt/indi-stable/lib/pkgconfig pkg-config --variable=includedir libindi 2>&1)
case $CO in
  *"/opt/indi-stable"*) ctl "with PKG_CONFIG_PATH=/opt/indi-stable/lib/pkgconfig -> $CO" ;;
  *)                    fail "our own .pc does not resolve even when pointed at directly ($CO) -- STEP 8 proves nothing" ;;
esac
# And nothing may have widened the default search path.
PCP=$(pkg-config --variable pc_path pkg-config)
case $PCP in
  *"/opt/indi-stable"*) fail "pkg-config default path now includes our prefix: $PCP" ;;
  *)                    pass "pkg-config default path unchanged: $PCP" ;;
esac
grep -rl 'indi-stable' /etc/profile.d /etc/ld.so.conf.d 2>/dev/null \
  && fail "we dropped a file into /etc/profile.d or /etc/ld.so.conf.d" \
  || pass "no indi-stable file in /etc/profile.d or /etc/ld.so.conf.d"

echo
echo "############ STEP 9: the snapshot property still holds ############"
NOW_GCC=no; command -v gcc >/dev/null 2>&1 && NOW_GCC=yes
if test "$NOW_GCC" = "$HAD_GCC"; then pass "gcc present: $NOW_GCC (unchanged) -- the no-toolchain snapshot property survives"
else fail "gcc went from $HAD_GCC to $NOW_GCC -- this run spent the VM snapshot; see STATUS.md"; fi

echo
if test "$FAIL" -eq 0; then
  echo "############ STEP 10: back to the Snapshot B baseline ############"
  # Remove what this run ADDED, not a hardcoded list (LESSONS_LEARNED.md #6).
  # The first run of this script hardcoded four names and left libindi-qt (a
  # dependency of libindi-devel) and erfa (a dependency of ours) behind, while
  # printing that the baseline had been restored.
  rpm -qa --qf '%{NAME}\n' | sort > "$W/pkgs-after.txt"
  comm -13 "$W/pkgs-before.txt" "$W/pkgs-after.txt" > "$W/pkgs-added.txt"
  echo "  this run added: $(tr '\n' ' ' < "$W/pkgs-added.txt")"
  if test -s "$W/pkgs-added.txt"; then
    xargs -a "$W/pkgs-added.txt" -d '\n' dnf remove -y --no-autoremove \
      || fail "cleanup removal failed -- box left dirty"
  else
    fail "the run appears to have added no packages -- STEP 3 cannot have installed anything"
  fi

  # The assertion the first version lacked: compare the whole package set.
  rpm -qa --qf '%{NAME}\n' | sort > "$W/pkgs-final.txt"
  if diff -u "$W/pkgs-before.txt" "$W/pkgs-final.txt" > "$W/pkgs.diff"; then
    pass "installed package set identical to the baseline ($(wc -l < "$W/pkgs-final.txt") packages)"
  else
    fail "the box is NOT back to its baseline:"; cat "$W/pkgs.diff"
  fi
  test -e /opt/indi-stable && fail "/opt/indi-stable survived removal" || pass "/opt/indi-stable gone"
  if rpm -V libindi; then pass "rpm -V libindi clean after the whole cycle"; else fail "rpm -V libindi dirty after removal"; fi
fi

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "ALL CHECKS PASSED -- box restored to the Snapshot B baseline."
else
  echo "FAILURES ABOVE. The box was left as-is for inspection. To restore:"
  echo "  sudo dnf remove --no-autoremove indi-stable-core-devel indi-stable-core-libs libindi-devel libindi-static"
fi
echo "  scratch: $W"
echo "==================================================================="
exit "$FAIL"
