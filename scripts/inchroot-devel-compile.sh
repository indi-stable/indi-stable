#
# The in-chroot half of scripts/test-devel-compile-mock.sh. Not run directly:
# the driver copies it into a mock chroot that already has both INDIs and a
# compiler, and runs it there as root. See that script's header for why the
# compile happens in a chroot at all.
#
set -u
FAIL=0
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

OURPC=/opt/indi-stable/lib/pkgconfig/libindi.pc
OURPATH=/opt/indi-stable/lib/pkgconfig

echo
echo "############ STEP 1b: both trees really are in this chroot ############"
# Assert the driver's install transaction landed rather than inferring it from
# mock exiting 0: every measurement below is about which of two trees wins, and
# with only one present they would all pass while testing nothing.
for p in indi-stable-core indi-stable-core-libs indi-stable-core-devel libindi libindi-libs libindi-devel; do
  if rpm -q "$p" >/dev/null 2>&1; then echo "  present: $(rpm -q "$p")"
  else echo "*** ABORT: $p is not installed in the chroot -- the comparison below would be vacuous ***"; exit 1; fi
done
command -v g++ >/dev/null 2>&1 || { echo "*** ABORT: no g++ in the chroot ***"; exit 1; }
test -f /usr/lib64/pkgconfig/libindi.pc || { echo "*** ABORT: the distribution's libindi.pc is missing ***"; exit 1; }

echo
echo "############ STEP 2: the INSTALLED libindi.pc ############"
test -f "$OURPC" || { echo "*** ABORT: $OURPC missing ***"; exit 1; }
grep -E '^(Libs|Cflags):' "$OURPC" | sed 's/^/    /'
grep -qxF 'Libs: -L${libdir} -Wl,-rpath,${libdir} -lindiclient' "$OURPC" \
  && pass "Libs: carries -Wl,-rpath,\${libdir}" || fail "Libs: line is not the fixed one"
grep -qxF 'Cflags: -I${includedir} -I${includedir}/libindi' "$OURPC" \
  && pass "Cflags: carries -I\${includedir}" || fail "Cflags: line is not the fixed one"
info "the distribution's own .pc: $(grep -E '^(Libs|Cflags):' /usr/lib64/pkgconfig/libindi.pc | tr '\n' ' ')"

# The pre-fix .pc, reconstructed from ours by undoing both edits. It is the
# control for everything below: a check that passes by finding nothing has to
# be shown able to find something (LESSONS_LEARNED.md #1), and here the
# something is the defect these two lines were added to fix.
mkdir -p /root/unfixed
sed -e 's|^Libs: -L${libdir} -Wl,-rpath,${libdir} -lindiclient|Libs: -L${libdir} -lindiclient|' \
    -e 's|^Cflags: -I${includedir} -I${includedir}/libindi|Cflags: -I${includedir}/libindi|' \
    "$OURPC" > /root/unfixed/libindi.pc
grep -qxF 'Libs: -L${libdir} -lindiclient' /root/unfixed/libindi.pc \
  && grep -qxF 'Cflags: -I${includedir}/libindi' /root/unfixed/libindi.pc \
  || { echo "*** ABORT: could not reconstruct the pre-fix .pc -- the controls below would test nothing ***"; exit 1; }
info "control .pc written to /root/unfixed/libindi.pc, carrying upstream's unfixed lines"

echo
echo "############ STEP 3: what pkg-config hands a consumer, per condition ############"
for cond in ours unfixed distro; do
  case $cond in
    ours)    P=$OURPATH ;;
    unfixed) P=/root/unfixed ;;
    distro)  P= ;;
  esac
  printf '  %-8s cflags: %s\n' "$cond" "$(PKG_CONFIG_PATH=$P pkg-config --cflags libindi)"
  printf '  %-8s libs:   %s\n' "$cond" "$(PKG_CONFIG_PATH=$P pkg-config --libs libindi)"
done

cat > /root/consumer.cpp <<'CPP'
#include <indiversion.h>
#include <baseclient.h>
#include <cstdio>
int main()
{
    // Heap-allocated and never deleted on purpose: the question is which
    // library got linked, not client lifetime.
    auto *c = new INDI::BaseClient();
    c->setServer("127.0.0.1", 7624);
    printf("DATA_INSTALL_DIR=%s\n", DATA_INSTALL_DIR);
    printf("INDI_VERSION=%s\n", INDI_VERSION);
    return 0;
}
CPP

