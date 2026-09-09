# indi-stable-3rdparty-drivers -- the INDI drivers for the 9 vendors
# indi-stable-3rdparty-libs bundles the vendor SDKs for, plus eqmod, built
# from the SAME upstream indi-3rdparty tag with -DBUILD_LIBS=OFF, so this
# build links against the -devel subpackages -libs already produces rather
# than building any vendor SDK a second time.
#
# eqmod is the FIRST driver here with no vendor blob behind it, added
# 2026-09-08: it needs no -libs subpackage at all, only libnova and GSL, and
# so Requires only indi-stable-core-libs. It is the pathfinder for the
# remaining non-blob drivers rather than a one-off -- see DESIGN.md, "The ~50
# non-blob drivers", for the survey and the eqmod-first scope decision.
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
# Scoped to the 9 vendors -libs bundles (apogee, asi, fli, playerone,
# inovasdk, micam, sbig, touptek, fishcamp) plus three non-blob drivers:
# eqmod, armadillo-platypus and maxdomeii. indi-3rdparty ships roughly 40
# more non-blob drivers (gpsd, celestronaux, nexdome, ...) that need no
# vendor blob and have no dependency on -libs whatsoever; those stay off for
# now.
#
# Scope decided with Will 2026-09-08: eqmod alone first, as a complete
# build/install/coexistence/upgrade slice on both distros, then widen -- so
# that the defects a first non-blob driver brings surface against one driver
# rather than forty. Widening then resumed 2026-09-09 with a deliberately
# small second slice, again Will's call, chosen for the MECHANISMS it forces
# rather than for driver count: armadillo-platypus is the first subpackage in
# this spec to ship a udev rule, the first with six binaries from one source
# directory, and the first whose catalogue filename (indi_lunatico.xml)
# matches neither its directory nor any binary in it; maxdomeii is the first
# with an upstream test target that the default build compiles but nothing
# installs. See STATUS.md, "3rdparty -- remaining".
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
Summary:        INDI drivers for 9 vendor camera/focuser SDKs plus non-blob mount, focuser and dome drivers (stable upstream release, private prefix)

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
#   eqmod                     -- GPL-3.0-or-later AND LGPL-2.0-only. The ONLY
#                                 subpackage here that is not LGPL, and the
#                                 reason it carries its own License: tag
#                                 below rather than inheriting this one.
#                                 indi-eqmod/ is genuinely two bodies of code
#                                 with different grants, read directly from
#                                 every .cpp/.h header in the directory
#                                 (2026-09-08, not spot-checked): Geehalel's
#                                 original Skywatcher-protocol driver
#                                 (eqmod*, skywatcher*, align/, scope-limits/,
#                                 simulator/) reads "either version 3 of the
#                                 License, or (at your option) any later
#                                 version" and ships a full GPLv3 COPYING;
#                                 the 2020 AZ-GTi/Star Adventurer additions
#                                 (azgtibase, staradventurer*base) read
#                                 "Library General Public License version 2"
#                                 with NO "or later" grant -- LGPL-2.0-only,
#                                 the same conservative reading inovasdk gets
#                                 above and for the same reason. All four
#                                 binaries compile skywatcher.cpp, so all four
#                                 are GPL-3.0-or-later as built; LGPL-2.0's
#                                 own section 3 is what permits that
#                                 combination.
# %%license below points at indi-3rdparty's own top-level LICENSE (correct
# 2.1 text) rather than apogee's/fli's/micam's/sbig's own bundled files where
# those are missing or stale -- packaging a license file whose TEXT actually
# matches the declared tag, not merely whatever happened to be closest.
# eqmod is the exception: it has its own COPYING carrying real GPLv3 text.
#
# This tag is the DEFAULT every subpackage inherits, not a description of the
# source tarball, and that distinction is load-bearing here. Adding eqmod's
# GPL-3.0-or-later to it was tried first and was wrong: rpm propagated it to
# all 9 vendor subpackages, none of which contain a line of GPL-3 code, so
# every installed RPM would have overstated its own licence. eqmod carries its
# own License: tag instead and is the only subpackage that overrides this one.
# The cost is that the SRPM's tag understates what the SRPM contains; the
# benefit is that all 10 binary RPMs -- the things anyone actually installs
# and redistributes -- declare exactly what they hold.
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
# eqmod only. find_package(Nova REQUIRED) and find_package(GSL REQUIRED) in
# indi-eqmod/CMakeLists.txt, and nothing else beyond INDI/ZLIB, which the
# 9 vendor drivers already pull in. Neither is needed by any other driver
# built here -- they arrive with eqmod and would leave with it.
BuildRequires:  libnova-devel
BuildRequires:  gsl-devel

