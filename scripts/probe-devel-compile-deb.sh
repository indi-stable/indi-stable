#
# The measuring half of scripts/test-devel-compile-deb.sh. Not run directly:
# the driver installs both trees and runs this where they both exist, as root.
# Kept separate for the same reason scripts/inchroot-devel-compile.sh is: the
# driver decides WHERE the compile happens, this decides WHAT is measured, and
# a chroot driver added later can reuse this file unchanged.
#
# What it measures, mirroring the Fedora probe:
#   1. the Libs:/Cflags: of the INSTALLED libindi.pc -- the artifact, not the
#      build log (LESSONS_LEARNED.md #2)
#   2. a consumer built with PKG_CONFIG_PATH=<ours> links, RUNS, and resolves
#      libindiclient.so.2 to /opt/indi-stable
#   3. both include spellings -- <indiversion.h> and <libindi/indiversion.h> --
#      open OUR headers under PKG_CONFIG_PATH, and the DISTRIBUTION's without it
#   4. CONTROL: the same consumer built against a scratch .pc carrying
#      upstream's unfixed lines must behave DIFFERENTLY (LESSONS_LEARNED.md #1
#      and #15)
#   5. Debian-only: what dpkg-shlibdeps generates for a consumer of our private
#      libraries. That is the mechanism by which shadowing would actually
#      happen on Debian -- see scripts/test-apt-depsolve.sh for why apt itself
#      cannot see sonames.
#
# DATA_INSTALL_DIR is the probe that tells the two trees apart: ours says
# /opt/indi-stable/share/indi/, the distribution's /usr/share/indi/. Version
# strings cannot -- both are 2.2.4 (LESSONS_LEARNED.md #11).
#
set -u
FAIL=0
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }
ctl()  { echo "  CONTROL: $*"; }
info() { echo "  ....  $*"; }

OURPC=/opt/indi-stable/lib/pkgconfig/libindi.pc
OURPATH=/opt/indi-stable/lib/pkgconfig
OURLIB=/opt/indi-stable/lib
OURH=/opt/indi-stable/include/libindi/indiversion.h
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)
DISTROPC=/usr/lib/$MULTIARCH/pkgconfig/libindi.pc
DISTROLIB=/usr/lib/$MULTIARCH
DISTROH=/usr/include/libindi/indiversion.h
WORK=${PROBE_WORK:-$(mktemp -d /tmp/probe-devel.XXXXXX)}

echo
echo "############ STEP 1: both trees really are here ############"
# Assert the driver's install landed rather than inferring it from an exit
# status: every measurement below is about which of two trees wins, and with
# only one present they would all pass while testing nothing
# (LESSONS_LEARNED.md #5).
for p in indi-stable-core indi-stable-core-libs indi-stable-core-dev libindi1 libindi-dev; do
  if dpkg -s "$p" >/dev/null 2>&1; then
    echo "  present: $p $(dpkg-query -W -f='${Version}' "$p")"
  else
    echo "*** ABORT: $p is not installed -- the comparison below would be vacuous ***"; exit 1
  fi
done
command -v g++ >/dev/null 2>&1 || { echo "*** ABORT: no g++ ***"; exit 1; }
test -f "$DISTROPC" || { echo "*** ABORT: the distribution's libindi.pc ($DISTROPC) is missing ***"; exit 1; }
test -f "$OURPC"    || { echo "*** ABORT: $OURPC missing ***"; exit 1; }
test -f "$DISTROH"  || { echo "*** ABORT: $DISTROH missing -- there is no second header tree to be shadowed by ***"; exit 1; }
info "multiarch: $MULTIARCH"

echo
echo "############ STEP 2: the INSTALLED libindi.pc ############"
grep -E '^(Libs|Cflags):' "$OURPC" | sed 's/^/      /'
grep -qxF 'Libs: -L${libdir} -Wl,-rpath,${libdir} -lindiclient' "$OURPC" \
  && pass "Libs: carries -Wl,-rpath,\${libdir}" || fail "Libs: line is not the fixed one"
grep -qxF 'Cflags: -I${includedir} -I${includedir}/libindi' "$OURPC" \
  && pass "Cflags: carries -I\${includedir}" || fail "Cflags: line is not the fixed one"
info "the distribution's own .pc: $(grep -E '^(Libs|Cflags):' "$DISTROPC" | tr '\n' ' ')"

