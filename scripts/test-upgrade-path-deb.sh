#!/bin/bash
#
# Upgrade-path test for dpkg -- does the alternative survive an upgrade, and is
# it genuinely withdrawn on a real removal?
#
# DEBIAN.md, "The equivalent of the tests that mattered" #3, which says in as
# many words: "Debian's prerm/postinst run in a different order than RPM's
# scriptlets, so reason it through for dpkg rather than porting the RPM
# assumption." This script does not reason it through -- it OBSERVES it, with
# `dpkg -D2` ("Invocation and status of maintainer scripts"), because a claim
# about an external tool is worth more run than recalled (LESSONS_LEARNED.md
# #10). STEP 3 prints the actual sequence.
#
# WHAT THE RPM TEST WAS GUARDING, AND WHY IT DOES NOT TRANSFER
#
# scripts/test-upgrade-path.sh exists because RPM runs the OLD package's
# %postun LAST, after the new %post has already registered the alternative, so
# an unguarded `alternatives --remove` there tears down the link the new
# scriptlet just installed. The `$1 -eq 0` guard is what stops it.
#
# dpkg orders an upgrade the other way round:
#
#     old prerm upgrade <new>  ->  new preinst upgrade <old>  ->  unpack
#       ->  old postrm upgrade <new>  ->  new postinst configure <old>
#
# The NEW package's postinst runs LAST, and ours calls
# `update-alternatives --install`, which is idempotent. So on dpkg the link is
# restored by the last script to run rather than destroyed by it, and the
# prerm's `remove|deconfigure` case guard is a belt to the postinst's braces
# rather than the only thing standing between the user and a dangling command.
# That is a genuinely weaker hazard than RPM's, and saying so is only worth
# anything if it was measured -- hence STEP 3.
#
# WHAT IS ACTUALLY FRAGILE HERE INSTEAD
#
# DEBIAN.md: "The alternatives install/remove name pairing lives in two files
# here, postinst and prerm, rather than in one spec. A rename applied to one
# and not the other strands the admin record." That is the dpkg-specific
# defect, so it is what STEP 7 builds on purpose and shows this harness able to
# catch (LESSONS_LEARNED.md #15 -- a control has to be able to detect the
# specific defect the check exists for, not merely SOMETHING).
#
# Run as: sudo bash scripts/test-upgrade-path-deb.sh <old-deb-dir> [new-deb-dir]
#
# Standing rules: absolute paths, never ~ (#4); assert the setup landed before
# measuring it (#5); restore by diffing (#6); readlink -e, not -f (#8).
#
set -u

BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)
OLD_DIR=${1:-$HOMEDIR/build}
NEW_DIR=${2:-$OLD_DIR}
OLD_VER=${OLD_VER:-2.2.4.2-1}
NEW_VER=${NEW_VER:-2.2.4.2-2}
W=$(mktemp -d /tmp/upgrade-deb.XXXXXX)

LINK=/usr/bin/indiserver-stable
ETCALT=/etc/alternatives/indiserver-stable
ADMIN=/var/lib/dpkg/alternatives/indiserver-stable
TARGET=/opt/indi-stable/bin/indiserver

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; echo "  work dir kept: $W"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

snapshot() { dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort; }

echo "############ STEP 0: two genuinely different builds, both current ############"
test "$(id -u)" -eq 0 || die "run under sudo"
# Anchored on the '_' separating name from version and on _amd64.deb, so the
# .ddeb debug packages beside them cannot match (LESSONS_LEARNED.md #3).
OLD_MAIN=$OLD_DIR/indi-stable-core_${OLD_VER}_amd64.deb
OLD_LIBS=$OLD_DIR/indi-stable-core-libs_${OLD_VER}_amd64.deb
NEW_MAIN=$NEW_DIR/indi-stable-core_${NEW_VER}_amd64.deb
NEW_LIBS=$NEW_DIR/indi-stable-core-libs_${NEW_VER}_amd64.deb
NEW_DEV=$NEW_DIR/indi-stable-core-dev_${NEW_VER}_amd64.deb
for f in "$OLD_MAIN" "$OLD_LIBS" "$NEW_MAIN" "$NEW_LIBS"; do
  test -f "$f" || die "missing $f -- build it first (DEBIAN.md)"
done
test "$OLD_VER" != "$NEW_VER" \
  || die "old and new are the SAME version -- an 'upgrade' to an identical package is a reinstall and would not exercise the script ordering this test exists for"
info "old: $OLD_VER    new: $NEW_VER"

