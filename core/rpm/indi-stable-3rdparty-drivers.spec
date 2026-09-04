# indi-stable-3rdparty-drivers -- the INDI drivers for the same 9 vendors
# indi-stable-3rdparty-libs bundles the vendor SDKs for, built from the SAME
# upstream indi-3rdparty tag with -DBUILD_LIBS=OFF, so this build links
# against the -devel subpackages -libs already produces rather than building
# any vendor SDK a second time.
#
# Builds, installs and removes cleanly alongside indi-stable-core and
# indi-stable-3rdparty-libs as of 2026-08-26 (see STATUS.md) -- verified
# against distribution core INDI, same as -libs's own coexistence pass, and
# found no new defects doing it: the fixes -libs's own coexistence testing
# required (the __requires_exclude union, universal %%dir ownership) held
# with a third source package added to the mix. Upgrade-path testing hasn't
# been done yet. Took six real build failures to get to a clean build (see
# git history for this file) -- LESSONS_LEARNED.md #1/#2 held again. Fishcamp
# added 2026-08-27 once its licence was confirmed clear (DESIGN.md).
#
# Deliberately scoped to the SAME 9 vendors -libs bundles (apogee, asi, fli,
# playerone, inovasdk, micam, sbig, touptek, fishcamp) and no others.
# indi-3rdparty ships roughly 50 more drivers (eqmod, gpsd, celestronaux, ...)
# that need no vendor blob at all and have no dependency on -libs whatsoever
# -- a deliberately separate, not-yet-made scope decision (confirmed with
# Will, 2026-08-26). See STATUS.md, "3rdparty -- remaining".
#
# See DESIGN.md, "Resolution -- two source packages, not one and not
# sixty-one", for why this is a second source package rather than a second
# phase of -libs's own spec, and for the Fedora precedent
# (indi-3rdparty-drivers.spec, fetched from dist-git) this shape follows.

%global indi_prefix     /opt/indi-stable
%global indi_libdir     %{indi_prefix}/lib
%global indi_includedir %{indi_prefix}/include
%global indi_bindir     %{indi_prefix}/bin
%global indi_datadir    %{indi_prefix}/share/indi

# Same pattern as -libs: GitHub strips the leading v from the tag name, but
# CMake's own project version (and this spec's Version:) does not carry it.
%global upstream_tag    v%{version}

# --- Dependency-generator filtering -----------------------------------------
# Provides: same rule as -libs and core, same reason -- nothing under the
# private prefix should ever be advertised system-wide.
#
# Requires: the UNION of core's own exclude pattern and -libs's own, because
# these driver binaries are the first thing in this project that links
# against BOTH families at once. Each add_executable() here pulls in
# ${INDI_LIBRARIES} (libindidriver.so, libindiAlignmentDriver.so, ...) AND
# the matching vendor library from -libs (libapogee.so.3, libASICamera2.so.1,
# ...) -- both already Provides-excluded by core.spec and indi-stable-
# 3rdparty-libs.spec respectively, so BOTH families of auto-generated
# soname Requires would be unsatisfiable here for exactly the reason
# LESSONS_LEARNED.md #-adjacent-to-21 documents for -libs's own -devel
# packages. The vendor SONAME list is copied verbatim from -libs's own
# __requires_exclude (same libraries, same reason); libindi.*  is copied
# verbatim from core's.
%global __provides_exclude_from ^%{indi_prefix}/.*$
%global __requires_exclude      ^lib(indi.*|apogee|ASICamera2|CAARotator|EAFFocuser|EFWFilter|USB2ST4Conv|fli|fishcamp|inovasdk|gxccd|PlayerOneCamera|PlayerOnePW|sbig|altaircam|bressercam|mallincam|meadecam|nncam|ogmacam|omegonprocam|starshootg|svbonycam|toupcam|tscam)\\.so.*$

Name:           indi-stable-3rdparty-drivers
Version:        2.2.4.1
Release:        1%{?dist}
Summary:        INDI drivers for 9 vendor camera/focuser SDKs (stable upstream release, private prefix)

