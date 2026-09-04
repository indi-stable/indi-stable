# indi-stable-core -- INDI core library and server, built from an upstream
# stable tag and installed into a private prefix so it never collides with
# the distribution's own INDI packages.
#
# See DESIGN.md for the full rationale. The short version:
#
#   * Distinct namespace, never replaces the distro's packages. Someone
#     running KStars/Ekos or Stellarium off the distro INDI must be able to
#     install this without their setup changing underneath them.
#   * SONAME versioning alone is NOT enough to achieve that. It is what lets
#     a 1.9.9 distro build and a 2.x build coexist today (.so.1 vs .so.2),
#     but this project ships stable releases exactly as the distro does, so
#     our libindiclient.so.2 and theirs will routinely share a SONAME. Hence
#     a private prefix, not a shared libdir.
#   * Everything INDI installs derives from CMAKE_INSTALL_PREFIX
#     (verified in indi/CMakeLists.txt: DATA_INSTALL_DIR line 72,
#     BIN_INSTALL_DIR 73, INCLUDE_INSTALL_DIR 82, PKG_CONFIG_LIBDIR 86),
#     so a self-contained prefix isolates the whole tree with no patching.
#     The driver-manifest directory (share/indi/drivers.xml) falls out of
#     that automatically -- confirmed live against two coexisting installs.
#   * UDEVRULES_INSTALL_DIR is the ONE exception: an absolute path, not
#     under the prefix. See the %install section -- it is handled there, and
#     it is a genuine file conflict if left alone.

# /opt, not %%{_libdir}/indi-stable, and identically on Debian. FHS 3.13
# reserves /opt for add-on application software, which is exactly what this
# is; both Fedora's and Debian's prohibitions on /opt bind only packages
# shipped *by* the distribution. The deciding factor is cross-distro path
# consistency: %%{_libdir} resolves to /usr/lib64 on Fedora but the multiarch
# /usr/lib/<triplet> on Debian, so users would have to type a different path
# into Ekos's "INDI drivers XML directory" and indi-web --xmldir depending on
# their distro. One path across all four targets is worth more than adherence
# to a rule that does not apply to third-party repositories.
%global indi_prefix     /opt/indi-stable
%global indi_libdir     %{indi_prefix}/lib
%global indi_bindir     %{indi_prefix}/bin
%global indi_includedir %{indi_prefix}/include
%global indi_datadir    %{indi_prefix}/share/indi

# Upstream tags carry a leading v and a fourth component that the CMake
# project version does not (tag v2.2.4.2 builds a 2.2.4 library). The RPM
# version tracks the *tag*, because that is what this project promotes and
# what versions.json records; the SONAME still comes from CMake.
%global upstream_tag    v%{version}

# --- Dependency-generator filtering: THIS IS PART OF THE COEXISTENCE RULE ---
#
# Without these, RPM's automatic dependency generator scans the private tree
# and advertises our libraries to the whole system. Verified 2026-08-24, the
# unfiltered -libs package Provides:
#
#   libindiclient.so.2()(64bit)   libindidriver.so.2()(64bit)
#   libindiAlignmentDriver.so.2()(64bit)   libindilx200.so.2()(64bit)
#
# which are EXACTLY the Provides of Fedora's own libindi-libs. That is
# shadowing -- the third verb in the one rule -- at the metadata layer rather
# than the filesystem. It is not hypothetical: on Fedora, phd2 and stellarium
# require `libindiclient.so.2()(64bit)` with NO package-name dependency on
# libindi. With our unfiltered package installed on a machine that does not
# yet have the distro INDI, `dnf install stellarium` finds that dependency
# already satisfied, never pulls in libindi-libs, and stellarium then fails at
# runtime -- our copy is in the private prefix, which is not on the loader
# path and which stellarium has no RPATH into. (kstars happens to escape
# because it also requires `libindi` by package name, but that is luck.)
#
# The two filters MUST be applied together. Filtering Provides alone would
# leave our own auto-generated Requires on those same SONAMEs unsatisfiable
# from within this package set -- so installing indi-stable-core would drag
# in the DISTRIBUTION's libindi-libs to satisfy them. That is the same bug
# pointing the other way.
#
#   * Provides: PATH-based over the whole prefix. Nothing under the private
#     tree should ever be advertised system-wide.
#   * Requires: STRING-based, matching the libindi* SONAMEs only. Path-based
#     filtering would be wrong here: it would also drop the legitimate
#     external dependencies these same binaries carry (libcfitsio.so.10,
#     libnova-0.16.so.0, libstdc++, ...), which rpm must still see.
#
# Verified on rpm 6.0.2 with a harness packaging the real built binaries:
# Provides reduced to the package's own name, libindi* Requires dropped, and
# libcfitsio/libnova/libc/libstdc++ all correctly retained.
#
# Inter-subpackage dependencies do not rely on the filtered SONAMEs: the
# explicit `Requires: %%{name}-libs%%{?_isa} = %%{version}-%%{release}` below is
# a name-and-version dependency and is unaffected.
%global __provides_exclude_from ^%{indi_prefix}/.*$
%global __requires_exclude      ^libindi.*\\.so.*$