%description
INDI drivers for the 9 vendor camera/focuser SDKs indi-stable-3rdparty-libs
bundles, plus the EQMod/Skywatcher mount drivers, built with -DBUILD_LIBS=OFF
from the same upstream indi-3rdparty tag that project builds from with
-DBUILD_LIBS=ON.

Installs into %{indi_prefix}, the same private prefix as indi-stable-core and
indi-stable-3rdparty-libs, so it never collides with any distribution-
provided INDI or driver package. The remaining non-blob drivers upstream
ships are not built here yet -- see DESIGN.md for the scope decision.

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

# The only subpackage here with no indi-stable-3rdparty-libs-<vendor>
# Requires, because eqmod has no vendor blob behind it: it talks the
# Skywatcher serial/network protocol directly. libnova and libgsl are picked
# up as ordinary auto-generated SONAME Requires -- deliberately NOT added to
# %%global __requires_exclude above, which covers only libraries this project
# ships inside the private prefix. These two come from the distribution, so
# rpm SHOULD depend on them by soname, exactly as it would for libc.
%package eqmod
Summary:        EQMod / Skywatcher-protocol mount INDI drivers
License:        GPL-3.0-or-later AND LGPL-2.0-only
Requires:       indi-stable-core-libs%{?_isa}
%description eqmod
indi_eqmod_telescope, indi_azgti_telescope, indi_staradventurergti_telescope
and indi_staradventurer2i_telescope -- four binaries, not one, sharing
skywatcher.cpp's motor-control code: EQMod-protocol Skywatcher mounts
(including the Wave 100i/150i), the AZ-GTi in equatorial WiFi mode, and both
Star Adventurer GTi and 2i variants.

Needs no vendor SDK, so unlike every other subpackage here it depends only on
indi-stable-core-libs. Does NOT include indi_ahpgt_telescope, which
indi-eqmod/CMakeLists.txt gates behind its own local option(WITH_AHP_GT ...
OFF) -- a same-named but independent option from the top-level WITH_AHP_GT,
and off by default either way. Its catalogue entry is stripped in %%install
rather than left dangling; see there for why that matters.

# Like eqmod, these two have no vendor blob and so no -libs Requires. Unlike
# eqmod they need nothing beyond INDI itself -- no libnova, no GSL -- so they
# add no BuildRequires either. Both are LGPL-2.1-or-later, matching this
# spec's top-level License:, so neither carries its own License: tag; that
# was read from every .cpp/.h header in both directories on 2026-09-09, not
# spot-checked (all 12 armadillo files and all 4 maxdomeii files carry the
# identical "version 2.1 ... or (at your option) any later version" grant).
%package armadillo-platypus
Summary:        Lunatico Armadillo, Platypus, Dragonfly, Seletek and Beaver INDI drivers
Requires:       indi-stable-core-libs%{?_isa}
%description armadillo-platypus
Six binaries from one source directory, for Lunatico Astronomia's controller
family: indi_armadillo_focus and indi_platypus_focus (focusers),
indi_seletek_rotator (rotator), indi_dragonfly and indi_dragonfly_dome
(relay controller and its dome front-end) and indi_beaver_dome.

The first subpackage in this spec to ship a udev rule -- every rule this
project previously installed came from indi-stable-3rdparty-libs. It is
re-homed under the same namespaced filename pattern -libs uses, so it takes
effect without colliding with a distribution rule for the same hardware.

