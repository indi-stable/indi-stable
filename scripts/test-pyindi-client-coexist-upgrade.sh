#!/bin/bash
#
# Coexistence + upgrade-path test for indi-stable-pyindi-client -- a
# different risk shape than every other component's upgrade test in this
# project. This package has no scriptlets at all (single package, confirmed
# by reading the spec -- no %post/%postun, no alternatives), so neither
# core's %postun ordering bug class (scripts/test-upgrade-path.sh) nor
# 3rdparty's orphaned-file class (scripts/test-upgrade-path-3rdparty.sh)
# applies here. What actually matters, and had never been exercised until
# this test (STATUS.md, "indi-stable-pyindi-client -- RPM side" only ever
# covered a single, static core version):
#
#   * COEXISTENCE: with Fedora's own libindi/libindi-libs installed
#     (identical libindiclient.so.2 SONAME -- confirmed real via
#     `rpm -q --provides`, not assumed), does `import PyIndi;
#     PyIndi.BaseClient()` resolve to OUR copy under /opt/indi-stable/lib,
#     not the distribution's.
#   * UPGRADE SURVIVAL: pyindi-client itself is never upgraded here --
#     indi-stable-core/-libs is. pyindi-client's RPATH points at a
#     DIRECTORY, not a pinned file, and its Requires on
#     indi-stable-core-libs is deliberately unversioned, so an upgrade
#     transaction that replaces core-libs underneath an ALREADY-INSTALLED,
#     untouched pyindi-client package is exactly the scenario this
#     project's coexistence guarantee has to survive for a Python consumer.
#
# Run as:
#   sudo bash scripts/test-pyindi-client-coexist-upgrade.sh \
#       [pyindi-dir] [old-core-dir] [new-core-dir]
#
# Defaults match fedoraastro's machine state (STATUS.md): pyindi-dir
# ~/mock-result-pyindi-client, old-core-dir ~/mock-result-pcfix,
# new-core-dir ~/mock-result-core-rel2 -- a genuine Release 2 scratch build
# of the CURRENT committed core.spec (never the repo's own Release: 1, same
# "bump Release in an uncommitted scratch copy" trick as every other
# upgrade test here). Do NOT point new-core-dir at ~/mock-result-rel2: that
# directory predates the libindi.pc fixes (STATUS.md, machine state) and
# would test stale packaging, not what actually ships.
#
# Standing rules for root-run tests (LESSONS_LEARNED.md #4, #5): absolute
# paths; assert the setup landed before measuring it.
#
set -u

# LESSONS_LEARNED.md #4: under sudo, $HOME is /root, not the invoking user's
# home -- derive the real one from SUDO_USER instead.
BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)

PYINDI_DIR=${1:-$HOMEDIR/mock-result-pyindi-client}
OLD_CORE_DIR=${2:-$HOMEDIR/mock-result-pcfix}
NEW_CORE_DIR=${3:-$HOMEDIR/mock-result-core-rel2}

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }

# Anchored to *.x86_64.rpm, excluding debuginfo/debugsource and the .src.rpm
# a resultdir also holds (LESSONS_LEARNED.md #3, #21).
pyindi_rpm()     { ls "$PYINDI_DIR"/indi-stable-pyindi-client-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource; }
old_core_rpms()  { ls "$OLD_CORE_DIR"/indi-stable-core-2*.x86_64.rpm "$OLD_CORE_DIR"/indi-stable-core-libs-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource; }
new_core_rpms()  { ls "$NEW_CORE_DIR"/indi-stable-core-2*.x86_64.rpm "$NEW_CORE_DIR"/indi-stable-core-libs-2*.x86_64.rpm 2>/dev/null | grep -v -e debuginfo -e debugsource; }

SO_GLOB="/usr/lib64/python3.*/site-packages/PyIndi/_PyIndi*.so"
so_path() { ls $SO_GLOB 2>/dev/null | head -1; }

echo "############ STEP 0: builds present, old/new core genuinely different ############"
test -n "$(pyindi_rpm)" || die "no pyindi-client RPM in $PYINDI_DIR -- build it first (FEDORA.md)"
test -n "$(old_core_rpms)" || die "no core RPMs in $OLD_CORE_DIR"
test -n "$(new_core_rpms)" || die "no core RPMs in $NEW_CORE_DIR"
OLD_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(old_core_rpms | grep -- '-core-2') | head -1)
NEW_NVR=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' $(new_core_rpms | grep -- '-core-2') | head -1)
echo "  old core: $OLD_NVR"
echo "  new core: $NEW_NVR"
[ -n "$OLD_NVR" ] && [ -n "$NEW_NVR" ] || die "could not read a core NVR from one of the two directories"
[ "$OLD_NVR" != "$NEW_NVR" ] \
  || die "old and new core are the SAME NVR -- an 'upgrade' to an identical package is a reinstall, not an upgrade"