# Aggregate across 9 driver source trees, confirmed by reading actual SOURCE
# FILE license headers (not the bundled COPYING file alone -- two of them,
# apogee's and sbig's, are stale "Library GPL v2" text left over from before
# upstream's own 2.1 relicense, contradicted by every .cpp header in both
# directories, which explicitly grant "version 2.1 ... or (at your option)
# any later version"). Confirmed per vendor:
#   apogee, asi, fli, playerone,
#   micam, sbig, touptek,
#   fishcamp                  -- LGPL-2.1-or-later, per .cpp header grants
#                                 (spot-checked one representative source
#                                 file per vendor directory; not a full
#                                 per-file audit -- same caveat -libs's own
#                                 License: comment already carries). fishcamp
#                                 added 2026-08-27, indi_fishcamp.cpp's own
#                                 header reads "version 2.1 ... or (at your
#                                 option) any later version" verbatim, same
#                                 shape as its seven siblings here.
#   inovasdk                  -- LGPL-2.0-only. The ONLY signal in this one
#                                 directory is its bundled COPYING.LIB (the
#                                 stale v2 text again), and unlike the other
#                                 8 no source file here carries ANY licence
#                                 header at all -- no "or later" grant to
#                                 upgrade the tag with, so the conservative,
#                                 defensible reading is the plain v2 text as
#                                 written, not v2.1-or-later by analogy to
#                                 its siblings.
# %%license below points at indi-3rdparty's own top-level LICENSE (correct
# 2.1 text) rather than apogee's/fli's/micam's/sbig's own bundled files where
# those are missing or stale -- packaging a license file whose TEXT actually
# matches the declared tag, not merely whatever happened to be closest.
License:        LGPL-2.1-or-later AND LGPL-2.0-only
URL:            https://github.com/indilib/indi-3rdparty
Source0:        https://github.com/indilib/indi-3rdparty/archive/refs/tags/%{upstream_tag}.tar.gz#/indi-3rdparty-%{upstream_tag}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  systemd-rpm-macros
# find_package(INDI REQUIRED) in every one of the 9 driver CMakeLists.txt.
BuildRequires:  indi-stable-core-devel
# find_package(CFITSIO REQUIRED) in every one of the 9.
BuildRequires:  cfitsio-devel
# find_package(ZLIB REQUIRED) in 8 of 9 (all but indi-mi); harmless to pull
# in for indi-mi's own configure pass too.
BuildRequires:  zlib-devel
# find_package(USB1 REQUIRED): asi, playerone, micam, sbig, fishcamp.
BuildRequires:  libusb1-devel
# The 9 vendor -devel subpackages this build configures against. Pinned to
# THIS package's own %%version-%%release, not core's -- indi-3rdparty is a
# genuinely independent version axis from core (DESIGN.md), but -libs and
# -drivers share one upstream tag and are always built and promoted together
# (the same discipline Fedora's own two specs use, `= %%{version}` there).
BuildRequires:  indi-stable-3rdparty-libs-apogee-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-asi-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-fli-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-playerone-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-inovasdk-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-micam-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-sbig-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-touptek-devel = %{version}-%{release}
BuildRequires:  indi-stable-3rdparty-libs-fishcamp-devel = %{version}-%{release}

%description
INDI drivers for the 9 vendor camera/focuser SDKs indi-stable-3rdparty-libs
bundles, built with -DBUILD_LIBS=OFF from the same upstream indi-3rdparty tag
that project builds from with -DBUILD_LIBS=ON.

Installs into %{indi_prefix}, the same private prefix as indi-stable-core and
indi-stable-3rdparty-libs, so it never collides with any distribution-
provided INDI or driver package. Only drivers for the 9 already-bundled
vendors are built here -- see DESIGN.md for the scope decision.

This is an unofficial third-party build. It is not affiliated with or
endorsed by the INDI project.

%package apogee
Summary:        Apogee CCD/filter-wheel INDI drivers
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-apogee%{?_isa} = %{version}-%{release}
%description apogee
indi_apogee_ccd and indi_apogee_wheel, linked against the bundled Apogee SDK
(indi-stable-3rdparty-libs-apogee).

%package asi
Summary:        ZWO Optics ASI camera/filter-wheel/focuser/rotator INDI drivers
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-asi%{?_isa} = %{version}-%{release}
%description asi
indi_asi_ccd, indi_asi_single_ccd, indi_asi_wheel, indi_asi_st4,
indi_asi_focuser and indi_asi_rotator, linked against the bundled ZWO ASI SDK
(indi-stable-3rdparty-libs-asi).