Its catalogue is indi_lunatico.xml, named for the vendor rather than for the
source directory or any binary in it -- worth knowing before globbing.

%package maxdomeii
Summary:        MaxDome II observatory dome INDI driver
Requires:       indi-stable-core-libs%{?_isa}
%description maxdomeii
indi_maxdomeii, for the MaxDome II dome controller. Needs no vendor SDK and
no library beyond INDI itself.

Does NOT include test-maxdomeii, an upstream standalone test harness that
indi-maxdomeii/CMakeLists.txt builds as part of the default target but never
install()s -- so unlike the asi and playerone diagnostic tools removed in
%%install, it never reaches the buildroot and needs no removal.

# Three more non-blob drivers, added 2026-09-09 as the third slice. Like
# armadillo-platypus and maxdomeii they need no vendor blob and so carry no
# -libs Requires; unlike those two they do link libnova, and celestronaux
# also GSL -- both already BuildRequires here since eqmod, so this slice
# added no new build dependency at all.
#
# All three are LGPL-2.1-or-later and therefore carry no License: tag of
# their own, read from every .cpp/.h in each directory rather than
# spot-checked. celestronaux has two files with no licence header at all
# (adaptive_tuner.cpp/.h, a PID helper); they carry no contradicting grant,
# so the directory's own reading stands. See STATUS.md for the several
# NEIGHBOURING drivers in this same dependency group that are NOT here,
# each held back on a real licence question rather than on packaging.
%package aok
Summary:        Astro-Electronic AOK Skywalker mount INDI driver
Requires:       indi-stable-core-libs%{?_isa}
%description aok
indi_lx200aok, an LX200-protocol driver for AOK Skywalker mount controllers.

Note the three-way name mismatch this package documents rather than hides:
the source directory is indi-aok, the upstream option is WITH_SKYWALKER, the
binary is indi_lx200aok and the catalogue is indi_aok.xml. None of them can
be derived from the others.

%package avalon
Summary:        Avalon StarGo mount INDI driver
Requires:       indi-stable-core-libs%{?_isa}
%description avalon
indi_lx200stargo, an LX200-protocol driver for Avalon Instruments StarGo
mount controllers. Catalogue is indi_avalon.xml, named for the vendor
rather than the binary.

%package celestronaux
Summary:        Celestron AUX-protocol mount INDI driver
Requires:       indi-stable-core-libs%{?_isa}
%description celestronaux
indi_celestron_aux, speaking Celestron's AUX protocol directly rather than
the NexStar serial protocol the core INDI driver uses. The only driver in
this package that needs GSL as well as libnova.

# --- The LGPL-2.0-only group -------------------------------------------------
# Four drivers whose every source file grants "the GNU Library General Public
# License version 2 as published by the Free Software Foundation" with NO "or
# later" clause -- read per file, not spot-checked. That is LGPL-2.0-only, the
# same conservative reading inovasdk and eqmod's azgti sources already get
# here, so each carries its own License: tag rather than inheriting the
# LGPL-2.1-or-later half of this spec's aggregate.
#
# %%license for these ships the LGPL-2.1 TEXT, which is not the text of the
# licence they grant. That is a deliberate decision by Will, 2026-09-09, taken
# because indi-3rdparty contains no LGPL-2.0 text anywhere -- checked, not
# assumed: indi-starbook-ten/COPYING.LESSER is 2.1 and libinovasdk/LICENSE.lib
# is a vendor notice. The alternatives were shipping no licence text at all or
# shipping something from outside the source tarball. The License: tag, which
# is what tooling and downstream consumers actually read, states the grant
# accurately in every case; it is only the accompanying text that is the
# nearest available rather than the exact one. See DESIGN.md.
%package nexdome
Summary:        NexDome observatory dome INDI driver (firmware v3+)
License:        LGPL-2.0-only
Requires:       indi-stable-core-libs%{?_isa}
%description nexdome
indi_nexdome, for NexDome domes running firmware v3 or later. Upstream
rewrote this driver completely for v3; firmware v1 is not supported.