echo "############ STEP 0b: start from a clean slate ############"
rpm -qa | grep -q '^indi-stable-' && dnf remove -y $(rpm -qa | grep '^indi-stable-') 2>/dev/null
rpm -qa | grep -q '^indi-stable-' && die "could not remove pre-existing indi-stable packages"
test -e /opt/indi-stable && die "/opt/indi-stable survived removal -- stale state, clean it before testing"
pass "no indi-stable installed, /opt/indi-stable absent"

echo "############ STEP 0c: CONTROL -- import genuinely fails before install ############"
# Proves "import succeeds" below is a real result, not a check that would
# pass even without our RPM (a stray venv, a leftover system install, a
# cached .pyc from an earlier run) -- LESSONS_LEARNED.md #1's shape, applied
# to a positive-assertion check rather than a find-nothing one.
if python3 -c 'import PyIndi' 2>/dev/null; then
  die "CONTROL: 'import PyIndi' already succeeds with NOTHING installed -- the whole test would be meaningless. Check for a stray system install."
fi
ctl "'import PyIndi' correctly fails before anything is installed"

DISTRO_COLLIDES=0
if rpm -q libindi-libs >/dev/null 2>&1; then
  if rpm -q --provides libindi-libs 2>/dev/null | grep -q '^libindiclient\.so\.2'; then
    DISTRO_COLLIDES=1
    echo "  distro libindi-libs provides libindiclient.so.2 -- the SONAME collision below is real, not hypothetical"
  else
    echo "  distro libindi-libs installed but does not provide libindiclient.so.2 (unexpected -- check the box)"
  fi
else
  echo "  (no distro libindi-libs on this box -- the coexistence half of this test will not be meaningful, only the upgrade-survival half)"
fi

echo "############ STEP 1: install core + core-libs (OLD) + pyindi-client together ############"
dnf install -y $(old_core_rpms) $(pyindi_rpm) || die "installing old core + pyindi-client failed"
PYINDI_NVR_PRE=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-pyindi-client)
CORE_NVR_PRE=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-core-libs)
echo "  pyindi-client: $PYINDI_NVR_PRE"
echo "  core-libs:     $CORE_NVR_PRE"

echo "############ STEP 2: COEXISTENCE -- fresh install, distro INDI still present ############"
SO=$(so_path)
test -n "$SO" || die "the compiled extension is not where expected ($SO_GLOB) -- did the package layout change?"
echo "  extension: $SO"
if python3 -c 'import PyIndi; c = PyIndi.BaseClient(); assert hasattr(c, "setServer")' 2>&1; then
  pass "import PyIndi; PyIndi.BaseClient() succeeds on a fresh install"
else
  fail "import PyIndi failed on a fresh install"
