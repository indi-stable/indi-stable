# indi-stable-3rdparty-libs -- the vendor SDKs and support libraries that
# indi-3rdparty's driver tree links against, built from an upstream
# indi-3rdparty stable tag and installed into the SAME private prefix as
# indi-stable-core.
#
# Builds, installs and removes cleanly alongside indi-stable-core as of
# 2026-08-26 (see STATUS.md) -- verified against distribution core INDI only
# (libindi/libindi-libs/kstars), since Fedora ships no indi-3rdparty package
# to coexist against at all (DESIGN.md). Upgrade-path testing has not been
# done yet the way core's was.
#
# See DESIGN.md, "`indi-3rdparty` is a different shape of build", for the full
# rationale. The short version of what makes this spec different from core's:
#
#   * indi-3rdparty is a genuinely independent version axis from core -- its
#     newest tag (v2.2.4.1) is BEHIND core's (v2.2.4.2) as of this writing.
#     This package's Version: tracks indi-3rdparty's own tags, never core's.
#   * The upstream build is two MUTUALLY EXCLUSIVE phases gated by
#     BUILD_LIBS, not two configure passes over the same output: FindASI.cmake
#     is an ordinary find_path/find_library over system search paths, and
#     libasi's own CMakeLists.txt installs the vendor blob via
#     add_library(... SHARED IMPORTED) -- a real system install, not a
#     source-tree reference. So this package's %files genuinely differ from
#     what indi-stable-3rdparty-drivers (not yet written) will produce from
#     the SAME source tree with BUILD_LIBS=OFF, and the drivers package will
#     BuildRequire this one's -devel, ordinarily, the way
#     Fedora's own indi-3rdparty-drivers.spec BuildRequires
#     indi-3rdparty-libapogee-devel. See DESIGN.md, "Resolution -- two source
#     packages, not one and not sixty-one".
#   * Only some of the 22 vendor SDKs bundled in this tree are built here.
#     See the licence-tier decision below and in DESIGN.md.

%global indi_prefix     /opt/indi-stable
%global indi_libdir     %{indi_prefix}/lib
%global indi_includedir %{indi_prefix}/include

# Same pattern as core: GitHub strips the leading v from the tag name, but
# CMake's own project version (and this spec's Version:) does not carry it.
%global upstream_tag    v%{version}

# --- Dependency-generator filtering: same rule as core, same reason ---------
# Nothing under the private prefix should ever be advertised system-wide, for
# exactly the reason DESIGN.md's "A private path is not enough" documents for
# core: an unfiltered Provides here would tell the depsolver this package is a
# system-wide provider of e.g. libASICamera2.so.1, and any consumer depending
# on that soname alone (rather than by package name) could be satisfied from
# our private, unreachable copy instead of a real system one.
#
# A libindi*-pattern Requires exclude, the OTHER half of core's filter pair,
# genuinely is not needed here: checked directly, none of the vendor lib*
# directories bundled below actually LINK against libindi
# (target_link_libraries in libapogee and libfli, the only two that even
# find_package(INDI), pulls in USB1/CURL only -- INDI headers are used, the
# library is not). That linking happens in the DRIVER packages, so
# indi-stable-3rdparty-drivers.spec is where a libindi*-pattern exclude will
# be needed.
#
# But a DIFFERENT Requires exclude is needed, and was missing until the first
# real `dnf install` (2026-08-26) failed all 8 -devel subpackages at once:
# "nothing provides libapogee.so.3()(64bit)", etc. Every -devel package here
# ships its vendor's unversioned .so symlink (e.g. libapogee.so ->
# libapogee.so.3), and rpmbuild's automatic dependency generator turns that
# into `Requires: libapogee.so.3()(64bit)` on the -devel package -- which the
# runtime package would normally satisfy with a matching auto-Provides, EXCEPT
# the __provides_exclude_from above has already stripped that Provides from
# everything under the private prefix, runtime packages included. Exactly the
# bug core's own comment above warns about ("Filtering Provides alone would
# leave our own auto-generated Requires... unsatisfiable"), just missed here
# because the check that was actually run (libindi linkage) answered a
# different question than the one that mattered (self-referential SONAME
# Requires). The package-name Requires already on each -devel subpackage
# (`Requires: %%{name}-<vendor>%%{?_isa} = %%{version}-%%{release}`, below)
# is what actually binds -devel to its runtime sibling; this exclude just
# keeps rpm from ALSO demanding the now-unadvertised SONAME. String-based, not
# path-based, for the same reason as core: path-based would also drop the
# legitimate external Requires these same libraries carry (libcurl.so.4,
# libusb-1.0.so.0, libc, libstdc++, ...), which rpm must still see. Lists
# every vendor SONAME stem bundled below, not a wildcard, so a future vendor
# addition must extend this deliberately rather than inherit it by accident.
%global __provides_exclude_from ^%{indi_prefix}/.*$
%global __requires_exclude      ^lib(apogee|ASICamera2|CAARotator|EAFFocuser|EFWFilter|USB2ST4Conv|fli|fishcamp|inovasdk|gxccd|PlayerOneCamera|PlayerOnePW|sbig|altaircam|bressercam|mallincam|meadecam|nncam|ogmacam|omegonprocam|starshootg|svbonycam|toupcam|tscam)\\.so.*$

