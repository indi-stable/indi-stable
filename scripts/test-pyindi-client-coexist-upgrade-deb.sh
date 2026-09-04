#!/bin/bash
#
# Coexistence + upgrade-path test for the Debian side of
# indi-stable-pyindi-client -- the Debian equivalent of
# scripts/test-pyindi-client-coexist-upgrade.sh (RPM). Same reasoning as
# that script's own header: indi-stable-pyindi-client ships no
# postinst/prerm and registers no alternative (confirmed by reading
# pyindi-client/deb -- it has neither file), so core's maintainer-script
# ordering test (test-upgrade-path-deb.sh) and 3rdparty's orphaned-file
# class (test-upgrade-path-3rdparty-deb.sh) do not apply here. What
# actually matters, and had never been exercised until this test
# (STATUS.md, "indi-stable-pyindi-client -- Debian side" only ever covered
# a single, static core version):
#
#   * COEXISTENCE: with configuration B's libindi1 installed (identical
#     libindiclient.so.2 SONAME -- confirmed real via `dpkg -S` on the
#     actual file, not assumed), does `import PyIndi; PyIndi.BaseClient()`
#     resolve to OUR copy under /opt/indi-stable/lib, not the
#     distribution's.
#   * UPGRADE SURVIVAL: pyindi-client itself is never upgraded here --
#     indi-stable-core/-libs is. debian/rules bakes an RPATH into a
#     DIRECTORY, not a pinned file, and pyindi-client's Depends on
#     indi-stable-core-libs is unversioned (pyindi-client/deb/control), so
#     an upgrade transaction that replaces core-libs underneath an
#     ALREADY-INSTALLED, untouched pyindi-client package is exactly the
#     scenario this project's coexistence guarantee has to survive for a
#     Python consumer.
#
# Run as:
#   sudo bash scripts/test-pyindi-client-coexist-upgrade-deb.sh [pyindi-dir] [core-dir]
#
# OLD_VER/NEW_VER/PYINDI_VER environment variables override the defaults,
# same convention as test-upgrade-path-deb.sh. Defaults match ubuntuastro's
# machine state (STATUS.md): both dirs default to ~/build, PYINDI_VER
# 2.2.0-1, OLD_VER 2.2.4.2-1, NEW_VER 2.2.4.2-2 -- the SAME Release-2
# scratch build core's own upgrade test already uses (confirmed 2026-08-27
# to carry the libindi.pc fixes, same as -1: do not rebuild a new one).
#
# Standing rules: absolute paths, never ~ (LESSONS_LEARNED.md #4); assert
# the setup landed before measuring it (#5); restore by diffing (#6).
#
set -u

BUILD_USER=${SUDO_USER:-$(id -un)}
HOMEDIR=$(getent passwd "$BUILD_USER" | cut -d: -f6)
PYINDI_DIR=${1:-$HOMEDIR/build}
CORE_DIR=${2:-$HOMEDIR/build}
PYINDI_VER=${PYINDI_VER:-2.2.0-1}
OLD_VER=${OLD_VER:-2.2.4.2-1}
NEW_VER=${NEW_VER:-2.2.4.2-2}
W=$(mktemp -d /tmp/pyindi-coexist-upgrade-deb.XXXXXX)

FAIL=0
die()  { echo; echo "*** ABORT: $* ***"; echo "  work dir kept: $W"; exit 1; }
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

snapshot() { dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort; }

PYINDI_DEB="$PYINDI_DIR/indi-stable-pyindi-client_${PYINDI_VER}_amd64.deb"
old_core_debs() {
  echo "$CORE_DIR/indi-stable-core_${OLD_VER}_amd64.deb"
  echo "$CORE_DIR/indi-stable-core-libs_${OLD_VER}_amd64.deb"
}
new_core_debs() {
  echo "$CORE_DIR/indi-stable-core_${NEW_VER}_amd64.deb"
  echo "$CORE_DIR/indi-stable-core-libs_${NEW_VER}_amd64.deb"
}

SO_GLOB="/usr/lib/python3/dist-packages/PyIndi/_PyIndi*.so"
so_path() { ls $SO_GLOB 2>/dev/null | head -1; }

echo "############ STEP 0: builds present, old/new core genuinely different ############"
test "$(id -u)" -eq 0 || die "run under sudo"
test -f "$PYINDI_DEB" || die "missing $PYINDI_DEB -- build it first (DEBIAN.md)"
for f in $(old_core_debs) $(new_core_debs); do
  test -f "$f" || die "missing $f -- build it first (DEBIAN.md)"
done
test "$OLD_VER" != "$NEW_VER" \
  || die "old and new core are the SAME version -- an 'upgrade' to an identical package is a reinstall, not an upgrade"
info "pyindi-client: $PYINDI_VER    old core: $OLD_VER    new core: $NEW_VER"