# The pre-fix .pc, reconstructed from ours by undoing both edits. It is the
# control for everything below: a check that passes by finding nothing has to
# be shown able to find something, and here the something is the defect these
# two lines were added to fix (LESSONS_LEARNED.md #1, #15).
mkdir -p "$WORK/unfixed"
sed -e 's|^Libs: -L${libdir} -Wl,-rpath,${libdir} -lindiclient|Libs: -L${libdir} -lindiclient|' \
    -e 's|^Cflags: -I${includedir} -I${includedir}/libindi|Cflags: -I${includedir}/libindi|' \
    "$OURPC" > "$WORK/unfixed/libindi.pc"
grep -qxF 'Libs: -L${libdir} -lindiclient' "$WORK/unfixed/libindi.pc" \
  && grep -qxF 'Cflags: -I${includedir}/libindi' "$WORK/unfixed/libindi.pc" \
  || { echo "*** ABORT: could not reconstruct the pre-fix .pc -- the controls below would test nothing ***"; exit 1; }
info "control .pc written to $WORK/unfixed/libindi.pc, carrying upstream's unfixed lines"

echo
echo "############ STEP 3: what pkg-config hands a consumer, per condition ############"
for cond in ours unfixed distro; do
  case $cond in
    ours)    P=$OURPATH ;;
    unfixed) P=$WORK/unfixed ;;
    distro)  P= ;;
  esac
  printf '  %-8s cflags: %s\n' "$cond" "$(PKG_CONFIG_PATH=$P pkg-config --cflags libindi)"
  printf '  %-8s libs:   %s\n' "$cond" "$(PKG_CONFIG_PATH=$P pkg-config --libs libindi)"
done

cat > "$WORK/consumer.cpp" <<'CPP'
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

build() {   # $1 label, $2 PKG_CONFIG_PATH (empty = pkg-config's default path)
  local label=$1 pcp=$2 cf libs
  cf=$(PKG_CONFIG_PATH=$pcp pkg-config --cflags libindi)
  libs=$(PKG_CONFIG_PATH=$pcp pkg-config --libs libindi)
  if g++ $cf "$WORK/consumer.cpp" -o "$WORK/consumer-$label" $libs 2>"$WORK/build-$label.err"; then
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
  fail "did not compile"; sed 's/^/        /' "$WORK/build-ours.err" | head -10
fi
if test -x "$WORK/consumer-ours"; then
  OUT=$(timeout 30 "$WORK/consumer-ours" 2>&1); RC=$?
  echo "$OUT" | sed 's/^/        /'
  test $RC -eq 0 && pass "RUNS, exit 0" \
    || fail "exited $RC -- linking without running is exactly what the RPATH fix exists to prevent"
  case $OUT in
    *"DATA_INSTALL_DIR=/opt/indi-stable/share/indi/"*) pass "it compiled against OUR headers" ;;
    *) fail "DATA_INSTALL_DIR is not ours -- it compiled against another tree" ;;
  esac
  RP=$(readelf -d "$WORK/consumer-ours" | grep -E 'RPATH|RUNPATH' | sed 's/^ *//')
  info "dynamic tag: ${RP:-(none)}"
  case $RP in
    *"$OURLIB"*) pass "carries an rpath into our private libdir" ;;
    *) fail "no $OURLIB rpath -- the Libs: fix did not reach the binary" ;;
  esac
  LD=$(ldd "$WORK/consumer-ours" | grep libindiclient | sed 's/^ *//')
  info "ldd: $LD"
  case $LD in
    *"$OURLIB/libindiclient.so.2"*) pass "libindiclient.so.2 resolves to OUR copy" ;;
    *) fail "libindiclient.so.2 did not resolve to ours" ;;
  esac
fi

echo
echo "############ STEP 5: CONTROL -- the same consumer, pre-fix .pc ############"
# Without the RPATH the link still succeeds; what changes is what the loader
# finds at startup. On a box carrying the distribution's libindiclient.so.2 --
# which is the whole point of this project -- the failure is not a missing
# library but the WRONG one, silently (LESSONS_LEARNED.md #16).
if test "$(build unfixed "$WORK/unfixed")" = COMPILED; then
  ctl "pre-fix .pc still compiles and links -- the defect is invisible at link time"
else
  info "pre-fix .pc did not even compile:"; sed 's/^/        /' "$WORK/build-unfixed.err" | head -10