# A revision bump does NOT mean newer packaging. The 2.2.4.2-2 debs that sat on
# this box before 2026-08-25 were a bumped revision of packaging that PREDATED
# the libindi.pc fixes -- a higher version carrying older content. Upgrading
# onto one would have looked like an upgrade and quietly tested a build nobody
# meant to test. Check the payload, not the version (LESSONS_LEARNED.md #11).
if test -f "$NEW_DEV"; then
  dpkg-deb --fsys-tarfile "$NEW_DEV" \
    | tar -xO ./opt/indi-stable/lib/pkgconfig/libindi.pc 2>/dev/null > "$W/new-pc" || true
  if test -s "$W/new-pc"; then
    grep -qF -- '-Wl,-rpath,${libdir}' "$W/new-pc" \
      && pass "the new build's libindi.pc carries the current fixes -- it is newer packaging, not just a higher number" \
      || die "$(basename "$NEW_DEV") PREDATES the libindi.pc fixes. Its version is higher but its content is older; rebuild the new side before using it (DEBIAN.md, Building)"
  fi
fi

# The two files that must agree, read out of the .deb rather than the repo:
# the artifact is what will run (LESSONS_LEARNED.md #2).
rm -rf "$W/ctl-new"; dpkg-deb --control "$NEW_MAIN" "$W/ctl-new" >/dev/null 2>&1 || die "cannot read the new package's control archive"
# Both calls are written across several lines with backslash continuations,
# so the continuations are joined before anything is matched. The first
# version of this grep matched the raw file and silently found nothing in the
# postinst while succeeding on the single-line prerm -- a check that reported
# "unreadable" for one side only (LESSONS_LEARNED.md #2: read the artifact,
# and make sure you are reading it in the form the tool will).
join_continuations() { sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n/ /g' "$1" | tr -s ' \t' '  '; }
PI_NAME=$(join_continuations "$W/ctl-new/postinst" \
          | grep -oE 'update-alternatives --install +[^ ]+ +[^ ]+ +[^ ]+' | head -1)
PR_NAME=$(join_continuations "$W/ctl-new/prerm" \
          | grep -oE 'update-alternatives --remove +[^ ]+ +[^ ]+' | head -1)
info "postinst registers: ${PI_NAME:-<unreadable>}"
info "prerm    withdraws: ${PR_NAME:-<unreadable>}"
# --install <link-path> <name> <target>;  --remove <name> <target>
PI_LINK=$(echo "$PI_NAME" | awk '{print $4}'); PI_TGT=$(echo "$PI_NAME" | awk '{print $5}')
PR_LINK=$(echo "$PR_NAME" | awk '{print $3}'); PR_TGT=$(echo "$PR_NAME" | awk '{print $4}')
if test -n "$PI_LINK" && test -n "$PR_LINK"; then
  test "$PI_LINK" = "$PR_LINK" && test "$PI_TGT" = "$PR_TGT" \
    && pass "postinst and prerm name the same alternative ($PI_LINK -> $PI_TGT)" \
    || fail "postinst and prerm DISAGREE: install '$PI_LINK -> $PI_TGT' vs remove '$PR_LINK -> $PR_TGT'. A removal will strand the admin record (DEBIAN.md)"
else
  fail "could not read the alternative name out of both maintainer scripts -- this check measured nothing"
fi

echo
echo "############ STEP 0b: clean slate ############"
dpkg -s indi-stable-core >/dev/null 2>&1 && die "ours is already installed -- clean it first"
test -e "$LINK"  && die "$LINK survived a previous run -- stale state"
test -e "$ADMIN" && die "$ADMIN survived a previous run -- stale alternatives admin record"
test -e /opt/indi-stable && die "/opt/indi-stable exists before we installed anything"
pass "no indi-stable installed, no stale alternative"

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
echo "############ STEP 1: install the OLD build ############"
apt-get install -y "$OLD_LIBS" "$OLD_MAIN" >"$W/install-old.log" 2>&1 \
  || { tail -20 "$W/install-old.log"; die "installing the old build failed"; }
INSTALLED_OLD=$(dpkg-query -W -f='${Version}' indi-stable-core)
test "$INSTALLED_OLD" = "$OLD_VER" || die "installed $INSTALLED_OLD, expected $OLD_VER"
OLD_TARGET=$(readlink -e "$LINK") \
  || die "$LINK does not resolve after the OLD install -- the alternative never worked, so an upgrade test would be meaningless"
info "$LINK -> $OLD_TARGET"
test -e "$ADMIN" || die "no alternatives admin record at $ADMIN after the old install"
pass "the alternative is live before the upgrade -- the test has something to break"

echo
echo "############ STEP 2: THE UPGRADE, with maintainer scripts traced ############"
# dpkg -i rather than apt-get: -D2 belongs to dpkg, and both packages'
# dependencies are already satisfied by the old install, so no solving is
# needed. PIPESTATUS, because the tee would otherwise report the status
# (LESSONS_LEARNED.md #7).
dpkg -D2 -i "$NEW_LIBS" "$NEW_MAIN" >"$W/upgrade.log" 2>&1
UPRC=$?
test "$UPRC" -eq 0 || { tail -30 "$W/upgrade.log"; die "the upgrade transaction itself failed (exit $UPRC)"; }
pass "the upgrade transaction succeeded"

echo
echo "############ STEP 3: the OBSERVED maintainer-script order ############"
# dpkg -D2 logs each script it actually runs as
#     D000002: fork/exec /var/lib/dpkg/info/<pkg>.<script> ( <args> )
# and separately logs the ones it SKIPS as "nonexistent <script>". Only the
# fork/exec lines are invocations. The first version of this step grepped for
# prose ("old pre-removal") that dpkg never emits, found nothing, and declared
# the trace empty while the trace was sitting in the log -- LESSONS_LEARNED.md
# #2, in the check rather than the package.
grep -oE 'fork/exec /var/lib/dpkg/info/[^ ]+\.(preinst|prerm|postinst|postrm) \( [^)]*\)' "$W/upgrade.log" \
  | sed -e 's|fork/exec /var/lib/dpkg/info/||' > "$W/order.txt"
if test -s "$W/order.txt"; then
  sed 's/^/      /' "$W/order.txt"
else
  fail "dpkg -D2 produced no fork/exec maintainer-script lines at all -- STEP 3 observed nothing, and its conclusions would be recalled rather than measured"
fi

if test -s "$W/order.txt"; then
  LAST=$(tail -1 "$W/order.txt")
  info "last maintainer script to run: $LAST"
  case $LAST in
    *.postinst\ \(\ configure*)
      pass "the NEW package's postinst ran LAST, with 'configure' -- the opposite of RPM, where the OLD %postun does. The alternative is re-registered by the final script rather than withdrawn by it" ;;
    *)
      fail "the last script was '$LAST', not a postinst configure -- the ordering described in this file's header does not match this dpkg, and the guard analysis needs redoing" ;;
  esac
  PRERM=$(grep '\.prerm' "$W/order.txt" | head -1)
  if test -n "$PRERM"; then
    case $PRERM in
      *\(\ upgrade*)
        pass "the old package's prerm ran as '$PRERM' -- argument 'upgrade', which our 'remove|deconfigure' case does NOT match, so it withdrew nothing" ;;
      *\(\ remove*|*\(\ deconfigure*)
        fail "the old package's prerm ran as '$PRERM' during an UPGRADE -- our case guard DOES match that, so the alternative was withdrawn mid-transaction" ;;
      *)
        info "the old package's prerm ran as '$PRERM'" ;;
    esac
  else
    fail "no prerm invocation in the trace at all -- then the guard this step exists to observe was never exercised"
  fi