echo
echo "############ STEP 0b: clean slate ############"
dpkg -s indi-stable-pyindi-client >/dev/null 2>&1 && die "pyindi-client is already installed -- clean it first"
dpkg -s indi-stable-core >/dev/null 2>&1 && die "indi-stable-core is already installed -- clean it first"
test -e /opt/indi-stable && die "/opt/indi-stable exists before we installed anything"
pass "no indi-stable installed, /opt/indi-stable absent"

echo
echo "############ STEP 0c: CONTROL -- import genuinely fails before install ############"
# Proves "import succeeds" below is a real result, not a check that would
# pass even without our .deb (a stray venv, a leftover install, a cached
# .pyc) -- LESSONS_LEARNED.md #1's shape, applied to a positive-assertion
# check rather than a find-nothing one.
if python3 -c 'import PyIndi' 2>/dev/null; then
  die "CONTROL: 'import PyIndi' already succeeds with NOTHING installed -- the whole test would be meaningless. Check for a stray system install."
fi
ctl "'import PyIndi' correctly fails before anything is installed"

BASELINE=$W/baseline.txt
snapshot > "$BASELINE"

DISTRO_SO=""
DISTRO_COLLIDES=0
if dpkg -s libindi1 >/dev/null 2>&1; then
  DISTRO_SO=$(dpkg -L libindi1 2>/dev/null | grep -m1 'libindiclient\.so\.2$')
  if test -n "$DISTRO_SO"; then
    DISTRO_COLLIDES=1
    info "distro libindi1 owns $DISTRO_SO -- the SONAME collision below is real, not hypothetical"
  else
    info "distro libindi1 installed but owns no libindiclient.so.2 (unexpected -- check the box)"
  fi
else
  info "(no distro libindi1 on this box -- the coexistence half of this test will not be meaningful, only the upgrade-survival half)"
fi
DISTRO_INDISERVER_SHA=""
if test -e /usr/bin/indiserver; then
  DISTRO_INDISERVER_SHA=$(sha256sum /usr/bin/indiserver | awk '{print $1}')
  info "distro /usr/bin/indiserver sha256: $DISTRO_INDISERVER_SHA"
fi

echo
echo "############ STEP 1: install core + core-libs (OLD) + pyindi-client together ############"
apt-get install -y $(old_core_debs) "$PYINDI_DEB" \
  >"$W/install-old.log" 2>&1 \
  || { tail -30 "$W/install-old.log"; die "installing old core + pyindi-client failed"; }
PYINDI_VER_PRE=$(dpkg-query -W -f='${Version}' indi-stable-pyindi-client)
CORE_VER_PRE=$(dpkg-query -W -f='${Version}' indi-stable-core-libs)
info "pyindi-client: $PYINDI_VER_PRE    core-libs: $CORE_VER_PRE"

echo
echo "############ STEP 2: COEXISTENCE -- fresh install, distro INDI still present ############"
SO=$(so_path)
test -n "$SO" || die "the compiled extension is not where expected ($SO_GLOB) -- did the package layout change?"
info "extension: $SO"
if python3 -c 'import PyIndi; c = PyIndi.BaseClient(); assert hasattr(c, "setServer")' 2>&1; then
  pass "import PyIndi; PyIndi.BaseClient() succeeds on a fresh install"
else
  fail "import PyIndi failed on a fresh install"