fi
if test -x "$WORK/consumer-unfixed"; then
  RPU=$(readelf -d "$WORK/consumer-unfixed" | grep -E 'RPATH|RUNPATH' | sed 's/^ *//')
  info "dynamic tag: ${RPU:-(none)}"
  test -z "$RPU" && ctl "no rpath at all, as expected pre-fix" \
                 || fail "the pre-fix binary carries an rpath ($RPU) -- then STEP 4's rpath proves nothing about the fix"
  LDU=$(ldd "$WORK/consumer-unfixed" | grep libindiclient | sed 's/^ *//')
  info "ldd: ${LDU:-(libindiclient not listed)}"
  case $LDU in
    *"/opt/indi-stable"*) fail "the pre-fix binary ALSO resolves to ours -- STEP 4 cannot distinguish the fix from the default" ;;
    *"not found"*)        ctl "pre-fix: libindiclient.so.2 NOT FOUND at runtime" ;;
    *"$DISTROLIB"*)       ctl "pre-fix: silently resolves to the DISTRIBUTION's copy under $DISTROLIB -- no error, wrong library. LESSONS_LEARNED.md #16: the omission is LOUD only on a box that has no other copy, and this box is the configuration that matters" ;;
    *)                    info "pre-fix resolution: ${LDU:-none}" ;;
  esac
  OUTU=$(timeout 30 "$WORK/consumer-unfixed" 2>&1); RCU=$?
  echo "$OUTU" | sed 's/^/        /'
  info "pre-fix consumer exited $RCU"
fi

echo
echo "############ STEP 6: which tree does each #include spelling open? ############"
# g++ -E -H prints every header it opens, one per line, prefixed by depth dots.
# Both spellings must land in the SAME tree as the .pc that supplied the flags;
# a mismatch is silent at compile time and is what the Cflags: fix prevents.
printf '#include <indiversion.h>\n'         > "$WORK/inc-bare.cpp"
printf '#include <libindi/indiversion.h>\n' > "$WORK/inc-qual.cpp"

probe_include() {   # $1 label, $2 PKG_CONFIG_PATH, $3 source, $4 expected file
  local label=$1 pcp=$2 src=$3 want=$4 cf got slug err
  slug=$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')
  err=$WORK/h-$slug.err
  cf=$(PKG_CONFIG_PATH=$pcp pkg-config --cflags libindi)
  if ! g++ -E -H $cf "$src" -o /dev/null 2>"$err"; then
    fail "$label: preprocessing failed -- $(head -1 "$err")"; return
  fi
  got=$(grep -o '[^ ]*indiversion\.h' "$err" | head -1)
  test -n "$got" || { fail "$label: -H printed no indiversion.h line -- the probe measured nothing"; return; }
  if test "$got" = "$want"; then pass "$label -> $got"; else fail "$label -> $got  (expected $want)"; fi
}

probe_include "ours,    <indiversion.h>        " "$OURPATH" "$WORK/inc-bare.cpp" "$OURH"
probe_include "ours,    <libindi/indiversion.h>" "$OURPATH" "$WORK/inc-qual.cpp" "$OURH"
probe_include "distro,  <indiversion.h>        " ""         "$WORK/inc-bare.cpp" "$DISTROH"
probe_include "distro,  <libindi/indiversion.h>" ""         "$WORK/inc-qual.cpp" "$DISTROH"

echo "  -- CONTROL: the same two spellings against the pre-fix .pc --"
CF_U=$(PKG_CONFIG_PATH=$WORK/unfixed pkg-config --cflags libindi)
g++ -E -H $CF_U "$WORK/inc-bare.cpp" -o /dev/null 2>"$WORK/h-u-bare.err"
g++ -E -H $CF_U "$WORK/inc-qual.cpp" -o /dev/null 2>"$WORK/h-u-qual.err"
UB=$(grep -o '[^ ]*indiversion\.h' "$WORK/h-u-bare.err" | head -1)
UQ=$(grep -o '[^ ]*indiversion\.h' "$WORK/h-u-qual.err" | head -1)
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
echo "############ STEP 7: RUNPATH on a shipped driver ############"
# indiserver links no INDI library at all, so a DRIVER is the right subject.
for b in /opt/indi-stable/bin/indi_simulator_ccd "$OURLIB/libindidriver.so.2"; do
  test -e "$b" || { fail "$b missing"; continue; }
  info "$(basename "$b"): $(readelf -d "$b" | grep -E 'RPATH|RUNPATH' | sed 's/^ *//' | tr '\n' ' ')"