fi
LDD_TARGET=$(ldd "$SO" 2>/dev/null | awk '/libindiclient\.so\.2/ {print $3}')
echo "  libindiclient.so.2 resolves to: ${LDD_TARGET:-<not found>}"
case "$LDD_TARGET" in
  /opt/indi-stable/lib/*) pass "resolves into the private prefix, not the distribution's identical SONAME" ;;
  *) fail "did NOT resolve into /opt/indi-stable/lib -- got '${LDD_TARGET:-nothing}'" ;;
esac

echo "############ STEP 3: THE UPGRADE -- core/-libs only, pyindi-client untouched ############"
echo "  (pyindi-client is not part of this dnf transaction at all)"
dnf install -y $(new_core_rpms) || die "the upgrade transaction itself failed"

echo "############ STEP 4: did the upgrade happen, and did pyindi-client survive untouched? ############"
CORE_NVR_POST=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-core-libs)
echo "  core-libs now: $CORE_NVR_POST"
[ "$CORE_NVR_POST" != "$CORE_NVR_PRE" ] \
  && pass "core-libs' NVR changed, so an upgrade really occurred" \
  || fail "core-libs still $CORE_NVR_PRE -- nothing was upgraded and STEP 5 would prove nothing"
NEW_OWNER=$(rpm -qf "$SO" --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null)
echo "  $SO owned by: $NEW_OWNER"
[ "$NEW_OWNER" = "$PYINDI_NVR_PRE" ] \
  && pass "the compiled extension is still owned by the SAME pyindi-client NVR -- the package itself was not touched" \
  || fail "the extension's owning package changed: expected $PYINDI_NVR_PRE, got $NEW_OWNER"
PYINDI_NVR_POST=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' indi-stable-pyindi-client)
[ "$PYINDI_NVR_POST" = "$PYINDI_NVR_PRE" ] \
  && pass "indi-stable-pyindi-client's own NVR is unchanged ($PYINDI_NVR_POST)" \
  || fail "indi-stable-pyindi-client's NVR changed across a core-only upgrade: $PYINDI_NVR_PRE -> $PYINDI_NVR_POST"
rpm -V indi-stable-pyindi-client >/tmp/pyindi-verify.$$ 2>&1
if [ -s /tmp/pyindi-verify.$$ ]; then
  fail "rpm -V reports pyindi-client modified by the core upgrade:"
  sed 's/^/    /' /tmp/pyindi-verify.$$
else
  pass "rpm -V clean on indi-stable-pyindi-client after the core upgrade"
fi
rm -f /tmp/pyindi-verify.$$

echo "############ STEP 5: THE POINT -- does it still work after core moved underneath it? ############"
if python3 -c 'import PyIndi; c = PyIndi.BaseClient(); assert hasattr(c, "setServer")' 2>&1; then
  pass "import PyIndi; PyIndi.BaseClient() STILL succeeds after core-libs was upgraded"
else
  fail "import PyIndi FAILED after the core upgrade -- this is exactly the risk this test exists for"
fi
LDD_TARGET2=$(ldd "$SO" 2>/dev/null | awk '/libindiclient\.so\.2/ {print $3}')
echo "  libindiclient.so.2 now resolves to: ${LDD_TARGET2:-<not found>}"
case "$LDD_TARGET2" in
  /opt/indi-stable/lib/*) pass "still resolves into the private prefix after the upgrade" ;;
  *) fail "no longer resolves into /opt/indi-stable/lib -- got '${LDD_TARGET2:-nothing}'" ;;
esac
NEW_SO_OWNER=$(rpm -qf /opt/indi-stable/lib/libindiclient.so.2 --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 2>/dev/null)
echo "  /opt/indi-stable/lib/libindiclient.so.2 now owned by: $NEW_SO_OWNER"
[ "$NEW_SO_OWNER" = "$CORE_NVR_POST" ] \
  && pass "the library pyindi-client just resolved really is the UPGRADED one, not a stale cached copy" \
  || fail "the resolved library is owned by $NEW_SO_OWNER, expected the new core-libs $CORE_NVR_POST"

echo "############ STEP 6: the distro binary is still a bystander ############"
if [ "$DISTRO_COLLIDES" -eq 1 ]; then
  rpm -V libindi libindi-libs >/tmp/distro-verify.$$ 2>&1
  if [ -s /tmp/distro-verify.$$ ]; then
    fail "rpm -V reports distro INDI modified:"
    sed 's/^/    /' /tmp/distro-verify.$$
  else
    pass "rpm -V clean on libindi/libindi-libs after coexistence + upgrade"
  fi
  rm -f /tmp/distro-verify.$$
fi
if [ -e /usr/bin/indiserver ]; then
  echo "  distro /usr/bin/indiserver sha256: $(sha256sum /usr/bin/indiserver | awk '{print $1}')"
fi

echo "############ STEP 7: full removal, then CONTROL -- import fails again ############"
dnf remove -y $(rpm -qa | grep '^indi-stable-') 2>&1 | tail -3
if [ -e /opt/indi-stable ]; then
  fail "/opt/indi-stable survived a full removal -- see LESSONS_LEARNED.md #20"
  find /opt/indi-stable 2>&1 | sed 's/^/    /'
else
  pass "/opt/indi-stable fully removed"
fi
if python3 -c 'import PyIndi' 2>/dev/null; then
  fail "CONTROL: 'import PyIndi' still succeeds after full removal -- STEP 2/5's passes cannot be trusted"
else
  ctl "'import PyIndi' correctly fails again after removal, so STEP 2/5's passes were real"
fi

echo
if [ $FAIL -eq 0 ]; then
  echo "############ PYINDI-CLIENT COEXIST + UPGRADE PATH: ALL CHECKS PASSED ############"
else
  echo "############ PYINDI-CLIENT COEXIST + UPGRADE PATH: ONE OR MORE CHECKS FAILED ############"
fi
exit $FAIL