Name:           indi-stable-3rdparty-libs
Version:        2.2.4.1
Release:        2%{?dist}
Summary:        Vendor camera/focuser SDKs bundled by indi-3rdparty (stable upstream release, private prefix)

# One tarball, several vendors, several licences -- this tag is a defensible
# aggregate, NOT a fully-verified per-file audit. Confirmed by reading the
# licence file text (not just the filename) for every vendor bundled below:
#   asi, playerone            -- MIT-style permission notice (verbatim in
#                                 asi's case; playerone wraps the same
#                                 boilerplate in a company preamble)
#   fli                       -- 2-clause BSD (LICENSE.BSD, read in full)
#   inovasdk, micam, sbig     -- a custom "redistribution in binary form
#                                 permitted" notice, BSD-shaped but not the
#                                 literal SPDX BSD-2-Clause text -- tagged
#                                 BSD-2-Clause as the closest match, not a
#                                 byte-for-byte one
#   apogee                    -- GPL-2.0, the FULL licence text (LICENSE),
#                                 not a permissive grant. Still redistributed
#                                 correctly under GPL's own terms -- this
#                                 project ships apogee's source alongside the
#                                 binary, which is what GPL requires and this
#                                 tree already does. Whether apogee's own
#                                 source files say "-only" or "-or-later" was
#                                 NOT checked at the per-file header level;
#                                 -only is the more conservative tag and is
#                                 used below for that reason.
#   the 11 Touptek rebrands   -- LGPL-2.1, full text (COPYING.LGPL), confirmed
#                                 byte-identical (502 lines) across all 11
#                                 directories rather than assumed from one
#   fishcamp                  -- 2-clause BSD (COPYING.LIB, read in full;
#                                 the filename suggests LGPL but the text is
#                                 genuine BSD-2-Clause), confirmed 2026-08-27,
#                                 same tier as fli -- see DESIGN.md
# See DESIGN.md, "The licence tiers, and why the motivating example is the
# hardest case", and its "Resolution" for why astroasis/atik/qhy/svbony are
# NOT in this package, and why pentax's libricohcamerasdk (an actual EULA
# forbidding standalone redistribution, found separately) is excluded below
# too even though it was never in the licence-tier survey. QSI's own
# libqsi/COPYING is the same shape, confirmed 2026-08-27: "Do not redistribute
# the source code without prior written permission from QSI" -- also excluded,
# also below, also stronger than mere silence. See DESIGN.md, "QSI and
# Fishcamp resolved".
License:        MIT AND BSD-2-Clause AND GPL-2.0-only AND LGPL-2.1-only
URL:            https://github.com/indilib/indi-3rdparty
Source0:        https://github.com/indilib/indi-3rdparty/archive/refs/tags/%{upstream_tag}.tar.gz#/indi-3rdparty-%{upstream_tag}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  systemd-rpm-macros
# find_package(INDI REQUIRED) in libapogee/CMakeLists.txt and
# libfli/CMakeLists.txt fails the WHOLE configure step if unmet, even though
# neither actually links against it -- one cmake invocation configures every
# lib*/ subdirectory together, so this is needed for the build to configure
# at all, not just for those two subpackages.
BuildRequires:  indi-stable-core-devel
# apogee, fli
BuildRequires:  libusb1-devel
# apogee
BuildRequires:  libcurl-devel

%description
The vendor camera and focuser SDKs that indi-3rdparty's DRIVERS link against,
built with -DBUILD_LIBS=ON from the same upstream indi-3rdparty tag this
project's driver packages build from with -DBUILD_LIBS=OFF -- see
indi-stable-3rdparty-drivers (a separate source package) and DESIGN.md.

Installs into %{indi_prefix}, the same private prefix as indi-stable-core, so
it never collides with any distribution-provided camera SDK package. Only a
subset of the vendors indi-3rdparty bundles are built here -- see the
per-subpackage descriptions below and DESIGN.md's licence-tier decision.