Name:           indi-stable-core
Version:        2.2.4.2
Release:        1%{?dist}
Summary:        INDI core library and server (stable upstream release, private prefix)

# INDI itself is LGPL-2.1+/GPL-2.0+. This spec file is MIT, but the license
# tag must describe the packaged software, not the packaging.
License:        LGPL-2.1-or-later AND GPL-2.0-or-later
URL:            https://github.com/indilib/indi
Source0:        https://github.com/indilib/indi/archive/refs/tags/%{upstream_tag}.tar.gz#/indi-%{upstream_tag}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  make
# Defines %%{_udevrulesdir}, used in %%install and %%files.
BuildRequires:  systemd-rpm-macros
# find_package() calls in indi/CMakeLists.txt, plus the wider set upstream
# needs for the full driver tree. Kept in sync with CORE_BUILD_PACKAGES in
# ACS's setup_indi_core.py, which was verified against real repos.
BuildRequires:  zlib-devel
BuildRequires:  cfitsio-devel
BuildRequires:  libnova-devel
BuildRequires:  libusb1-devel
BuildRequires:  libcurl-devel
BuildRequires:  gsl-devel
BuildRequires:  libjpeg-turbo-devel
BuildRequires:  libev-devel
BuildRequires:  gpsd-devel
BuildRequires:  LibRaw-devel
BuildRequires:  libftdi-devel
BuildRequires:  krb5-devel
BuildRequires:  libtiff-devel
BuildRequires:  fftw-devel
BuildRequires:  rtl-sdr-devel
BuildRequires:  libgphoto2-devel
BuildRequires:  libdc1394-devel
BuildRequires:  boost-devel
BuildRequires:  libtheora-devel
BuildRequires:  libXISF-devel
BuildRequires:  erfa-devel

Requires:       %{name}-libs%{?_isa} = %{version}-%{release}
# alternatives(8) manages a namespaced /usr/bin/indiserver-stable link, NOT
# /usr/bin/indiserver -- see DESIGN.md "Resolution -- namespaced link, not
# /usr/bin/indiserver". Fedora's libindi ships /usr/bin/indiserver as a plain
# file it owns, not a symlink; alternatives --install refuses to replace it
# but still exits 0, so registering the real name is a silent no-op, not a
# working coexistence mechanism. The namespaced name is owned by no
# distribution, so registration always succeeds. See %post/%postun.
Requires(post):   %{_sbindir}/alternatives
Requires(postun): %{_sbindir}/alternatives

%description
INDI (Instrument-Neutral Distributed Interface) is a distributed control
protocol for astronomical instrumentation. This package provides indiserver
and the bundled device drivers, built from an upstream stable release tag.

It installs into a private prefix (%{indi_prefix}) and registers
indiserver-stable through alternatives(8), so it coexists with a
distribution-provided INDI rather than replacing it. Nothing this package
installs overwrites a file owned by another package.

This is an unofficial third-party build. It is not affiliated with or
endorsed by the INDI project.

%package libs
Summary:        Shared libraries for indi-stable-core
%description libs
The INDI client, driver and alignment shared libraries, installed under
%{indi_libdir}. Consumers find them through RPATH rather than the system
library search path, so they never shadow a distribution INDI.

%package devel
Summary:        Development files for indi-stable-core
Requires:       %{name}-libs%{?_isa} = %{version}-%{release}
%description devel
Headers, static libraries and pkg-config metadata for building against
indi-stable-core.