%package fli
Summary:        Finger Lakes Instrumentation INDI drivers
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-fli%{?_isa} = %{version}-%{release}
%description fli
indi_fli_ccd, indi_fli_focus and indi_fli_wheel, linked against the bundled
FLI SDK (indi-stable-3rdparty-libs-fli). Does NOT include the Kepler camera
driver (indi_kepler_ccd) or its indi_flipro.xml -- both are gated by
find_package(FLIPRO) inside indi-fli/CMakeLists.txt, which self-excludes
here because indi-stable-3rdparty-libs deliberately does not package
flipro/flialgo (still-undecided licence coverage, see STATUS.md); nothing
special needs to be done in this spec for that, it is a natural consequence
of what -libs already leaves out.

%package playerone
Summary:        Player One Astronomy camera/filter-wheel INDI drivers
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-playerone%{?_isa} = %{version}-%{release}
%description playerone
indi_playerone_ccd, indi_playerone_single_ccd and indi_playerone_wheel,
linked against the bundled Player One SDK
(indi-stable-3rdparty-libs-playerone).

%package inovasdk
Summary:        i.Nova Technologies focuser INDI driver
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-inovasdk%{?_isa} = %{version}-%{release}
%description inovasdk
indi_inovaplx_ccd, linked against the bundled i.Nova SDK
(indi-stable-3rdparty-libs-inovasdk).

%package micam
Summary:        Moravian Instruments camera/filter-wheel INDI drivers
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-micam%{?_isa} = %{version}-%{release}
%description micam
indi_mi_ccd and indi_mi_sfw, linked against the bundled Moravian SDK
(indi-stable-3rdparty-libs-micam). Upstream's own driver source directory is
named indi-mi; this subpackage is named micam to match the sibling -libs
subpackage it Requires.

%package sbig
Summary:        Santa Barbara Instrument Group camera INDI driver
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-sbig%{?_isa} = %{version}-%{release}
%description sbig
indi_sbig_ccd, linked against the bundled SBIG SDK
(indi-stable-3rdparty-libs-sbig).

%package fishcamp
Summary:        Fishcamp Engineering CCD camera INDI driver
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-fishcamp%{?_isa} = %{version}-%{release}
%description fishcamp
indi_fishcamp_ccd, linked against the bundled Fishcamp library
(indi-stable-3rdparty-libs-fishcamp). Added 2026-08-27 once Fishcamp's
licence was confirmed clear (DESIGN.md).

%package touptek
Summary:        Touptek and rebranded-Touptek camera INDI drivers (11 brands)
Requires:       indi-stable-core-libs%{?_isa}
Requires:       indi-stable-3rdparty-libs-touptek%{?_isa} = %{version}-%{release}
%description touptek
indi_<brand>_ccd, indi_<brand>_wheel and indi_<brand>_focuser for all eleven
Touptek-family brands (Toupcam, Altair, Bresser, Mallincam, Meade, Nncam,
Ogmacam, Omegon, StarShootG, TSCam, SVBONYCAM), linked against the bundled
SDKs (indi-stable-3rdparty-libs-touptek). Same eleven-brands-one-package
shape as -libs's own touptek subpackage, for the same reason: one
CMakeLists.txt macro (`build_touptek_driver`) builds all eleven from a
single loop.

%prep
# GitHub strips the leading v: tag v2.2.4.1 unpacks to indi-3rdparty-2.2.4.1.
%autosetup -n indi-3rdparty-%{version} -p1

# toupcam_test and omegonprocam_test are vendor SDK diagnostic CLI tools,
# not INDI drivers -- unlike asi's and playerone's own test/bench
# executables, indi-toupbase/CMakeLists.txt never install()s either of
# them, so they were never going to be packaged regardless. Found on the
# first real build (2026-08-26): ninja builds cmake's default "all" target,
# which includes every add_executable() regardless of whether anything
# installs it, and omegonprocam_test.cpp fails to compile outright
# (missing libomegonprocam/omegonprocam.h -- an upstream include-path bug
# this project has no need to chase down, since the file was never wanted).
# EXCLUDE_FROM_ALL keeps cmake's target graph intact (unlike deleting the
# add_executable block, which would be fragile against a multi-line
# target_link_libraries() call right after it) while keeping ninja from
# ever trying to build either one. Safe specifically because neither has an
# install() rule -- if one did, excluding it from the default build target
# would just move this same failure from %%build to %%install ("cannot
# find target file") instead of fixing it.
# Both lines are indented (inside their WITH_<BRAND>CAM if() blocks), so the
# match must not anchor to column 1 -- an earlier version of this patch did
# and silently matched nothing, which rpmbuild's own %%build failure on the
# very same omegonprocam_test.cpp compile error caught immediately.
sed -i '/add_executable(toupcam_test /a set_target_properties(toupcam_test PROPERTIES EXCLUDE_FROM_ALL TRUE)' indi-toupbase/CMakeLists.txt
sed -i '/add_executable(omegonprocam_test /a set_target_properties(omegonprocam_test PROPERTIES EXCLUDE_FROM_ALL TRUE)' indi-toupbase/CMakeLists.txt