This is an unofficial third-party build. It is not affiliated with or
endorsed by the INDI project.

%package apogee
Summary:        Apogee CCD camera SDK (GPL-2.0)
%description apogee
Apogee Instruments CCD camera library, GPL-2.0 licensed -- source is included
in this package's %%license files, satisfying GPL's own redistribution terms
rather than merely permitting them.

%package apogee-devel
Summary:        Development files for indi-stable-3rdparty-libs-apogee
Requires:       %{name}-apogee%{?_isa} = %{version}-%{release}
%description apogee-devel
Headers for building against the bundled Apogee SDK. Install path is
%{indi_includedir}, matching indi-stable-core-devel's own headers -- never
under /usr/include, for the same reason core's headers are not there.

%package asi
Summary:        ZWO Optics ASI camera/filter-wheel/focuser SDK (MIT)
%description asi
ZWO's ASICamera2, EFW, ST4, EAF and CAA SDKs, bundled as prebuilt vendor
binaries under a verbatim MIT licence.

%package asi-devel
Summary:        Development files for indi-stable-3rdparty-libs-asi
Requires:       %{name}-asi%{?_isa} = %{version}-%{release}
%description asi-devel
Headers for building against the bundled ZWO ASI SDK.

%package fli
Summary:        Finger Lakes Instrumentation SDK (BSD-2-Clause)
%description fli
FLI's camera/focuser/filter-wheel SDK, 2-clause BSD licensed, source included.

%package fli-devel
Summary:        Development files for indi-stable-3rdparty-libs-fli
Requires:       %{name}-fli%{?_isa} = %{version}-%{release}
%description fli-devel
Headers for building against the bundled FLI SDK.

%package playerone
Summary:        Player One Astronomy camera SDK (MIT-style)
%description playerone
Player One Astronomy's camera SDK, redistributable under the terms in its own
licence.txt (an MIT-style permission notice).

%package playerone-devel
Summary:        Development files for indi-stable-3rdparty-libs-playerone
Requires:       %{name}-playerone%{?_isa} = %{version}-%{release}
%description playerone-devel
Headers for building against the bundled Player One SDK.

%package inovasdk
Summary:        i.Nova Technologies focuser SDK
%description inovasdk
i.Nova's focuser SDK, redistributable in binary form under its own licence.

%package inovasdk-devel
Summary:        Development files for indi-stable-3rdparty-libs-inovasdk
Requires:       %{name}-inovasdk%{?_isa} = %{version}-%{release}
%description inovasdk-devel
Headers for building against the bundled i.Nova SDK.

%package micam
Summary:        Moravian Instruments camera SDK
%description micam
Moravian Instruments' gxccd camera SDK, redistributable in binary form under
its own licence.

%package micam-devel
Summary:        Development files for indi-stable-3rdparty-libs-micam
Requires:       %{name}-micam%{?_isa} = %{version}-%{release}
%description micam-devel
Headers for building against the bundled Moravian SDK.

%package sbig
Summary:        Santa Barbara Instrument Group camera SDK and firmware
%description sbig
SBIG's camera SDK and firmware images, redistributable in binary form under
its own licence.

%package sbig-devel
Summary:        Development files for indi-stable-3rdparty-libs-sbig
Requires:       %{name}-sbig%{?_isa} = %{version}-%{release}
%description sbig-devel
Headers for building against the bundled SBIG SDK.

%package fishcamp
Summary:        Fishcamp Engineering CCD camera library and firmware (BSD-2-Clause)
%description fishcamp
Fishcamp Engineering's camera library, 2-clause BSD licensed, source included
-- same tier as fli, resolved 2026-08-27 (DESIGN.md). Ships two firmware
images uploaded to the camera's own microcontroller, covered by the same
top-level licence as the library source (same reasoning as sbig's own
bundled firmware).

%package fishcamp-devel
Summary:        Development files for indi-stable-3rdparty-libs-fishcamp
Requires:       %{name}-fishcamp%{?_isa} = %{version}-%{release}
%description fishcamp-devel
Headers for building against the bundled Fishcamp library.

%package touptek
Summary:        Touptek and rebranded-Touptek camera SDKs (LGPL-2.1)
%description touptek
The Touptek camera SDK and its ten rebrands (Altair, Bresser, Mallincam,
Meade, Nncam, Ogmacam, Omegon, StarShoot, TSCam, SVBONYCAM) -- the same
underlying hardware sold under eleven brand names, each with its own
LGPL-2.1-licensed vendor SDK. Bundled together because indi-toupbase, the
single driver source that consumes them, builds against all eleven from one
CMakeLists.txt loop (`foreach(BRAND IN LISTS TOUPTEK_REBRANDS)`) -- see
DESIGN.md.