done
DRV=/opt/indi-stable/bin/indi_simulator_ccd
if test -x "$DRV"; then
  TAG=$(readelf -d "$DRV" | grep -oE 'RPATH|RUNPATH' | head -1)
  info "this toolchain emits DT_$TAG for our drivers"
  L=$(ldd "$DRV" | grep libindidriver | sed 's/^ *//')
  info "ldd: $L"
  case $L in
    *"$OURLIB/libindidriver.so.2"*) pass "driver resolves libindidriver.so.2 to OUR copy" ;;
    *) fail "driver did not resolve to ours: $L" ;;
  esac
fi

echo
echo "############ STEP 8: what does dpkg-shlibdeps generate for a consumer of ours? ############"
# The Debian-only question, and the one that matters most for shadowing here.
# apt cannot see sonames, so the package name a consumer ends up depending on
# is chosen at the CONSUMER's build time by dpkg-shlibdeps, from the .shlibs of
# whichever installed package owns the library. Our packages ship no .shlibs
# (scripts/test-apt-depsolve.sh STEP 2 proves that from the artifacts), so the
# question is what dpkg-shlibdeps does when it meets our library anyway --
# reachable through the consumer's RUNPATH.
#
# Two answers would be defects, and they are the two asserted against:
#   * naming indi-stable-core-libs -- we would be advertising ourselves as a
#     system-wide provider of libindiclient.so.2;
#   * naming libindi1 -- a consumer of OUR library would get a dependency on
#     the DISTRIBUTION's package, which is silently the wrong library.
# Anything else, including a hard error, is loud and therefore safe.
SD=$WORK/shlibdeps; rm -rf "$SD"; mkdir -p "$SD/debian"
printf 'Source: probe\n\nPackage: probe\nArchitecture: any\nDescription: probe for scripts/probe-devel-compile-deb.sh\n .\n' > "$SD/debian/control"
run_shlibdeps() {   # $1 binary
  ( cd "$SD" && dpkg-shlibdeps -O "$1" 2>&1 )
}
if test -x "$WORK/consumer-ours"; then
  OURS_DEPS=$(run_shlibdeps "$WORK/consumer-ours")
  echo "$OURS_DEPS" | sed 's/^/        /'
  case $OURS_DEPS in
    *indi-stable-core-libs*)
      fail "dpkg-shlibdeps named indi-stable-core-libs -- our private libraries are being advertised as a system-wide provider" ;;
    *libindi1*)
      fail "dpkg-shlibdeps named libindi1 for a consumer of OUR library -- the generated dependency points at the distribution's package while the binary links ours" ;;
    *)
      pass "dpkg-shlibdeps named neither indi-stable-core-libs nor libindi1 for a consumer built against ours" ;;
  esac
fi
echo "  -- CONTROL: the same tool on a consumer built against the DISTRIBUTION --"
# STEP 8 passes by NOT finding two package names, so the tool has to be shown
# able to produce one at all (LESSONS_LEARNED.md #1). Built with pkg-config's
# default path, this consumer links the distribution's library and MUST come
# back with libindi1.
if test "$(build distro "")" = COMPILED; then
  DISTRO_DEPS=$(run_shlibdeps "$WORK/consumer-distro")
  echo "$DISTRO_DEPS" | sed 's/^/        /'
  case $DISTRO_DEPS in
    *libindi1*) ctl "dpkg-shlibdeps DOES emit libindi1 for a consumer of the distribution's library -- so its silence about our packages above is a real result, not a tool that produced nothing" ;;
    *)          fail "CONTROL BROKEN: dpkg-shlibdeps did not name libindi1 even for a consumer linked against the distribution's library. It is producing nothing, so STEP 8's pass means nothing" ;;
  esac
else
  fail "could not build a distribution-linked consumer -- STEP 8 keeps no positive control"
  sed 's/^/        /' "$WORK/build-distro.err" | head -10
fi

echo
if test "$FAIL" -eq 0; then echo "PROBE RESULT: ALL CHECKS PASSED"; else echo "PROBE RESULT: FAILURES ABOVE"; fi
echo "  probe work dir: $WORK"
exit "$FAIL"