%package talon6
Summary:        Talon6 roll-off roof controller INDI driver
License:        LGPL-2.0-only
Requires:       indi-stable-core-libs%{?_isa}
%description talon6
indi_talon6, for the Talon6 observatory roof controller.

%package ocs
Summary:        OnCue OCS observatory control system INDI driver
License:        LGPL-2.0-only
Requires:       indi-stable-core-libs%{?_isa}
%description ocs
indi_ocs, for the OnCue Observatory Control System.

Ships the top-level LGPL-2.1 text rather than its own bundled LICENSE.txt,
which is the GPL-2 text and contradicts every source header in the
directory. That is a genuine contradiction rather than the staleness apogee
and sbig carry, and shipping a GPL text alongside LGPL code would overstate
the terms in the more restrictive direction.

%package starbook-ten
Summary:        Vixen Starbook TEN mount INDI driver
License:        LGPL-2.0-only AND MIT
Requires:       indi-stable-core-libs%{?_isa}
%description starbook-ten
indi_starbook_ten, for Vixen Starbook TEN mount controllers, which it drives
over HTTP rather than a serial protocol.

The only subpackage here carrying MIT code: it bundles cpp-httplib
(httplib.h, Copyright (c) 2020 Yuji Hirose), which is genuinely compiled in
-- both starbook_ten.h and connectionhttp.h include it -- and so appears in
this subpackage's License: tag. Unlike its three siblings in this group it
ships its OWN COPYING.LESSER, which is the same LGPL-2.1 text.

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
# 47 WITH_<X>=OFF overrides -- the full "everything except our 9 vendors and
# eqmod" list, and
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
# The other 37 are out of THIS project's CURRENT scope, not excluded for any
# licence reason -- non-blob drivers deferred by the eqmod-first decision
# (STATUS.md, "3rdparty -- remaining"; the file header above), to be revisited
# once eqmod has been through the full verification cycle on both distros.
#
# The last two, WITH_WEBCAM and WITH_NUT, are a DIFFERENT case from every
# other line here and must stay pinned whatever the scope becomes. Neither is
# a fixed upstream default: indi-3rdparty's own top-level CMakeLists.txt sets
# each one by running find_package(FFmpeg) / find_package(NUTClient) at
# CONFIGURE time, so leaving either unset makes the build's contents depend on
# what happens to be installed in that day's mock chroot -- the exact
# nondeterminism this project's pinned Source0 hashes exist to prevent. Pinned
# Off rather than On because WITH_WEBCAM needs ffmpeg-devel, which is not in
# base Fedora at all (RPM Fusion only, a repo this project has never
# depended on). Found by reading upstream's CMakeLists.txt, 2026-09-08;
# neither had ever been passed explicitly before.
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
    -DUDEVRULES_INSTALL_DIR=%{indi_prefix}/udev-rules \
    -DINDI_DATA_DIR=%{indi_datadir} \
    -DWITH_ASTROASIS=OFF \
    -DWITH_ATIK=OFF \
    -DWITH_ATIK_EFW=OFF \
    -DWITH_QHY=OFF \
    -DWITH_SVBONY=OFF \
    -DWITH_PENTAX=OFF \
    -DWITH_QSI=OFF \
    -DWITH_ASTARBOX=OFF \
    -DWITH_ASTROLINK4=OFF \
    -DWITH_ASTROMECHFOC=OFF \
    -DWITH_AVALONUD=OFF \
    -DWITH_BEEFOCUS=OFF \
    -DWITH_BRESSEREXOS2=OFF \
    -DWITH_CLOUDWATCHER=OFF \
    -DWITH_DREAMFOCUSER=OFF \
    -DWITH_DSI=OFF \
    -DWITH_DUINO=OFF \
    -DWITH_FFMV=OFF \
    -DWITH_GPHOTO=OFF \
    -DWITH_GPIO=OFF \
    -DWITH_GPSD=OFF \
    -DWITH_GPSNMEA=OFF \
    -DWITH_LIMESDR=OFF \
    -DWITH_MGEN=OFF \
    -DWITH_NIGHTSCAPE=OFF \
    -DWITH_OPENOGMA=OFF \
    -DWITH_ORION_SSG3=OFF \
    -DWITH_RADIOSIM=OFF \
    -DWITH_ROLLOFFINO=OFF \
    -DWITH_RTKLIB=OFF \
    -DWITH_SHELYAK=OFF \
    -DWITH_SPECTRACYBER=OFF \
    -DWITH_STARBOOK=OFF \
    -DWITH_SX=OFF \
    "-DWITH_TICFOCUSER-NG=OFF" \
    -DWITH_WEEWX_JSON=OFF \
    -DWITH_WEBCAM=OFF \
    -DWITH_NUT=OFF
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