%package touptek-devel
Summary:        Development files for indi-stable-3rdparty-libs-touptek
Requires:       %{name}-touptek%{?_isa} = %{version}-%{release}
%description touptek-devel
Headers for building against all eleven bundled Touptek-family SDKs.

%prep
# GitHub strips the leading v: tag v2.2.4.1 unpacks to indi-3rdparty-2.2.4.1.
%autosetup -n indi-3rdparty-%{version} -p1

%build
# -DINDI_ROOT: FindINDI.cmake (cmake_modules/FindINDI.cmake) documents this as
# the supported way to point find_package(INDI) at a non-standard install --
# our own private prefix is exactly that, and without it configure fails with
# INDI not found despite indi-stable-core-devel being a BuildRequires.
#
# -DCMAKE_INSTALL_LIBDIR=lib and RPATH into our own libdir: same two reasons
# as core's spec (relative libdir keeps pkgconfig/whatever else inside the
# prefix; RPATH is this project's actual coexistence mechanism), even though
# most of these vendor libraries do not themselves link anything further.
#
# Three absolute paths redirected into the private prefix, found by reading
# every bundled lib's CMakeLists.txt rather than assumed to not exist because
# core did not have them:
#   UDEVRULES_INSTALL_DIR  -- shared by every vendor lib here, same variable
#                             and same %%install re-homing step as core uses.
#   FIRMWARE_INSTALL_DIR   -- libsbig only (libsbig/CMakeLists.txt:22,30);
#                             upstream's own default is /usr/lib/firmware,
#                             a real file-conflict-with-other-packages risk
#                             this project's private-prefix rule exists to
#                             avoid, same as UDEVRULES_INSTALL_DIR.
#   CONF_DIR               -- libapogee only (libapogee/CMakeLists.txt:17),
#                             upstream's own Linux default is /etc -- writing
#                             into the SYSTEM /etc is exactly the kind of
#                             thing this project's whole design exists to
#                             prevent, not merely a style preference.
# All three are ordinary CMake CACHE STRING variables in the upstream tree,
# so a -D on this command line overrides the in-tree default without patching.
#
# BUILD_LIBS=ON is the whole point of this spec -- see the file header.
#
# Six WITH_<X>=OFF overrides, all vendors this project decided NOT to bundle
# (DESIGN.md, the licence-tier Resolution): astroasis, atik, qhy and svbony
# ship with no licence file at all; libricohcamerasdk (WITH_PENTAX, which
# defaults On and was NOT part of the original licence-tier survey since
# indi-pentax itself is not a "blob driver" by this project's own test) is
# excluded here too because its own EULA explicitly forbids standalone
# redistribution -- a stronger reason than mere silence. Leaving WITH_PENTAX
# at its default would have built and packaged an SDK this project has no
# right to redistribute at all; caught by reading every WITH_* default in
# CMakeLists.txt rather than assuming only the four already-surveyed vendors
# needed disabling.
#
# WITH_QSI and WITH_FISHCAMP (both default On, CMakeLists.txt ~220-222) were
# missed by that same survey when the build was first written -- caught
# 2026-08-26 on the first real mock build (WITH_QSI failed configure outright,
# find_package(FTDI1 REQUIRED); WITH_FISHCAMP configured and built fine and
# would have shipped an unaudited vendor SDK silently if the build's own
# "installed but unpackaged" check hadn't caught it -- LESSONS_LEARNED.md
# #1/#2's shape) and both left OFF pending a licence read. That read happened
# 2026-08-27 (DESIGN.md, "QSI and Fishcamp resolved") and the two vendors
# resolved oppositely: QSI's own libqsi/COPYING explicitly forbids
# redistribution without QSI's written permission -- same tier as Pentax
# above, stays OFF, now for a confirmed reason instead of "never looked at".
# Fishcamp's libfishcamp/COPYING.LIB is genuine BSD-2-Clause (the filename
# suggests LGPL; the text does not) -- moved to the bundled tier, %%package
# fishcamp below.
#
# WITH_AHP_XC and WITH_AHP_GT are NOT touched: both already default Off, and
# leaving them off is load-bearing, not incidental -- both do
# `execute_process(COMMAND git clone https://github.com/...)` AT CONFIGURE
# TIME (CMakeLists.txt ~423-433), which needs network access no mock/koji
# build provides and which this project has done no licence review for at
# all. Someone must not "helpfully" turn these on without reading DESIGN.md
# first.
%cmake \
    -DCMAKE_INSTALL_PREFIX=%{indi_prefix} \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH=%{indi_libdir} \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
    -DINDI_ROOT=%{indi_prefix} \
    -DBUILD_LIBS=ON \
    -DINDI_INSTALL_UDEV_RULES=ON \
    -DUDEVRULES_INSTALL_DIR=%{indi_prefix}/udev-rules \
    -DINDI_INSTALL_FIRMWARE=ON \
    -DFIRMWARE_INSTALL_DIR=%{indi_prefix}/share/indi/firmware \
    -DCONF_DIR=%{indi_prefix}/etc \
    -DWITH_ASTROASIS=OFF \
    -DWITH_ATIK=OFF \
    -DWITH_QHY=OFF \
    -DWITH_SVBONY=OFF \
    -DWITH_PENTAX=OFF \
    -DWITH_QSI=OFF