# $1 label, $2 PKG_CONFIG_PATH (empty = pkg-config's default path)
build() {
  local label=$1 pcp=$2 cf libs
  cf=$(PKG_CONFIG_PATH=$pcp pkg-config --cflags libindi)
  libs=$(PKG_CONFIG_PATH=$pcp pkg-config --libs libindi)
  if g++ $cf /root/consumer.cpp -o /root/consumer-$label $libs 2>/root/build-$label.err; then
    echo COMPILED
  else
    echo COMPILE-FAILED
  fi
}

echo
echo "############ STEP 4: consumer built against OURS -- link, then RUN ############"
if test "$(build ours "$OURPATH")" = COMPILED; then
  pass "compiles and links"
else
  fail "did not compile"; sed 's/^/      /' /root/build-ours.err | head -10
fi
if test -x /root/consumer-ours; then
  OUT=$(timeout 30 /root/consumer-ours 2>&1); RC=$?
  echo "$OUT" | sed 's/^/      /'
  test $RC -eq 0 && pass "RUNS, exit 0" \
    || fail "exited $RC -- linking without running is exactly what the RPATH fix exists to prevent"
  case $OUT in
    *"DATA_INSTALL_DIR=/opt/indi-stable/share/indi/"*) pass "it compiled against OUR headers" ;;
    *) fail "DATA_INSTALL_DIR is not ours -- it compiled against another tree" ;;
  esac
  RP=$(readelf -d /root/consumer-ours | grep -E 'RPATH|RUNPATH' | sed 's/^ *//')
  info "dynamic tag: ${RP:-(none)}"
  case $RP in
    *"/opt/indi-stable/lib"*) pass "carries an rpath into our private libdir" ;;
    *) fail "no /opt/indi-stable/lib rpath -- the Libs: fix did not reach the binary" ;;
  esac
  LD=$(ldd /root/consumer-ours | grep libindiclient | sed 's/^ *//')
  info "ldd: $LD"
  case $LD in
    *"/opt/indi-stable/lib/libindiclient.so.2"*) pass "libindiclient.so.2 resolves to OUR copy" ;;
    *) fail "libindiclient.so.2 did not resolve to ours" ;;
  esac
fi

echo
echo "############ STEP 5: CONTROL -- the same consumer, pre-fix .pc ############"
# Without the RPATH the link still succeeds; what changes is what the loader
# finds at startup. On a box carrying the distribution's libindiclient.so.2 --
# which is the whole point of this project -- the failure is not a missing
# library but the WRONG one, silently.
if test "$(build unfixed /root/unfixed)" = COMPILED; then
  ctl "pre-fix .pc still compiles and links -- the defect is invisible at link time"
else
  info "pre-fix .pc did not even compile:"; sed 's/^/      /' /root/build-unfixed.err | head -10