# --- eqmod: drop the catalogue entry for the driver we do not build ---------
# indi_eqmod.xml catalogues indi_ahpgt_telescope, but indi-eqmod's own local
# option(WITH_AHP_GT ... OFF) means that binary is never built here. Left
# alone it would survive the rewrite below as a BARE name (the rewrite only
# substitutes names it found an installed binary for), and a bare name is
# strictly worse than a missing entry: indiserver resolves it through PATH,
# so a distribution-provided indi_ahpgt_telescope would be what actually ran
# out of OUR catalogue -- precisely the coexistence violation the rewrite
# exists to prevent (DESIGN.md, "Driver-manifest discoverability").
# The count assertion is LESSONS_LEARNED.md #1: a deletion that silently
# matched nothing would otherwise look identical to a successful one.
_ahpgt_before=$(grep -c 'indi_ahpgt_telescope' %{buildroot}%{indi_datadir}/indi_eqmod.xml)
test "$_ahpgt_before" -eq 1 \
    || { echo "ERROR: expected exactly 1 indi_ahpgt_telescope catalogue entry, found $_ahpgt_before -- indi_eqmod.xml.cmake changed upstream"; exit 1; }
sed -i '/<device label="AHP GT Mount"/,/<\/device>/d' %{buildroot}%{indi_datadir}/indi_eqmod.xml
grep -q 'indi_ahpgt_telescope' %{buildroot}%{indi_datadir}/indi_eqmod.xml \
    && { echo "ERROR: indi_ahpgt_telescope still present in indi_eqmod.xml after the device-block delete"; exit 1; }
# The four real eqmod drivers must survive that delete, not be collateral.
for _d in indi_eqmod_telescope indi_azgti_telescope \
          indi_staradventurergti_telescope indi_staradventurer2i_telescope; do
    grep -q "${_d}" %{buildroot}%{indi_datadir}/indi_eqmod.xml \
        || { echo "ERROR: ${_d} lost from indi_eqmod.xml -- the AHP GT device-block delete over-matched"; exit 1; }
done