%build
# -DBUILD_LIBS=OFF is the whole point of this spec, the complement of -libs's
# own -DBUILD_LIBS=ON -- see the file header and DESIGN.md.
#
# -DINDI_ROOT=%%{indi_prefix}: FindINDI.cmake's own documented, bespoke way to
# point find_package(INDI) at a non-standard install, same as -libs uses.
#
# -DCMAKE_PREFIX_PATH=%%{indi_prefix}: the DIFFERENT mechanism every vendor
# Find<X>.cmake needs (FindASI.cmake, FindAPOGEE.cmake, FindFLI.cmake, ...
# checked directly: none of them has a bespoke ROOT variable the way
# FindINDI.cmake does -- every one is an ordinary find_path/find_library
# with no extra hint beyond CMake's own default search behaviour). Setting
# CMAKE_PREFIX_PATH is what makes that default search also look under
# %%{indi_prefix}/include and %%{indi_prefix}/lib, where -libs's -devel
# subpackages actually put things. Without this, every vendor find_package()
# call fails despite the matching -devel BuildRequires being installed.
#
# -DCMAKE_INSTALL_RPATH=%%{indi_libdir}: this project's actual coexistence
# mechanism, same as core and -libs -- these binaries link against BOTH
# libindi*.so (core) and the vendor libraries (-libs), both of which live in
# the SAME %%{indi_libdir}, so one RPATH entry covers both.
#
# 46 WITH_<X>=OFF overrides -- the full "everything except our 9" list, and
# the single biggest way this %%build differs from -libs's own. Found the
# hard way on the first real build attempt (2026-08-26): -DBUILD_LIBS=ON (the
# libs phase) only ever processes "lib*" subdirectories, and non-blob vendors
# like ticfocuser-ng or eqmod have no lib* counterpart at all -- so -libs's
# own scope stayed naturally narrow without a single WITH_<X>=OFF beyond the
# 6 blob-tier exclusions below. -DBUILD_LIBS=OFF (this spec) has no such
# natural narrowing: it processes indi-3rdparty's FULL ~65-driver
# add_subdirectory() list unconditionally, defaults On for nearly all of it,
# and the first attempt here configured straight into indi-ticfocuser-ng
# (Nova/libnova-devel, then FFmpeg, libudev-devel, Qt, yaml, Bluetooth, ...
# each behind the next `CMake Error` in turn) despite it never having been
# part of this project's 8-vendor scope at all.
#
# Generated by diffing the complete `option(WITH_...)` list in CMakeLists.txt
# (65 default-On entries) against the 19 flags this project actually wants on
# (9 vendors -- MI, FLI, SBIG, INOVAPLX, APOGEE, ASICAM, PLAYERONE, FISHCAMP,
# plus the 11 individually-flagged Touptek brands) -- not hand-picked, so
# nothing already off (WITH_GIGE, WITH_LIBCAMERA, WITH_BNO_IMU, WITH_ICM_IMU,
# WITH_CELESTRON_ORIGIN, WITH_AHP_XC, WITH_AHP_GT -- the last two for the
# SAME execute_process(COMMAND git clone ...)-at-configure-time reason
# -libs's own comment already gives) needed to be touched or re-verified.
#
# First 7 are the SAME blob-tier vendors -libs excludes, for the SAME
# licence-tier reasons (DESIGN.md; DESIGN.md "QSI and Fishcamp resolved" for
# why QSI is here but fishcamp, resolved 2026-08-27, no longer is), plus
# WITH_ATIK_EFW -- a variant of WITH_ATIK the -libs survey never had a
# reason to notice, since it gates a DRIVER with no lib* counterpart at all.
# Leaving WITH_QSI at its default On would not merely build an unwanted
# driver -- its own top-level block falls back to `add_subdirectory(libqsi)`
# when the corresponding lib was not found (which it never will be here),
# i.e. the DRIVERS build would try to build the excluded vendor's LIBRARY
# inline, reintroducing exactly the licence and BuildRequires problem
# -libs's own WITH_QSI=OFF already excludes it for. WITH_FISHCAMP used to be
# excluded here for the identical reason; removed 2026-08-27 now that -libs
# ships a real indi-stable-3rdparty-libs-fishcamp-devel to link against, so
# FISHCAMP_FOUND is true and indi-3rdparty's own `if(FISHCAMP_FOUND)
# add_subdirectory(indi-fishcamp)` branch is what actually runs, not the
# library-build fallback.
#
# The other 38 are entirely out of THIS project's scope, not excluded for
# any licence reason -- non-blob drivers this packaging effort has not yet
# decided whether to bundle at all (STATUS.md, "3rdparty -- remaining"; the
# file header above).
#
# Extra -I%%{indi_includedir}: found on the first real build (2026-08-26),
# indi-apogee/apogee_ccd.cpp mixes BOTH include styles for the same vendor
# headers -- `#include "Alta.h"` (unqualified, resolved fine by
# APOGEE_INCLUDE_DIR itself, which FindAPOGEE.cmake's own PATH_SUFFIXES
# libapogee resolves to %%{indi_includedir}/libapogee) AND
# `#include <libapogee/Alta.h>` (qualified, needs the PARENT directory,
# %%{indi_includedir} itself, on the search path instead). Neither
# APOGEE_INCLUDE_DIR nor INDI_INCLUDE_DIR (which FindINDI.cmake resolves to
# %%{indi_includedir}/libindi, not the parent either) puts that parent
# directory on the compiler's search path anywhere in indi-apogee's own
# CMakeLists.txt, so the qualified form fails outright with "No such file or
# directory" despite the exact same header compiling fine two lines above it,
# unqualified. Not patched per-file -- exported globally via CFLAGS/CXXFLAGS
# rather than a source patch, since upstream's own inconsistency is plausibly
# present in other vendors' driver sources too and a global -I is harmless
# where it is not needed.
export CFLAGS="${CFLAGS:-} -I%{indi_includedir}"
export CXXFLAGS="${CXXFLAGS:-} -I%{indi_includedir}"