fi

echo
echo "############ STEP 4: THE POINT -- the alternative survived ############"
INSTALLED_NEW=$(dpkg-query -W -f='${Version}' indi-stable-core)
info "now installed: $INSTALLED_NEW"
test "$INSTALLED_NEW" = "$NEW_VER" \
  && pass "the installed version changed $INSTALLED_OLD -> $INSTALLED_NEW, so an upgrade really occurred" \
  || fail "still $INSTALLED_OLD -- nothing was upgraded and everything below would prove nothing"
test "$(dpkg-query -W -f='${Package}\n' 'indi-stable-core' | wc -l)" -eq 1 \
  && pass "exactly one copy installed" || fail "more than one indi-stable-core is installed"

if NEW_TARGET=$(readlink -e "$LINK"); then
  info "$LINK -> $NEW_TARGET"
  pass "the command still resolves after the upgrade"
  case $NEW_TARGET in
    /opt/indi-stable/*) pass "and still points into the private prefix" ;;
    *) fail "it now points OUTSIDE the private prefix: $NEW_TARGET" ;;
  esac
else
  fail "$LINK IS DANGLING OR GONE after the upgrade"
  ls -l "$LINK" 2>&1 | sed 's/^/        /'
fi
test -e "$ADMIN" && pass "the alternatives admin record survived" \
                 || fail "$ADMIN is gone -- the upgrade withdrew the alternative"
test -L "$ETCALT" && pass "$ETCALT is still a symlink" || fail "$ETCALT is missing or not a symlink"
update-alternatives --display indiserver-stable 2>&1 | sed 's/^/        /'

echo
echo "############ STEP 5: it still runs ############"
if "$LINK" --version 2>&1 | grep -E 'INDI Library|Code' | sed 's/^/        /'; then
  pass "the upgraded indiserver-stable executes"
else
  fail "the upgraded indiserver-stable did not report a version"
fi

echo
echo "############ STEP 6: the distribution binary is still a bystander ############"
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
echo "############ STEP 7: CONTROL -- can this harness see a stranded record? ############"
# STEP 4 passes by FINDING the link and the admin record. The dpkg-specific
# defect DEBIAN.md warns about is the opposite: a removal that leaves the
# record behind because prerm names an alternative postinst never registered.
# Build exactly that, and confirm the checks below report it. If they cannot,
# STEP 8's "nothing left behind" would pass on a broken package too.
rm -rf "$W/typo"; mkdir -p "$W/typo"
dpkg-deb -R "$NEW_MAIN" "$W/typo" >/dev/null 2>&1 || fail "could not unpack the new package for the control"
if test -f "$W/typo/DEBIAN/prerm"; then
  sed -i 's/--remove indiserver-stable /--remove indiserver-stable-typo /' "$W/typo/DEBIAN/prerm"
  sed -i 's/^Version: .*/Version: 2.2.4.2-3typo/' "$W/typo/DEBIAN/control"
  grep -q -- '--remove indiserver-stable-typo' "$W/typo/DEBIAN/prerm" \
    || fail "could not plant the typo -- the control below would test nothing"
  dpkg-deb -b "$W/typo" "$W/typo.deb" >/dev/null 2>&1 || fail "could not rebuild the control package"
  if test -f "$W/typo.deb"; then
    dpkg -i "$W/typo.deb" >"$W/typo-install.log" 2>&1 || fail "installing the control package failed"
    dpkg -r indi-stable-core >"$W/typo-remove.log" 2>&1
    if test -e "$ADMIN"; then
      ctl "removing a package whose prerm names the WRONG alternative leaves $ADMIN behind -- so STEP 8's check below can detect a stranded record, and the postinst/prerm pairing is load-bearing exactly as DEBIAN.md says"
      update-alternatives --remove indiserver-stable "$TARGET" >/dev/null 2>&1
      test -e "$ADMIN" && fail "could not clean up the stranded record by hand -- remove it before the next run"
    else
      fail "CONTROL: the admin record was cleaned up even with a mismatched prerm. Then STEP 8's 'no record left behind' cannot distinguish a correct package from a broken one, and its pass means nothing"
    fi
  fi