%cmake_build

%install
# Same false-positive class as core's spec hits, for the same reason -- /opt
# is not on check-rpaths-worker's hardcoded allowlist. See core's %%install
# comment for the full reasoning; not repeated here verbatim, but the
# suppression must stay scoped to the SAME class (0x0002) for the SAME reason:
# a genuinely insecure relative RPATH or '..' traversal must still fail.
export QA_RPATHS=$(( 0x0002 ))

%cmake_install

# --- flipro/flialgo: built unconditionally alongside libfli, not packaged --
# libfli/CMakeLists.txt has no WITH_<X> gate of its own for these two --
# they are ADD_LIBRARY(... SHARED IMPORTED) targets inside the SAME
# CMakeLists.txt that builds the real, source-compiled, LICENSE.BSD-covered
# fli target (~76-97), so there is no configure-time flag that keeps libfli
# while dropping them. Their licence coverage is still genuinely open --
# see STATUS.md, "Genuinely open, not just untested" -- so they must not
# ship. Confirmed 2026-08-26 that %%cmake_install actually installs them
# (rpmbuild's "installed but unpackaged" check found libflipro.so*,
# libflialgo.so* and libflipro.h in the buildroot); deleting them here is
# what makes "left OUT of %%files" true in the buildroot, not just in the
# spec text.
rm -f %{buildroot}%{indi_libdir}/libflipro.so*
rm -f %{buildroot}%{indi_libdir}/libflialgo.so*
rm -f %{buildroot}%{indi_includedir}/libflipro.h