%cmake \
    -DCMAKE_INSTALL_PREFIX=%{indi_prefix} \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH=%{indi_libdir} \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
    -DINDI_ROOT=%{indi_prefix} \
    -DCMAKE_PREFIX_PATH=%{indi_prefix} \
    -DBUILD_LIBS=OFF \
    -DWITH_ASTROASIS=OFF \
    -DWITH_ATIK=OFF \
    -DWITH_ATIK_EFW=OFF \
    -DWITH_QHY=OFF \
    -DWITH_SVBONY=OFF \
    -DWITH_PENTAX=OFF \
    -DWITH_QSI=OFF \
    -DWITH_ARMADILLO=OFF \
    -DWITH_ASTARBOX=OFF \
    -DWITH_ASTROLINK4=OFF \
    -DWITH_ASTROMECHFOC=OFF \
    -DWITH_AVALON=OFF \
    -DWITH_AVALONUD=OFF \
    -DWITH_BEEFOCUS=OFF \
    -DWITH_BRESSEREXOS2=OFF \
    -DWITH_CAUX=OFF \
    -DWITH_CLOUDWATCHER=OFF \
    -DWITH_DREAMFOCUSER=OFF \
    -DWITH_DSI=OFF \
    -DWITH_DUINO=OFF \
    -DWITH_EQMOD=OFF \
    -DWITH_FFMV=OFF \
    -DWITH_GPHOTO=OFF \
    -DWITH_GPIO=OFF \
    -DWITH_GPSD=OFF \
    -DWITH_GPSNMEA=OFF \
    -DWITH_LIMESDR=OFF \
    -DWITH_MAXDOME=OFF \
    -DWITH_MGEN=OFF \
    -DWITH_NEXDOME=OFF \
    -DWITH_NIGHTSCAPE=OFF \
    -DWITH_OCS=OFF \
    -DWITH_OPENOGMA=OFF \
    -DWITH_ORION_SSG3=OFF \
    -DWITH_RADIOSIM=OFF \
    -DWITH_ROLLOFFINO=OFF \
    -DWITH_RTKLIB=OFF \
    -DWITH_SHELYAK=OFF \
    -DWITH_SKYWALKER=OFF \
    -DWITH_SPECTRACYBER=OFF \
    -DWITH_STARBOOK=OFF \
    -DWITH_STARBOOK_TEN=OFF \
    -DWITH_SX=OFF \
    -DWITH_TALON6=OFF \
    "-DWITH_TICFOCUSER-NG=OFF" \
    -DWITH_WEEWX_JSON=OFF