fi

echo
echo "############ STEP 8: a REAL removal withdraws the alternative ############"
# The other half of STEP 4's control: it passed by finding the link, so the
# same checks are pointed at a state where the link must be ABSENT.
dpkg -s indi-stable-core >/dev/null 2>&1 && apt-get remove -y --no-autoremove indi-stable-core >>"$W/teardown.log" 2>&1
readlink -e "$LINK" >/dev/null 2>&1 \
  && fail "$LINK STILL resolves after a full removal -- prerm did not withdraw the alternative" \
  || pass "after a real removal the link is gone, so STEP 4 was a genuine check"
test -e "$ADMIN" && fail "the admin record $ADMIN survived a full removal" \
                 || pass "the admin record was cleaned up too"
test -e "$ETCALT" && fail "$ETCALT survived a full removal" \
                  || pass "$ETCALT was cleaned up"

echo
echo "############ STEP 9: restore, by diffing rather than by naming ############"
TO_REMOVE=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
              indi-stable-core indi-stable-core-libs indi-stable-core-dev 2>/dev/null \
            | awk '$1 ~ /^i/ {print $2}')
info "removing what is actually installed: ${TO_REMOVE:-(nothing)}"
test -n "$TO_REMOVE" && apt-get remove -y --no-autoremove $TO_REMOVE >>"$W/teardown.log" 2>&1

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
  diff "$BASELINE" "$W/final.txt" | sed 's/^/        /'
fi
test -e /opt/indi-stable && fail "/opt/indi-stable survived the teardown" \
                         || pass "/opt/indi-stable fully removed"

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "DEB UPGRADE PATH: ALL CHECKS PASSED"
else
  echo "DEB UPGRADE PATH: ONE OR MORE CHECKS FAILED"
fi
echo "  logs: $W"
echo "==================================================================="
exit "$FAIL"