# --- udev rules: re-home under a namespaced filename ------------------------
# NEW as of the armadillo-platypus/maxdomeii slice: until then no subpackage
# in THIS spec shipped a udev rule at all -- every rule this project put in
# /usr/lib/udev/rules.d came from -libs. Confirmed before writing this rather
# than assumed: `rpm -qlp` over all ten 2.2.4.1-1 driver RPMs matched zero
# paths under rules.d.
#
# THIS DOES NOT WORK THE WAY -libs's EQUIVALENT DOES, and the first build
# proved it. -libs redirects UDEVRULES_INSTALL_DIR with a -D flag and then
# re-homes out of that private scratch directory. Every lib* vendor
# directory declares that variable as `set(... CACHE STRING ...)`, so the
# -D wins. Driver directories are split, and five of them -- armadillo-
# platypus, dsi, orion-ssg3, qsi and sx -- instead use a DIFFERENT variable,
# RULES_INSTALL_DIR, declared with a plain `set()` and no CACHE. A plain
# set() overwrites whatever the command line supplied, so:
#
#   -DUDEVRULES_INSTALL_DIR=...  does nothing for these five (wrong name)
#   -DRULES_INSTALL_DIR=...      does nothing either (overwritten at configure)
#
# The rule is therefore installed straight to a hardcoded /usr/lib/udev/
# rules.d, under upstream's own un-namespaced filename, and no -D flag can
# move it. That is a coexistence problem, not a tidiness one: 99-armadillo
# platypus.rules is the exact filename a distribution package for the same
# hardware would use, so shipping it as-is puts a file this project owns
# where a distro file belongs. DESIGN.md's "Upstream build-system facts"
# calls UDEVRULES_INSTALL_DIR "the one non-derived install path"; that is
# now known to be incomplete.
#
# So re-home by DESTINATION rather than by source directory: take whatever
# landed in either place and rename it, which is robust to both upstream
# mechanisms and to a driver switching between them. Same namespaced pattern
# -libs uses, so everything this project installs into rules.d is one
# greppable set. See core's spec for why four percent signs are needed in
# ${base%%%%-*} under RPM macro expansion.
mkdir -p %{buildroot}%{_udevrulesdir}
for rule in %{buildroot}%{indi_prefix}/udev-rules/*.rules \
            %{buildroot}%{_udevrulesdir}/*.rules; do
    [ -e "$rule" ] || continue
    base=$(basename "$rule")
    case "$base" in
        *-indi-stable-3rdparty-*) continue ;;   # already re-homed
    esac
    mv "$rule" "%{buildroot}%{_udevrulesdir}/${base%%%%-*}-indi-stable-3rdparty-${base#*-}"
done
rm -rf %{buildroot}%{indi_prefix}/udev-rules

# A loop that finds nothing must not pass as though it worked (#1). Exactly
# one driver in this spec's current scope ships a rule -- armadillo-platypus.
# maxdomeii deliberately ships none, so this asserts a COUNT, not merely "at
# least one": a second rule appearing means a driver started shipping one and
# needs a %%files line, which would otherwise surface much later as an
# unpackaged-file failure with nothing pointing at the cause.
_rules=$(ls -1 %{buildroot}%{_udevrulesdir}/*.rules 2>/dev/null | wc -l)
test "$_rules" -eq 1 \
    || { echo "ERROR: expected exactly 1 udev rule from this package, found $_rules:"; ls -1 %{buildroot}%{_udevrulesdir}/ 2>/dev/null; exit 1; }
test -e %{buildroot}%{_udevrulesdir}/99-indi-stable-3rdparty-armadilloplatypus.rules \
    || { echo "ERROR: the armadillo-platypus rule is not at its re-homed name. Found:"; ls -1 %{buildroot}%{_udevrulesdir}/; exit 1; }
# And nothing may be left at an upstream, un-namespaced filename -- that is
# the actual coexistence assertion, and the one the first build failed.
_bare_rules=$(ls -1 %{buildroot}%{_udevrulesdir}/*.rules 2>/dev/null | grep -v -- '-indi-stable-3rdparty-' || true)
test -z "$_bare_rules" \
    || { echo "ERROR: udev rules left at an upstream filename, where a distro package's own rule belongs:"; echo "$_bare_rules"; exit 1; }

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

# Every <driver> entry must now name an absolute path. Any that does not is a
# catalogue entry for a binary this package did not build, and would resolve
# through PATH to whatever the distribution provides -- the AHP GT case
# stripped above, found 2026-09-08 while adding eqmod, generalized so the
# next one cannot arrive silently. Verified non-vacuous before being relied
# on: run against the already-shipped 2.2.4.1-1 packages all 56 entries were
# already absolute, and against an unstripped indi_eqmod.xml it fires.
_bare=$(grep -hoE '<driver[^>]*>[^<]+</driver>' %{buildroot}%{indi_datadir}/indi_*.xml \
        | grep -vE '>%{indi_bindir}/' || true)
test -z "$_bare" || { echo "ERROR: catalogue entries left as bare names, which resolve via PATH to a distro binary:"; echo "$_bare"; exit 1; }

# Assert every vendor this spec means to ship actually landed, rather than
# trusting a clean cmake_build exit (LESSONS_LEARNED.md #1 and #5).
# All four eqmod binaries are listed, not one representative: they are four
# separate add_executable() targets whose only shared fate is skywatcher.cpp,
# so any one of them can go missing on its own.
for _bin in indi_apogee_ccd indi_asi_ccd indi_fli_ccd indi_playerone_ccd \
            indi_inovaplx_ccd indi_mi_ccd indi_sbig_ccd indi_toupcam_ccd \
            indi_fishcamp_ccd indi_eqmod_telescope indi_azgti_telescope \
            indi_staradventurergti_telescope indi_staradventurer2i_telescope \
            indi_armadillo_focus indi_platypus_focus indi_seletek_rotator \
            indi_dragonfly indi_dragonfly_dome indi_beaver_dome \
            indi_maxdomeii indi_lx200aok indi_lx200stargo \
            indi_celestron_aux indi_nexdome indi_talon6 indi_ocs \
            indi_starbook_ten; do
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

# The only %%license here pointing at a driver directory's own file rather
# than indi-3rdparty's top-level LICENSE: indi-eqmod/COPYING is real GPLv3
# text, which is what this subpackage's own License: tag declares. The
# top-level LICENSE is LGPL-2.1 and would be the wrong text for it.
# The four *_sk.xml files are INDI property skeletons, not driver
# catalogues -- they carry no <driver> element at all (checked, 2026-09-08),
# so the catalogue rewrite in %%install correctly leaves them untouched
# despite matching its indi_*.xml glob.
%files eqmod
%license indi-eqmod/COPYING
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_eqmod_telescope
%{indi_bindir}/indi_azgti_telescope
%{indi_bindir}/indi_staradventurergti_telescope
%{indi_bindir}/indi_staradventurer2i_telescope
%{indi_datadir}/indi_eqmod.xml
%{indi_datadir}/indi_eqmod_sk.xml
%{indi_datadir}/indi_eqmod_simulator_sk.xml
%{indi_datadir}/indi_align_sk.xml
%{indi_datadir}/indi_eqmod_scope_limits_sk.xml

# Neither directory ships a licence file of its own, so both point at
# indi-3rdparty's top-level LICENSE -- which is the correct text here,
# unlike eqmod's case: that file IS the LGPL-2.1 these two grant. Checked,
# not assumed: LICENSE's first lines read "GNU LESSER GENERAL PUBLIC
# LICENSE / Version 2.1, February 1999".
%files armadillo-platypus
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_armadillo_focus
%{indi_bindir}/indi_platypus_focus
%{indi_bindir}/indi_seletek_rotator
%{indi_bindir}/indi_dragonfly
%{indi_bindir}/indi_dragonfly_dome
%{indi_bindir}/indi_beaver_dome
%{indi_datadir}/indi_lunatico.xml
%{_udevrulesdir}/*-indi-stable-3rdparty-*armadilloplatypus*.rules

%files maxdomeii
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_maxdomeii
%{indi_datadir}/indi_maxdomeii.xml

# None of these three ships a licence file of its own, so all three point at
# indi-3rdparty's top-level LICENSE -- which is the right text for them: it
# is the LGPL-2.1 these directories grant.
%files aok
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_lx200aok
%{indi_datadir}/indi_aok.xml

%files avalon
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_lx200stargo
%{indi_datadir}/indi_avalon.xml

%files celestronaux
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_celestron_aux
%{indi_datadir}/indi_celestronaux.xml

# These four grant LGPL-2.0-only and ship the LGPL-2.1 text -- see the
# %%package block above for why, and DESIGN.md for the decision itself.
# starbook-ten uses its own COPYING.LESSER rather than the top-level LICENSE
# only because it has one; the two are the same licence text.
%files nexdome
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_nexdome
%{indi_datadir}/indi_nexdome.xml

%files talon6
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_talon6
%{indi_datadir}/indi_talon6.xml

%files ocs
%license LICENSE
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_ocs
%{indi_datadir}/indi_ocs.xml

%files starbook-ten
%license indi-starbook-ten/COPYING.LESSER
%dir %{indi_prefix}
%dir %{indi_bindir}
%dir %{indi_prefix}/share
%dir %{indi_datadir}
%{indi_bindir}/indi_starbook_ten
%{indi_datadir}/indi_starbook_ten.xml

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