Headers install to %{indi_includedir}, NOT /usr/include/libindi. That is
deliberate and load-bearing: headers are not SONAME-versioned, and
/usr/include precedes /usr/local/include and any private path in the default
compiler search order, so a distribution -devel package left installed would
silently win. Build against this package with:

    pkg-config --with-path=%{indi_libdir}/pkgconfig --cflags --libs libindi

%prep
# GitHub strips a leading "v" from the tag when naming the tarball's root
# directory, so tag v2.2.4.2 unpacks to indi-2.2.4.2 -- %%{version}, not
# %%{upstream_tag}. -p1 applies anything in patches/ (see DESIGN.md: a pinned
# tag will meet compilers it predates, and carrying a fix here beats waiting
# on an upstream merge to ship a release).
%autosetup -n indi-%{version} -p1

%build
# FIX_WARNINGS=OFF is upstream's own -Werror escape hatch
# (cmake_modules/CMakeCommon.cmake). A pinned tag is by definition older than
# some compiler it will be built with, and warnings-as-errors turns that into
# a hard build failure in code nothing here even loads -- this is not
# hypothetical, gcc 15 broke drivers/telescope/astrotrac.cpp exactly this way.
# Absorbing that is part of what a packaging layer is for.
#
# INDI_INSTALL_UDEV_RULES stays ON, but UDEVRULES_INSTALL_DIR is redirected
# into the build root's private tree; %install then renames the files. Left
# at its default (/lib/udev/rules.d) it installs 99-indi_auxiliary.rules and
# 80-dbk21-camera.rules under names the distribution's own package already
# owns -- an outright file conflict, and the only place in the entire build
# where a path is not derived from CMAKE_INSTALL_PREFIX.
#
# CMAKE_INSTALL_LIBDIR must be RELATIVE ("lib", not "/usr/lib64"). Two
# separate reasons, both load-bearing:
#   1. Fedora's own %%cmake macro passes it as an absolute path, and INDI
#      builds its pkgconfig destination straight off it --
#   set(PKGCONFIG_INSTALL_PREFIX "${CMAKE_INSTALL_LIBDIR}/pkgconfig/")
#      (CMakeLists.txt:83), so an absolute value puts libindi.pc in the
#      system /usr/lib64/pkgconfig -- outside the private prefix, colliding
#      with the distribution's own libindi-devel.
#   2. It is plain "lib", not %%{_lib}: inside a self-contained /opt tree
#      there is no lib/lib64 split to honour, and using lib64 here would
#      make the RPM and Debian trees diverge for no benefit. %%{indi_libdir}
#      above must agree with this value.
# These -D flags follow %%cmake's on the command line, so they win.
%cmake \
    -DCMAKE_INSTALL_PREFIX=%{indi_prefix} \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_RPATH=%{indi_libdir} \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
    -DFIX_WARNINGS=OFF \
    -DINDI_BUILD_SERVER=ON \
    -DINDI_BUILD_CLIENT=ON \
    -DINDI_BUILD_DRIVERS=ON \
    -DINDI_BUILD_QT_CLIENT=OFF \
    -DINDI_INSTALL_UDEV_RULES=ON \
    -DUDEVRULES_INSTALL_DIR=%{indi_prefix}/udev-rules
%cmake_build

%install
# Fedora's check-rpaths (run from %%__arch_install_post, inside this same
# scriptlet) rejects our RPATH with "ERROR 0002: invalid runpath". The label is
# misleading: /opt/indi-stable/lib is a perfectly well-formed absolute path.
# Reading /usr/lib/rpm/check-rpaths-worker, the classifier is a hardcoded
# allowlist -- /lib/*, /usr/lib/*, /lib64/*, /usr/lib64/*, /usr/libexec/*,
# $ORIGIN -- and *everything else* falls through to `(*) badness=2` (line 141).
# /opt is simply not on that list. It is not diagnosing a defect.
#
# This is the linter DESIGN.md says must not be "fixed" by dropping the RPATH:
# the RPATH into the private libdir IS the coexistence guarantee. So downgrade
# the one class that misfires, rather than disabling the check. Per the worker's
# msg() (line 81), a class whose bit is set in QA_RPATHS becomes a non-fatal
# WARNING; every other class stays fatal -- notably 0x0004 (insecure *relative*
# RPATH) and 0x0020 ('..' traversal), which would be real bugs worth failing on.
#
# Deliberately NOT `%%global __brp_check_rpaths %%{nil}`: that would switch the
# whole check off and lose those two protections along with the false positive.
export QA_RPATHS=$(( 0x0002 ))