fi
LDD_TARGET=$(ldd "$SO" 2>/dev/null | awk '/libindiclient\.so\.2/ {print $3}')
info "libindiclient.so.2 resolves to: ${LDD_TARGET:-<not found>}"
case "$LDD_TARGET" in
  /opt/indi-stable/lib/*) pass "resolves into the private prefix, not the distribution's identical SONAME" ;;
  *) fail "did NOT resolve into /opt/indi-stable/lib -- got '${LDD_TARGET:-nothing}'" ;;
esac

echo
echo "############ STEP 3: THE UPGRADE -- core/-libs only, pyindi-client untouched ############"
echo "  (pyindi-client is not part of this dpkg transaction at all)"
dpkg -i $(new_core_debs) >"$W/upgrade.log" 2>&1
UPRC=$?
test "$UPRC" -eq 0 || { tail -30 "$W/upgrade.log"; die "the upgrade transaction itself failed (exit $UPRC)"; }
pass "the upgrade transaction succeeded"

echo
echo "############ STEP 4: did the upgrade happen, and did pyindi-client survive untouched? ############"
CORE_VER_POST=$(dpkg-query -W -f='${Version}' indi-stable-core-libs)
info "core-libs now: $CORE_VER_POST"
test "$CORE_VER_POST" != "$CORE_VER_PRE" \
  && pass "core-libs' version changed, so an upgrade really occurred" \
  || fail "core-libs still $CORE_VER_PRE -- nothing was upgraded and STEP 5 would prove nothing"
NEW_OWNER=$(dpkg -S "$SO" 2>/dev/null | cut -d: -f1)
info "$SO owned by: $NEW_OWNER"
test "$NEW_OWNER" = "indi-stable-pyindi-client" \
  && pass "the compiled extension is still owned by pyindi-client -- the package itself was not touched" \
  || fail "the extension's owning package changed: expected indi-stable-pyindi-client, got '$NEW_OWNER'"
PYINDI_VER_POST=$(dpkg-query -W -f='${Version}' indi-stable-pyindi-client)
test "$PYINDI_VER_POST" = "$PYINDI_VER_PRE" \
  && pass "indi-stable-pyindi-client's own version is unchanged ($PYINDI_VER_POST)" \
  || fail "indi-stable-pyindi-client's version changed across a core-only upgrade: $PYINDI_VER_PRE -> $PYINDI_VER_POST"
if dpkg -V indi-stable-pyindi-client >"$W/pyindi-verify.log" 2>&1; then
  pass "dpkg -V clean on indi-stable-pyindi-client after the core upgrade"
else
  fail "dpkg -V reports pyindi-client modified by the core upgrade:"
  sed 's/^/    /' "$W/pyindi-verify.log"
fi

echo
echo "############ STEP 5: THE POINT -- does it still work after core moved underneath it? ############"
if python3 -c 'import PyIndi; c = PyIndi.BaseClient(); assert hasattr(c, "setServer")' 2>&1; then
  pass "import PyIndi; PyIndi.BaseClient() STILL succeeds after core-libs was upgraded"
else
  fail "import PyIndi FAILED after the core upgrade -- this is exactly the risk this test exists for"
fi
LDD_TARGET2=$(ldd "$SO" 2>/dev/null | awk '/libindiclient\.so\.2/ {print $3}')
info "libindiclient.so.2 now resolves to: ${LDD_TARGET2:-<not found>}"
case "$LDD_TARGET2" in
  /opt/indi-stable/lib/*) pass "still resolves into the private prefix after the upgrade" ;;
  *) fail "no longer resolves into /opt/indi-stable/lib -- got '${LDD_TARGET2:-nothing}'" ;;
esac
RESOLVED_LIB=$(readlink -f "$LDD_TARGET2" 2>/dev/null)
NEW_SO_OWNER=$(dpkg -S "$RESOLVED_LIB" 2>/dev/null | cut -d: -f1)
info "$RESOLVED_LIB owned by: $NEW_SO_OWNER (version should now be $CORE_VER_POST)"
test "$NEW_SO_OWNER" = "indi-stable-core-libs" \
  && pass "the library pyindi-client just resolved really is core-libs' file, not a stale cached copy" \
  || fail "the resolved library is owned by '$NEW_SO_OWNER', expected indi-stable-core-libs"

echo
echo "############ STEP 6: the distro binary is still a bystander ############"
if test "$DISTRO_COLLIDES" -eq 1; then
  dpkg -V libindi1 >/dev/null 2>&1 && pass "dpkg -V libindi1 still clean" \
                                    || fail "dpkg -V libindi1 now reports modifications"
fi
if test -n "$DISTRO_INDISERVER_SHA"; then
  test "$(sha256sum /usr/bin/indiserver | awk '{print $1}')" = "$DISTRO_INDISERVER_SHA" \
    && pass "/usr/bin/indiserver unchanged across coexistence + upgrade" \
    || fail "/usr/bin/indiserver CHANGED across coexistence + upgrade"
fi

echo
echo "############ STEP 7: full removal, restore by diffing, CONTROL -- import fails again ############"
TO_REMOVE=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
              indi-stable-core indi-stable-core-libs indi-stable-pyindi-client 2>/dev/null \
            | awk '$1 ~ /^i/ {print $2}')
info "removing: $(echo "$TO_REMOVE" | tr '\n' ' ')"
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

# Same control as core's and 3rdparty-libs' own upgrade tests: prove the
# added/removed comparison can actually see a planted difference before
# trusting its silence (LESSONS_LEARNED.md #1).
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
                         || pass "/opt/indi-stable fully removed, even after coexistence + an upgrade in between"

if python3 -c 'import PyIndi' 2>/dev/null; then
  fail "CONTROL: 'import PyIndi' still succeeds after full removal -- STEP 2/5's passes cannot be trusted"
else
  ctl "'import PyIndi' correctly fails again after removal, so STEP 2/5's passes were real"
fi

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "PYINDI-CLIENT DEB COEXIST + UPGRADE PATH: ALL CHECKS PASSED"
else
  echo "PYINDI-CLIENT DEB COEXIST + UPGRADE PATH: ONE OR MORE CHECKS FAILED"
fi
echo "  logs: $W"
echo "==================================================================="
exit "$FAIL"