%cmake_build

%install
# Same false-positive check-rpaths class as core's and -libs's %%install --
# /opt is not on check-rpaths-worker's hardcoded allowlist. QA_RPATHS scoped
# to the SAME class (0x0002) for the SAME reason: a genuinely insecure
# relative RPATH or '..' traversal must still fail.
export QA_RPATHS=$(( 0x0002 ))

%cmake_install

# --- vendor SDK test/bench utilities: built and installed by upstream, not
# INDI drivers, not packaged here -------------------------------------------
# asi and playerone both install() a handful of standalone CLI diagnostic
# tools alongside their real drivers (asi_camera_test, asi_multi_camera_test,
# asi_camera_bench, asi_wheel_test, playerone_camera_test,
# playerone_camera_bench) -- confirmed by reading the install(TARGETS ...)
# calls directly, not assumed absent because they carry no indi_ prefix.
# None of them appear in any drivers.xml-equivalent catalogue and none of
# them are what "the coexistence guarantee" is about, so they are removed
# from the buildroot here rather than packaged -- the same
# remove-rather-than-merely-omit discipline -libs's own %%install already
# uses for flipro/flialgo, for the same reason: rpmbuild's own "installed
# but unpackaged" check would otherwise fail this build on exactly these
# files.
rm -f %{buildroot}%{indi_bindir}/asi_camera_test
rm -f %{buildroot}%{indi_bindir}/asi_multi_camera_test
rm -f %{buildroot}%{indi_bindir}/asi_camera_bench
rm -f %{buildroot}%{indi_bindir}/asi_wheel_test
rm -f %{buildroot}%{indi_bindir}/playerone_camera_test
rm -f %{buildroot}%{indi_bindir}/playerone_camera_bench