fi
if test -x /root/consumer-unfixed; then
  RPU=$(readelf -d /root/consumer-unfixed | grep -E 'RPATH|RUNPATH' | sed 's/^ *//')
  info "dynamic tag: ${RPU:-(none)}"
  test -z "$RPU" && ctl "no rpath at all, as expected pre-fix" \
                 || fail "the pre-fix binary carries an rpath ($RPU) -- then STEP 4's rpath proves nothing about the fix"
  LDU=$(ldd /root/consumer-unfixed | grep libindiclient | sed 's/^ *//')
  info "ldd: ${LDU:-(libindiclient not listed)}"
  case $LDU in
    *"/opt/indi-stable"*) fail "the pre-fix binary ALSO resolves to ours -- STEP 4 cannot distinguish the fix from the default" ;;
    *"not found"*)        ctl "pre-fix: libindiclient.so.2 NOT FOUND at runtime" ;;
    */lib64/*)            ctl "pre-fix: silently resolves to the DISTRIBUTION's copy under ${LDU#*=> } -- ldd prints /lib64, the symlink to /usr/lib64" ;;
    *)                    info "pre-fix resolution: ${LDU:-none}" ;;
  esac
  OUTU=$(timeout 30 /root/consumer-unfixed 2>&1); RCU=$?
  echo "$OUTU" | sed 's/^/      /'
  info "pre-fix consumer exited $RCU"
fi

echo
echo "############ STEP 6: which tree does each #include spelling open? ############"
# g++ -E -H prints every header it opens, one per line, prefixed by depth dots.
# Both spellings must land in the SAME tree as the .pc that supplied the flags;
# a mismatch is silent at compile time and is what the Cflags: fix prevents.
printf '#include <indiversion.h>\n'          > /root/inc-bare.cpp
printf '#include <libindi/indiversion.h>\n'  > /root/inc-qual.cpp

probe_include() {   # $1 label, $2 PKG_CONFIG_PATH, $3 source, $4 expected dir
  # The label is prose and contains spaces; the log file needs a slug, and
  # every use of it needs quoting. The first version of this function
  # interpolated the label straight into a redirect, so all four calls died
  # with "ambiguous redirect" and reported a preprocessing failure that had
  # not happened -- LESSONS_LEARNED.md #1, in the check itself.
  local label=$1 pcp=$2 src=$3 want=$4 cf got slug err
  slug=$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')
  err=/root/h-$slug.err
  cf=$(PKG_CONFIG_PATH=$pcp pkg-config --cflags libindi)
  if ! g++ -E -H $cf "$src" -o /dev/null 2>"$err"; then
    fail "$label: preprocessing failed -- $(head -1 "$err")"; return
  fi
  got=$(grep -o '[^ ]*indiversion\.h' "$err" | head -1)
  test -n "$got" || { fail "$label: -H printed no indiversion.h line -- the probe measured nothing"; return; }
  if test "$got" = "$want"; then pass "$label -> $got"; else fail "$label -> $got  (expected $want)"; fi
}

OURH=/opt/indi-stable/include/libindi/indiversion.h
DISTROH=/usr/include/libindi/indiversion.h
probe_include "ours,    <indiversion.h>        " "$OURPATH"      /root/inc-bare.cpp "$OURH"
probe_include "ours,    <libindi/indiversion.h>" "$OURPATH"      /root/inc-qual.cpp "$OURH"
probe_include "distro,  <indiversion.h>        " ""              /root/inc-bare.cpp "$DISTROH"
probe_include "distro,  <libindi/indiversion.h>" ""              /root/inc-qual.cpp "$DISTROH"

echo "  -- CONTROL: the same two spellings against the pre-fix .pc --"
CF_U=$(PKG_CONFIG_PATH=/root/unfixed pkg-config --cflags libindi)
g++ -E -H $CF_U /root/inc-bare.cpp -o /dev/null 2>/root/h-u-bare.err
g++ -E -H $CF_U /root/inc-qual.cpp -o /dev/null 2>/root/h-u-qual.err
UB=$(grep -o '[^ ]*indiversion\.h' /root/h-u-bare.err | head -1)
UQ=$(grep -o '[^ ]*indiversion\.h' /root/h-u-qual.err | head -1)
info "pre-fix, <indiversion.h>         -> ${UB:-(failed)}"
info "pre-fix, <libindi/indiversion.h> -> ${UQ:-(failed)}"
if test "$UQ" = "$DISTROH"; then
  ctl "pre-fix: the qualified spelling reached the DISTRIBUTION's headers while linking OUR library -- the defect, reproduced"
elif test "$UQ" = "$OURH"; then
  fail "pre-fix: the qualified spelling ALSO reached ours -- then the Cflags: fix changes nothing here and STEP 6 proves nothing"
else
  info "pre-fix: qualified spelling resolved to ${UQ:-nothing}"
fi

echo
echo "############ STEP 7: RPATH or RUNPATH on a shipped driver? ############"
# STATUS.md asks this: on Ubuntu, CMake's --enable-new-dtags default emits
# DT_RUNPATH, which LD_LIBRARY_PATH can override. Fedora's toolchain may differ,
# and a driver is the right subject -- indiserver links no libindi library at
# all (FEDORA.md, checklist item 5).
for b in /opt/indi-stable/bin/indi_simulator_ccd /opt/indi-stable/lib/libindidriver.so.2; do
  test -e "$b" || { fail "$b missing"; continue; }
  info "$(basename "$b"): $(readelf -d "$b" | grep -E 'RPATH|RUNPATH' | sed 's/^ *//' | tr '\n' ' ')"
done
DRV=/opt/indi-stable/bin/indi_simulator_ccd
if test -x "$DRV"; then
  TAG=$(readelf -d "$DRV" | grep -oE 'RPATH|RUNPATH' | head -1)
  info "Fedora emits DT_$TAG for our drivers"
  L=$(ldd "$DRV" | grep libindidriver | sed 's/^ *//')
  info "ldd: $L"
  case $L in
    *"/opt/indi-stable/lib/libindidriver.so.2"*) pass "driver resolves libindidriver.so.2 to OUR copy" ;;
    *) fail "driver did not resolve to ours: $L" ;;
  esac
fi

echo
if test "$FAIL" -eq 0; then echo "IN-CHROOT RESULT: ALL CHECKS PASSED"; else echo "IN-CHROOT RESULT: FAILURES ABOVE"; fi
exit "$FAIL"