# --- udev rules: re-home exactly as core does -------------------------------
# Every vendor lib bundled here installs its own 99-<vendor>.rules into the
# SAME UDEVRULES_INSTALL_DIR variable, redirected above into the private
# prefix's scratch tree. Re-home under namespaced filenames so they take
# effect without colliding with any distribution package that might one day
# ship a udev rule for the same hardware. See core's spec for why four
# percent signs are needed in ${base%%%%-*} under RPM's macro expansion.
mkdir -p %{buildroot}%{_udevrulesdir}
for rule in %{buildroot}%{indi_prefix}/udev-rules/*.rules; do
    [ -e "$rule" ] || continue
    base=$(basename "$rule")
    mv "$rule" "%{buildroot}%{_udevrulesdir}/${base%%%%-*}-indi-stable-3rdparty-${base#*-}"
done
rm -rf %{buildroot}%{indi_prefix}/udev-rules

# Assert every vendor this spec means to ship actually landed, rather than
# trusting a clean cmake_build exit -- an upstream option rename would leave
# a WITH_<X>=OFF-shaped silence indistinguishable from a real build across
# every one of the vendors this spec exists to bundle (LESSONS_LEARNED.md #1
# and #5: a check -- and a %%install step -- that cannot tell "built" from
# "silently skipped" is worse than none).
for _lib in libapogee libASICamera2 libfli libPlayerOneCamera libinovasdk \
            libgxccd libsbig libtoupcam libfishcamp; do
    ls %{buildroot}%{indi_libdir}/${_lib}.so* >/dev/null 2>&1 \
        || { echo "ERROR: ${_lib} did not install -- an upstream WITH_* default or library name changed"; exit 1; }
done

%files apogee
%license libapogee/LICENSE
%dir %{indi_prefix}
%dir %{indi_libdir}
%{indi_libdir}/libapogee.so.*
%{_udevrulesdir}/*-indi-stable-3rdparty-*apogee*.rules
# Per-camera-model config data (CONF_DIR/Apogee/camera/*.txt,
# libapogee/CMakeLists.txt ~70) -- not code, but read at runtime by the
# apogee library itself, so it ships in the runtime subpackage, not -devel.
# Missing entirely from the original %%files (no %%license-adjacent line ever
# claimed them); caught by rpmbuild's "installed but unpackaged" check on the
# first real mock build, 2026-08-26.
%dir %{indi_prefix}/etc
%dir %{indi_prefix}/etc/Apogee
%{indi_prefix}/etc/Apogee/camera/

%files apogee-devel
%dir %{indi_includedir}
%{indi_includedir}/libapogee/
%{indi_libdir}/libapogee.so

%files asi
%license libasi/license.txt
# %%dir %%{indi_prefix}/%%{indi_libdir} here (and in every other vendor runtime
# subpackage below) is not redundant with indi-stable-core-libs/apogee already
# declaring them. Confirmed 2026-08-26 by actually installing core +
# 3rdparty-libs together and removing them together (STATUS.md): with only
# core-libs and apogee as explicit owners of these two directories, whichever
# of the two rpm happens to erase LAST in that single transaction is the one
# that gets to rmdir them -- and it is not always one of those two, so
# /opt/indi-stable and /opt/indi-stable/lib were left behind as empty dirs
# after a real combined removal. Every subpackage that places files here must
# independently declare ownership so the erasure order stops mattering.
%dir %{indi_prefix}
%dir %{indi_libdir}
# Five add_library(... SHARED IMPORTED) targets in libasi/CMakeLists.txt, not
# four. USB2ST4Conv (~48-51) IS a real target -- gated by HAVE_USB2ST4Conv,
# which is TRUE everywhere except Apple arm64 -- contrary to what an earlier
# reading of this file concluded ("does not actually declare as a target at
# all"); the first real mock build installed libUSB2ST4Conv.so* and rpmbuild's
# "installed but unpackaged" check caught the resulting mismatch on
# 2026-08-26. It lives in the SAME libasi/ directory under the SAME top-level
# license.txt as the other four -- no separate blob-specific licence notice,
# unlike libfli's flipro/flialgo below -- so it is covered by the same
# licence-tier decision and belongs here, not left out.
%{indi_libdir}/libASICamera2.so.*
%{indi_libdir}/libEFWFilter.so.*
%{indi_libdir}/libEAFFocuser.so.*
%{indi_libdir}/libCAARotator.so.*
%{indi_libdir}/libUSB2ST4Conv.so.*
# The bare .so symlinks live HERE, in the runtime package, not in -devel:
# these vendor blobs carry an UNVERSIONED SONAME (or none at all), so the
# driver's own DT_NEEDED is the bare name and the dynamic loader needs the
# symlink at RUN time, not merely at link time. Shipping it in -devel left
# every driver for this vendor unable to load on a runtime-only install --
# measured, not theorised: 45 of 56 driver binaries failed ldd that way on
# 2026-09-04. Vendors whose blobs DO carry a versioned SONAME (apogee, fli,
# playerone, sbig, inovasdk, fishcamp) keep the ordinary layout, with the
# symlink in -devel. See LESSONS_LEARNED.md #22.
%{indi_libdir}/libASICamera2.so
%{indi_libdir}/libEFWFilter.so
%{indi_libdir}/libEAFFocuser.so
%{indi_libdir}/libCAARotator.so
%{indi_libdir}/libUSB2ST4Conv.so
%{_udevrulesdir}/*-indi-stable-3rdparty-*asi*.rules

%files asi-devel
# Same directory-ownership reasoning as %%files asi above, applied to
# %%{indi_includedir}: every -devel subpackage below declares it.
%dir %{indi_includedir}
%{indi_includedir}/libasi/

%files fli
%license libfli/LICENSE.BSD
%dir %{indi_prefix}
%dir %{indi_libdir}
# libfli.so is the base FLI library, compiled from real source
# (fli_LIB_SRCS) under LICENSE.BSD -- this is the vendor bundled by the
# licence-tier decision.
#
# NOT packaged, on purpose: on Linux this same CMakeLists.txt unconditionally
# ALSO builds flipro/flialgo (libfli/CMakeLists.txt ~76-93) from prebuilt
# libflipro.bin/libflialgo.bin blobs -- found only while writing this spec,
# not part of the original licence-tier survey. libfli/ carries exactly one
# licence file, LICENSE.BSD, at the top level, with none inside flipro/
# specifically -- genuinely ambiguous whether it was meant to cover a blob
# added to a subdirectory of an otherwise source-shipping library, or whether
# that blob has no licence coverage at all, same as the four vendors already
# excluded. Left OUT of %%files rather than guessed either way; %%install now
# rm's them out of %%{buildroot} explicitly (confirmed 2026-08-26 that
# %%cmake_install does put them there) rather than relying on omission from
# this list alone. See STATUS.md for the follow-up.
%{indi_libdir}/libfli.so.*
%{_udevrulesdir}/*-indi-stable-3rdparty-*fli*.rules

%files fli-devel
%dir %{indi_includedir}
%{indi_includedir}/libfli.h
%{indi_libdir}/libfli.so

%files playerone
%license libplayerone/license.txt
%dir %{indi_prefix}
%dir %{indi_libdir}
%{indi_libdir}/libPlayerOne*.so.*
%{_udevrulesdir}/*-indi-stable-3rdparty-*player_one*.rules

%files playerone-devel
%dir %{indi_includedir}
%{indi_includedir}/libplayerone/
%{indi_libdir}/libPlayerOne*.so

%files inovasdk
%license libinovasdk/LICENSE.lib
%dir %{indi_prefix}
%dir %{indi_libdir}
%{indi_libdir}/libinovasdk*.so.*
%{_udevrulesdir}/*-indi-stable-3rdparty-*inovaplx*.rules

%files inovasdk-devel
%dir %{indi_includedir}
%{indi_includedir}/inovasdk/
%{indi_libdir}/libinovasdk*.so

%files micam
%license libmicam/LICENSE
%dir %{indi_prefix}
%dir %{indi_libdir}
%{indi_libdir}/libgxccd.so.*
# The bare .so symlinks live HERE, in the runtime package, not in -devel:
# these vendor blobs carry an UNVERSIONED SONAME (or none at all), so the
# driver's own DT_NEEDED is the bare name and the dynamic loader needs the
# symlink at RUN time, not merely at link time. Shipping it in -devel left
# every driver for this vendor unable to load on a runtime-only install --
# measured, not theorised: 45 of 56 driver binaries failed ldd that way on
# 2026-09-04. Vendors whose blobs DO carry a versioned SONAME (apogee, fli,
# playerone, sbig, inovasdk, fishcamp) keep the ordinary layout, with the
# symlink in -devel. See LESSONS_LEARNED.md #22.
%{indi_libdir}/libgxccd.so
%{_udevrulesdir}/*-indi-stable-3rdparty-*miccd*.rules

%files micam-devel
%dir %{indi_includedir}
%{indi_includedir}/libmicam/

%files sbig
%license libsbig/LICENSE.firmware
%dir %{indi_prefix}
%dir %{indi_libdir}
# The add_library() target in libsbig/CMakeLists.txt is named "sbig", not
# "sbigudrv" -- confirmed by reading it. libsbigudrv.so does not exist; only
# the HEADER is named sbigudrv.h (installed separately, below), which is a
# different thing from the library's own SONAME and is easy to conflate.
%{indi_libdir}/libsbig.so.*
# %%dir on share/, share/indi/ AND share/indi/firmware/ -- indi-stable-core's
# MAIN package also owns %%{indi_prefix}/share/ (core's own %%files, for its
# own %%{indi_datadir}), but core main is always erased before core-libs (it
# Requires core-libs) and owns neither %%{indi_prefix} nor these intermediate
# dirs itself -- so it can never be the last package standing for this
# subtree. Without sbig also declaring ownership here, share/ and share/indi/
# were left behind as empty dirs after a real combined core+3rdparty removal
# on 2026-08-26, the same class of bug %%files asi's comment documents for
# %%{indi_prefix}/%%{indi_libdir}.
#
# firmware/ itself is now a SHARED directory too, not sbig's alone: fishcamp
# (below, added 2026-08-27) installs into the identical FIRMWARE_INSTALL_DIR
# (libfishcamp/CMakeLists.txt), same as sbig's own. A bare recursive
# `%%{indi_prefix}/share/indi/firmware/` glob here would try to claim
# fishcamp's files too and fail the build with "file listed twice" --
# every firmware image is named explicitly instead, one vendor's worth per
# subpackage, same %%dir-ownership rule as %%{indi_prefix}/%%{indi_libdir}
# above applied one level deeper.
%dir %{indi_prefix}/share
%dir %{indi_prefix}/share/indi
%dir %{indi_prefix}/share/indi/firmware
%{indi_prefix}/share/indi/firmware/sbigucam.hex
%{indi_prefix}/share/indi/firmware/sbiglcam.hex
%{indi_prefix}/share/indi/firmware/sbigfcam.hex
%{indi_prefix}/share/indi/firmware/sbigpcam.hex
%{indi_prefix}/share/indi/firmware/stfga.bin
%{_udevrulesdir}/*-indi-stable-3rdparty-*sbig*.rules

%files sbig-devel
%dir %{indi_includedir}
%{indi_includedir}/libsbig/
%{indi_libdir}/libsbig.so

%files fishcamp
%license libfishcamp/COPYING.LIB
%dir %{indi_prefix}
%dir %{indi_libdir}
%{indi_libdir}/libfishcamp.so.*
# Same shared-directory reasoning as %%files sbig above, applied the other
# direction: fishcamp's own two firmware images, named explicitly, not the
# whole directory.
%dir %{indi_prefix}/share
%dir %{indi_prefix}/share/indi
%dir %{indi_prefix}/share/indi/firmware
%{indi_prefix}/share/indi/firmware/gdr_usb.hex
%{indi_prefix}/share/indi/firmware/Guider_mono_rev16_intel.srec
%{_udevrulesdir}/*-indi-stable-3rdparty-*fishcamp*.rules

%files fishcamp-devel
%dir %{indi_includedir}
%{indi_includedir}/libfishcamp/
%{indi_libdir}/libfishcamp.so

%files touptek
%license libtoupcam/COPYING.LGPL
%dir %{indi_prefix}
%dir %{indi_libdir}
%{indi_libdir}/libtoupcam.so.*
%{indi_libdir}/libaltaircam.so.*
%{indi_libdir}/libbressercam.so.*
%{indi_libdir}/libmallincam.so.*
%{indi_libdir}/libmeadecam.so.*
%{indi_libdir}/libnncam.so.*
%{indi_libdir}/libogmacam.so.*
%{indi_libdir}/libomegonprocam.so.*
%{indi_libdir}/libstarshootg.so.*
%{indi_libdir}/libtscam.so.*
%{indi_libdir}/libsvbonycam.so.*
# The bare .so symlinks live HERE, in the runtime package, not in -devel:
# these vendor blobs carry an UNVERSIONED SONAME (or none at all), so the
# driver's own DT_NEEDED is the bare name and the dynamic loader needs the
# symlink at RUN time, not merely at link time. Shipping it in -devel left
# every driver for this vendor unable to load on a runtime-only install --
# measured, not theorised: 45 of 56 driver binaries failed ldd that way on
# 2026-09-04. Vendors whose blobs DO carry a versioned SONAME (apogee, fli,
# playerone, sbig, inovasdk, fishcamp) keep the ordinary layout, with the
# symlink in -devel. See LESSONS_LEARNED.md #22.
%{indi_libdir}/libtoupcam.so
%{indi_libdir}/libaltaircam.so
%{indi_libdir}/libbressercam.so
%{indi_libdir}/libmallincam.so
%{indi_libdir}/libmeadecam.so
%{indi_libdir}/libnncam.so
%{indi_libdir}/libogmacam.so
%{indi_libdir}/libomegonprocam.so
%{indi_libdir}/libstarshootg.so
%{indi_libdir}/libtscam.so
%{indi_libdir}/libsvbonycam.so
%{_udevrulesdir}/*-indi-stable-3rdparty-*toupcam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*altaircam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*bressercam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*mallincam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*meadecam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*nncam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*ogmacam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*omegonprocam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*starshootg*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*tscam*.rules
%{_udevrulesdir}/*-indi-stable-3rdparty-*svbonycam*.rules

%files touptek-devel
%dir %{indi_includedir}
%{indi_includedir}/libtoupcam/
%{indi_includedir}/libaltaircam/
%{indi_includedir}/libbressercam/
%{indi_includedir}/libmallincam/
%{indi_includedir}/libmeadecam/
%{indi_includedir}/libnncam/
%{indi_includedir}/libogmacam/
%{indi_includedir}/libomegonprocam/
%{indi_includedir}/libstarshootg/
%{indi_includedir}/libtscam/
%{indi_includedir}/libsvbonycam/

%changelog
* Fri Sep 04 2026 Will Snyder <william@williamlsnyder.org> - 2.2.4.1-2
- New upstream release v2.2.4.1, built and gated by 3rdparty-release.yml.

* Wed Aug 26 2026 Will Snyder <william@williamlsnyder.org> - 2.2.4.1-1
- Initial package. Builds upstream indi-3rdparty tag v2.2.4.1 with
  -DBUILD_LIBS=ON into the shared private prefix. Builds, installs and
  removes cleanly alongside indi-stable-core as of 2026-08-26. See STATUS.md.
  Fishcamp added 2026-08-27 once its licence was confirmed clear (DESIGN.md,
  "QSI and Fishcamp resolved"); not yet released, so folded into the initial
  entry rather than given its own dated one, same convention as core.spec.