# --- driver catalogue: absolute paths, not bare names -----------------------
# Same defect, same fix, same verification method as core's %%install -- see
# core's spec for the full reasoning (DESIGN.md, "Driver-manifest
# discoverability"). The one real difference: indi-3rdparty does not emit
# ONE drivers.xml the way core does, it emits one indi_<vendor>.xml PER
# vendor (indi_apogee.xml, indi_asi.xml, ... 11 separate indi_<brand>.xml
# files for touptek alone) -- so this loops over every catalogue file this
# package installs, not a single named one.
_sed=$(mktemp)
for _b in %{buildroot}%{indi_bindir}/*; do
    [ -f "$_b" ] && [ -x "$_b" ] || continue
    _n=$(basename "$_b")
    echo "s|>${_n}</driver>|>%{indi_bindir}/${_n}</driver>|g" >> "$_sed"
done
_rewritten=0
for _cat in %{buildroot}%{indi_datadir}/indi_*.xml; do
    [ -e "$_cat" ] || continue
    sed -i -f "$_sed" "$_cat"
    _n=$(grep -c ">%{indi_bindir}/" "$_cat") || _n=0
    _rewritten=$(( _rewritten + _n ))
done
rm -f "$_sed"
test "$_rewritten" -gt 0 || { echo "ERROR: rewrote 0 catalogue entries across every indi_*.xml; the <driver> form changed upstream"; exit 1; }
echo "driver catalogues: rewrote $_rewritten entries to %{indi_bindir}"

# Assert every vendor this spec means to ship actually landed, rather than
# trusting a clean cmake_build exit (LESSONS_LEARNED.md #1 and #5).
for _bin in indi_apogee_ccd indi_asi_ccd indi_fli_ccd indi_playerone_ccd \
            indi_inovaplx_ccd indi_mi_ccd indi_sbig_ccd indi_toupcam_ccd \
            indi_fishcamp_ccd; do
    test -x %{buildroot}%{indi_bindir}/${_bin} \
        || { echo "ERROR: ${_bin} did not install -- an upstream WITH_* default or driver name changed"; exit 1; }
done

%files apogee
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_apogee_ccd
%{indi_bindir}/indi_apogee_wheel
%{indi_datadir}/indi_apogee.xml

%files asi
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_asi_ccd
%{indi_bindir}/indi_asi_single_ccd
%{indi_bindir}/indi_asi_wheel
%{indi_bindir}/indi_asi_st4
%{indi_bindir}/indi_asi_focuser
%{indi_bindir}/indi_asi_rotator
%{indi_datadir}/indi_asi.xml

%files fli
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_fli_focus
%{indi_bindir}/indi_fli_wheel
%{indi_bindir}/indi_fli_ccd
%{indi_datadir}/indi_fli.xml

%files playerone
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_playerone_ccd
%{indi_bindir}/indi_playerone_single_ccd
%{indi_bindir}/indi_playerone_wheel
%{indi_datadir}/indi_playerone.xml

%files inovasdk
%license indi-inovaplx/COPYING.LIB
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_inovaplx_ccd
%{indi_datadir}/indi_inovaplx_ccd.xml

%files micam
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
# indi_mi_ccd_usb/_eth and indi_mi_sfw_usb/_eth are symlinks to the two real
# binaries below, created at install time via install(CODE ...) rather than
# add_executable() (indi-mi/CMakeLists.txt ~40-64) -- missed by the
# add_executable()-only survey this spec's %%files was first drafted from;
# caught by rpmbuild's own "installed but unpackaged" check, 2026-08-26.
%{indi_bindir}/indi_mi_ccd
%{indi_bindir}/indi_mi_ccd_usb
%{indi_bindir}/indi_mi_ccd_eth
%{indi_bindir}/indi_mi_sfw
%{indi_bindir}/indi_mi_sfw_usb
%{indi_bindir}/indi_mi_sfw_eth
%{indi_datadir}/indi_miccd.xml

%files sbig
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_sbig_ccd
%{indi_datadir}/indi_sbig.xml

# indi-fishcamp/ (the driver source dir) carries no licence file of its own,
# unlike indi-inovaplx/ and indi-toupbase/ -- %%license points at
# indi-3rdparty's own top-level LICENSE (LGPL-2.1 text), matching every
# other vendor here that has no directory-local file, and matching
# indi_fishcamp.cpp's own header grant ("version 2.1 ... or any later").
%files fishcamp
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_fishcamp_ccd
%{indi_datadir}/indi_fishcamp.xml

%files touptek
%license indi-toupbase/COPYING.LGPL
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_toupcam_*
%{indi_bindir}/indi_altaircam_*
%{indi_bindir}/indi_bressercam_*
%{indi_bindir}/indi_mallincam_*
%{indi_bindir}/indi_meadecam_*
%{indi_bindir}/indi_nncam_*
%{indi_bindir}/indi_ogmacam_*
%{indi_bindir}/indi_omegonprocam_*
%{indi_bindir}/indi_starshootg_*
%{indi_bindir}/indi_tscam_*
%{indi_bindir}/indi_svbonycam_*
%{indi_datadir}/indi_toupcam.xml
%{indi_datadir}/indi_altaircam.xml
%{indi_datadir}/indi_bressercam.xml
%{indi_datadir}/indi_mallincam.xml
%{indi_datadir}/indi_meadecam.xml
%{indi_datadir}/indi_nncam.xml
%{indi_datadir}/indi_ogmacam.xml
%{indi_datadir}/indi_omegonprocam.xml
%{indi_datadir}/indi_starshootg.xml
%{indi_datadir}/indi_tscam.xml
%{indi_datadir}/indi_svbonycam.xml

%changelog
* Wed Aug 26 2026 Will Snyder <william@williamlsnyder.org> - 2.2.4.1-1
- Initial package. Builds indi-3rdparty tag v2.2.4.1's drivers for the same
  9 vendors indi-stable-3rdparty-libs bundles, with -DBUILD_LIBS=OFF against
  that package's -devel subpackages. Builds, installs and removes cleanly
  alongside indi-stable-core and indi-stable-3rdparty-libs as of 2026-08-26.
  See STATUS.md. Fishcamp added 2026-08-27 once its licence was confirmed
  clear (DESIGN.md); not yet released, so folded into the initial entry
  rather than given its own dated one, same convention as core.spec.