%cmake_install

# --- udev rules: the one path INDI does not derive from the prefix ---------
# Re-home them into the real udev directory under namespaced filenames, so
# they take effect without colliding with the distribution's copies. The
# numeric prefix is preserved because udev applies rules in lexical order.
# NOTE the four percent signs in ${base%%%%-*}. RPM collapses %%%% -> %% before
# the shell ever sees this line, so the shell receives ${base%%-*} -- strip the
# LONGEST -* suffix, i.e. the leading number alone. Writing the obvious %%-*
# here is a trap: it reaches the shell as %-* (strip the SHORTEST suffix) and
# silently produces the wrong prefix on any filename with more than one hyphen.
# That is not hypothetical -- it shipped in the first build that got this far:
#   80-dbk21-camera.rules -> 80-dbk21-indi-stable-dbk21-camera.rules
# while 99-indi_auxiliary.rules came out right purely because it has one hyphen.
# Verified with `rpmspec --parse`. debian/rules is NOT affected: make leaves %
# alone in recipe text, so its $${base%%-*} already reaches the shell intact --
# which is exactly why the two packagings disagreed on this filename.
mkdir -p %{buildroot}%{_udevrulesdir}
for rule in %{buildroot}%{indi_prefix}/udev-rules/*.rules; do
    [ -e "$rule" ] || continue
    base=$(basename "$rule")
    mv "$rule" "%{buildroot}%{_udevrulesdir}/${base%%%%-*}-indi-stable-${base#*-}"
done
rm -rf %{buildroot}%{indi_prefix}/udev-rules

# --- driver catalogue: absolute paths, not bare names ----------------------
# Upstream generates drivers.xml naming each binary by BARE NAME, e.g.
#   <driver name="CCD Simulator">indi_simulator_ccd</driver>
# A bare name is resolved by execvp through PATH, and the private bindir is
# deliberately not on PATH, so /usr/bin wins and a picker pointed at our
# catalogue still launches the DISTRIBUTION's drivers. Our file and the
# distribution's are otherwise byte-identical, so the prefix alone buys
# nothing here. See DESIGN.md, "Driver-manifest discoverability".
#
# Rewriting the entries to absolute paths is what makes the private prefix
# reachable: someone points KStars/Ekos (indiDriversDir) or INDI Web Manager
# (--xmldir) at %{indi_datadir} and gets OUR drivers, explicitly and
# reversibly, with no PATH change and nothing shadowed. Verified on a live
# Ekos session 2026-08-25.
#
# Only entries whose binary this package actually ships are rewritten. The
# catalogue lists drivers built by other packages -- and two that exist in no
# build at all -- and inventing paths for those would turn a driver that is
# merely absent into one that fails with a wrong path.
_cat=%{buildroot}%{indi_datadir}/drivers.xml
test -f "$_cat" || { echo "ERROR: $_cat is missing; upstream layout changed"; exit 1; }
_sed=$(mktemp)
# EVERY executable we ship, not just indi_*. The catalogue lists at least one
# driver whose binary carries no indi_ prefix (shelyak_usis), and an indi_*
# glob leaves it a bare name -- resolving to the distribution's copy, which is
# precisely the bug this block exists to remove. indiserver is swept up
# harmlessly: it is not a <driver> entry, so its rule never matches.
for _b in %{buildroot}%{indi_bindir}/*; do
    [ -f "$_b" ] && [ -x "$_b" ] || continue
    _n=$(basename "$_b")
    # No printf: a % in a format string is a macro sigil to RPM before the
    # shell ever sees it. echo keeps this line free of them.
    echo "s|>${_n}</driver>|>%{indi_bindir}/${_n}</driver>|g" >> "$_sed"
done
sed -i -f "$_sed" "$_cat"
rm -f "$_sed"

# Assert the rewrite happened, rather than trusting that it did. A silent
# no-op here ships a catalogue that looks right and resolves to /usr/bin --
# exactly the failure this whole change exists to remove.
_done=$(grep -c ">%{indi_bindir}/" "$_cat") || _done=0
test "$_done" -gt 0 || { echo "ERROR: rewrote 0 catalogue entries; the <driver> form changed upstream"; exit 1; }
# Derive this check from the CATALOGUE, never from the same glob that drove
# the rewrite. The first version of this block looped over indi_* in both
# places, so the check inherited the blind spot it was meant to catch and
# passed while shelyak_usis shipped as a bare name. Asking "which entries are
# still bare, and do we ship any of them?" cannot share that flaw.
_left=0
for _n in $(grep -oE '<driver[^>]*>[^<>/][^<>]*</driver>' "$_cat" \
            | sed -e 's|</driver>$||' -e 's|^.*>||' | sort -u); do
    if [ -x "%{buildroot}%{indi_bindir}/${_n}" ]; then
        echo "ERROR: $_n is shipped by this package but is still a bare name"
        _left=$(( _left + 1 ))
    fi
done
test "$_left" -eq 0 || { echo "ERROR: $_left shipped driver(s) left unrewritten"; exit 1; }
echo "drivers.xml: rewrote $_done entries to %{indi_bindir}"

# --- pkg-config: two fixes to the generated libindi.pc ---------------------
# Both exist for the same underlying reason: upstream's template is written for
# an install at prefix=/usr, where the compiler and the dynamic linker already
# search the right directories by default. In a private prefix neither does,
# and each omission fails SILENTLY.
#
# (1) Libs: -- the RPATH.
# Upstream's libindi.pc.cmake hardcodes
#     Libs: -L${libdir} -lindiclient
# and -L is a LINK-time search path only. Our own binaries do not care, because
# CMake bakes CMAKE_INSTALL_RPATH into each of them at build time -- but
# nothing does that for a third-party consumer, and %{indi_libdir} is
# deliberately absent from ld.so.conf and ldconfig. So a program built against
# the -devel subpackage links fine and then loads the wrong library, or none:
# on a box with no other copy of the SONAME it dies at startup with
# "libindiclient.so.2: cannot open shared object file", and on a box that has
# the distribution's -- the configuration this package exists for -- it
# silently loads /lib64/libindiclient.so.2 against our headers and exits 0.
# Both measured, the second on Fedora 2026-08-25. See DESIGN.md, "Consumers of
# the private prefix need the RPATH too".
#
# Appending -Wl,-rpath gives consumers the same mechanism our own binaries rely
# on: per-consumer, opt-in, no global state touched. The tempting alternative,
# an /etc/ld.so.conf.d entry, is exactly the shadowing this project exists to
# prevent and must never be added.
#
# Demonstrated on the DEB side 2026-08-25 (compile, link and RUN, before and
# after), and on this one the same day: rebuilt through mock and exercised by
# scripts/test-devel-compile-mock.sh, which compiles and runs a consumer in a
# chroot holding both INDIs and reproduces the pre-fix defect as its control.
#
# grep -F, not plain grep: the pattern is a literal string containing a '$'
# that is not an anchor. POSIX says '$' is literal mid-BRE, but implementations
# disagree -- ugrep treats it as an anchor and never matches. -F sidesteps it.
#
# (2) Cflags: -- the parent include directory.
# Upstream DROPPED -I${includedir} between 1.9.9 and 2.2.4, keeping only
# -I${includedir}/libindi. At prefix=/usr that loses nothing, because
# /usr/include is searched implicitly and both spellings land in the same tree.
# Under our prefix only the second-level directory is on the path, so:
#     #include <indiversion.h>         -> ours
#     #include <libindi/indiversion.h> -> /usr/include/libindi, the
#                                         DISTRIBUTION's headers, against our
#                                         library
# Measured with g++ -E -H on the DEB, both spellings. That mismatch is silent,
# and it is the exact failure the private include path exists to prevent --
# headers are not SONAME-versioned and /usr/include wins the search order.
# Restoring -I${includedir} puts both spellings back on our tree. Safe because
# our includedir holds nothing but the libindi/ subdirectory, so it exposes no
# header that could shadow a system one.
#
# ${libdir} and ${includedir} must stay LITERAL in the output: they are
# pkg-config's own variable syntax, expanded by pkg-config at query time, not
# by CMake, RPM or the shell. The single quotes are what stop the %%install
# shell expanding them to nothing.
_pc=%{buildroot}%{indi_libdir}/pkgconfig/libindi.pc
test -f "$_pc" || { echo "ERROR: $_pc is missing; upstream layout changed"; exit 1; }
sed -i 's|^Libs: -L${libdir} -lindiclient|Libs: -L${libdir} -Wl,-rpath,${libdir} -lindiclient|' "$_pc"
grep -qF -- '-Wl,-rpath,${libdir}' "$_pc" \
    || { echo "ERROR: libindi.pc Libs: line did not gain the RPATH; upstream changed the template"; exit 1; }
sed -i 's|^Cflags: -I${includedir}/libindi|Cflags: -I${includedir} -I${includedir}/libindi|' "$_pc"
grep -qF -- 'Cflags: -I${includedir} -I${includedir}/libindi' "$_pc" \
    || { echo "ERROR: libindi.pc Cflags: line did not gain -I\${includedir}; upstream changed the template"; exit 1; }
echo "libindi.pc: $(grep '^Libs:' "$_pc")"
echo "libindi.pc: $(grep '^Cflags:' "$_pc")"

# alternatives manages /usr/bin/indiserver-stable, a namespaced name owned by
# no distribution -- NOT the plain /usr/bin/indiserver. On Fedora that name is
# an ordinary file owned by libindi, not a symlink, and alternatives --install
# refuses to replace it while still exiting 0, making it a silent no-op rather
# than a working coexistence mechanism (DESIGN.md "Resolution -- namespaced
# link, not /usr/bin/indiserver"). This package ships no file at either path;
# the real binary stays in the private prefix, which alternatives can point
# to without it living in a bin directory.
%post
%{_sbindir}/alternatives --install \
    %{_bindir}/indiserver-stable indiserver-stable \
    %{indi_bindir}/indiserver 20

%postun
if [ $1 -eq 0 ]; then
    %{_sbindir}/alternatives --remove indiserver-stable %{indi_bindir}/indiserver
fi

%files
%license LICENSE COPYING.BSD COPYING.GPL COPYING.LGPL
%doc README.md
%{indi_bindir}/
%{indi_prefix}/share/
%{_udevrulesdir}/*-indi-stable-*.rules

# The private tree's top-level directories are owned here rather than in the
# main package: main and devel both Requires: libs, so libs is present
# whenever any part of this package set is, but libs can also be installed
# on its own -- which would leave these directories unowned if main held them.
%files libs
%dir %{indi_prefix}
%dir %{indi_libdir}
%{indi_libdir}/*.so.*

# Alignment-subsystem math plugins. These live in -libs, not -devel, despite
# carrying an unversioned .so name: they are dlopen'd MODULEs, not link-time
# libraries. libs/alignment/MathPluginManagement.cpp opendir()s the directory,
# readdir()s it and dlopen()s each entry at runtime (lines 447-467), so a
# runtime-only install that lacked them would enumerate zero math plugins and
# degrade silently rather than fail.
#
# They need an explicit entry because the globs above are not recursive --
# %%{indi_libdir}/*.so.* and the devel package's %%{indi_libdir}/*.so both match
# only the top level, so this subdirectory was installed-but-unpackaged and
# failed the build on check-files.
#
# The directory is a second consumer of the relative CMAKE_INSTALL_LIBDIR rule
# documented in %%build: libs/alignment/CMakeLists.txt:1 builds it as
# ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/indi/MathPlugins and bakes it
# into the binary as -DINDI_MATH_PLUGINS_DIRECTORY (verified in the generated
# flags.make). An absolute libdir would yield /opt/indi-stable//usr/lib64/...
# -- installed outside the prefix, and unfindable at runtime.
%dir %{indi_libdir}/indi
%dir %{indi_libdir}/indi/MathPlugins
%{indi_libdir}/indi/MathPlugins/*.so

%files devel
%{indi_includedir}/
%{indi_libdir}/*.so
%{indi_libdir}/*.a
%{indi_libdir}/pkgconfig/

%changelog
* Sun Aug 23 2026 Will Snyder <william@williamlsnyder.org> - 2.2.4.2-1
- Initial package. Builds upstream tag v2.2.4.2 into a private prefix.
- alternatives registers indiserver-stable, not indiserver: the plain name is
  an ordinary file libindi owns on Fedora, so registering it silently no-ops
  instead of coexisting. See DESIGN.md. (Not yet released, so folded into the
  initial entry rather than given its own dated one.)
