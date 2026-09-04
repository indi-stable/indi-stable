# indi-stable-pyindi-client -- Python bindings for INDI's C++ client API,
# built and version-matched against THIS project's indi-stable-core rather
# than any system libindi.
#
# See DESIGN.md, "pyindi-client -- packaging decisions", 2026-08-26, for the
# two decisions made before writing any of this project's pyindi-client
# packaging (Debian side written first, this spec translates it):
#
#   * Built from the untagged 2.2.0 PyPI release, not the last real git tag
#     (v2.1.2 needs a static libindiclient.a this project's core/ does not
#     build; 2.2.0 is upstream's own released state, just missing the tag).
#   * The compiled module installs to the ordinary system Python location,
#     NOT /opt/indi-stable -- deliberately, not an exception to "coexistence,
#     the one rule everything else serves" (CLAUDE.md). A Python package
#     named PyIndi has no path- or metadata-level collision surface: no
#     distribution package of any name to shadow (confirmed via repoquery,
#     see DESIGN.md), and Python's own per-interpreter import resolution is
#     not a filesystem SONAME collision. The real collision risk -- which
#     libindiclient.so the compiled extension resolves at runtime -- is
#     handled the ordinary way, via RPATH into the private libdir, below.

%global indi_prefix /opt/indi-stable
%global indi_libdir %{indi_prefix}/lib
# The libindi/ CHILD directory specifically, not the parent -- upstream's own
# setup.cfg needs both on the search path (see %%build), and pyindi-client/
# deb/rules names this same value INDI_INCDIR for the same reason.
%global indi_incdir %{indi_prefix}/include/libindi

Name:           indi-stable-pyindi-client
Version:        2.2.0
Release:        1%{?dist}
Summary:        Python bindings for the INDI client library (indi-stable build)

# pyindi-client itself is GPL-3.0-or-later (LICENSE is the plain GPLv3 text;
# pyproject.toml's own classifier reads "GNU General Public License v3 or
# later (GPLv3+)", confirmed 2026-08-27 against the real 2.2.0 sdist). This
# spec file is MIT, but the License: tag describes the packaged software, not
# the packaging -- same convention as indi-stable-core.spec.
License:        GPL-3.0-or-later
URL:            https://github.com/indilib/pyindi-client

# The exact commit PyPI published as 2.2.0 -- no corresponding git tag exists
# (see DESIGN.md). Pinned to the fully-resolved files.pythonhosted.org URL
# rather than the pypi.io/pypi.org redirect shorthand, since that URL is
# immutable once published; the pypi.io form depends on redirect
# infrastructure staying up. sha256 verified 2026-08-27 both against PyPI's
# own JSON API digest (pypi.org/pypi/pyindi-client/2.2.0/json) and by hashing
# a local download directly -- not trusted from one source alone.
Source0:        https://files.pythonhosted.org/packages/55/92/bbde7827ad87fbd56ce9586f7beb0cf677b7618aab5d8a1368a2f18ca8cf/pyindi_client-2.2.0.tar.gz

BuildRequires:  python3-devel
BuildRequires:  python3-setuptools
BuildRequires:  gcc-c++
BuildRequires:  swig
BuildRequires:  zlib-devel
BuildRequires:  cfitsio-devel
BuildRequires:  libnova-devel
BuildRequires:  indi-stable-core-devel

# --- Dependency-generator filtering -----------------------------------------
#
# The compiled _PyIndi*.so links libindiclient.so.2 via RPATH (see %%build).
# RPM's automatic ELF dependency generator scans DT_NEEDED regardless of
# whether the scanned FILE itself carries a SONAME, so without this it would
# add an unfiltered `Requires: libindiclient.so.2()(64bit)` -- satisfiable by
# a DISTRIBUTION libindi-libs sharing that SONAME (a real, not hypothetical,
# collision: Fedora's own libindi-libs ships the identical SONAME) instead of
# by this project's own package, which is exactly the shadowing-at-the-
# metadata-layer bug indi-stable-core.spec's own header documents. Same
# pattern, same fix, as core.spec and indi-stable-3rdparty-drivers.spec: drop
# the auto-Requires and depend on indi-stable-core-libs BY NAME below instead.
#
# No __provides_exclude_from needed here, unlike core/3rdparty: this package
# ships no SONAME-carrying library of its own to accidentally advertise.
# _PyIndi*.so is a dlopen()'d Python extension module built without
# -Wl,-soname, so RPM's Provides generator (which keys off DT_SONAME) already
# emits nothing for it.
%global __requires_exclude ^libindi.*\\.so.*$

# Independent version axis from indi-stable-core -- same reasoning as
# indi-stable-3rdparty-drivers.spec's own unversioned Requires on this same
# package: this spec's Version tracks pyindi-client's own upstream release,
# not core's.
Requires:       indi-stable-core-libs%{?_isa}

%description
SWIG-generated Python bindings for INDI's C++ client API
(INDI::BaseClient et al.), built and version-matched against this
project's own indi-stable-core rather than any system libindi.

This is indilib/pyindi-client's own upstream binding, rebuilt against
this project's private INDI prefix; it is not a fork.

Unofficial third-party build; not affiliated with or endorsed by the
INDI project.

%prep
echo "2f224edcc52177aa380bece0d82fb65369ac65eeeb526c65d08211687b7f571a  %{SOURCE0}" | sha256sum -c - \
    || { echo "ERROR: pyindi_client-%{version}.tar.gz sha256 mismatch -- upstream tarball changed"; exit 1; }
# PyPI's sdist unpacks to pyindi_client-VERSION (underscore, the normalized
# distribution name), not pyindi-client-VERSION -- confirmed 2026-08-27
# against the real tarball.
%autosetup -n pyindi_client-%{version}

%build
test -d %{indi_incdir} || { echo "ERROR: %{indi_incdir} missing -- is indi-stable-core-devel a BuildRequires?"; exit 1; }

# Replace, not append -- upstream's own setup.cfg defaults name distro paths
# (/usr/include, /usr/local/include/libindi) this project must never resolve
# against. Same fix, same reasoning, as pyindi-client/deb/rules's
# override_dh_auto_configure.
sed -i \
  -e "s|^include_dirs = .*|include_dirs = %{indi_prefix}/include:%{indi_incdir}|" \
  -e "s|^swig_opts = .*|swig_opts = -v -Wall -c++ -threads -I%{indi_prefix}/include -I%{indi_incdir}|" \
  setup.cfg
grep -qF -- "%{indi_incdir}" setup.cfg \
  || { echo "ERROR: setup.cfg did not gain the private include path; upstream changed the file"; exit 1; }

# setup.cfg has no key for library_dirs/extra_link_args -- both are literals
# in setup.py's own Extension() call. Dropping /usr/lib(64) entirely from
# library_dirs is deliberate: those are the compiler's default search path
# anyway for z/cfitsio/nova, and INCLUDING them would let -lindiclient
# resolve a distro libindi-devel's own unversioned symlink instead of ours
# if it ever sorted first -- don't trust order, remove the ambiguity
# (LESSONS_LEARNED.md #11), same fix as pyindi-client/deb/rules.
sed -i \
  -e 's|library_dirs=\["/usr/lib", "/usr/lib64", "/lib", "/lib64"\]|library_dirs=["%{indi_libdir}"]|' \
  -e 's|extra_link_args=\["-shared"\]|extra_link_args=["-shared", "-Wl,-rpath,%{indi_libdir}"]|' \
  setup.py
grep -qF -- 'library_dirs=["%{indi_libdir}"]' setup.py \
  || { echo "ERROR: setup.py's Extension() did not gain the private library_dirs; upstream changed the file"; exit 1; }
grep -qF -- '-Wl,-rpath,%{indi_libdir}' setup.py \
  || { echo "ERROR: setup.py's Extension() did not gain the RPATH; upstream changed the file"; exit 1; }
echo "setup.cfg: $(grep '^include_dirs' setup.cfg)"
echo "setup.cfg: $(grep '^swig_opts' setup.cfg)"
echo "setup.py:  $(grep 'library_dirs=\[' setup.py)"
echo "setup.py:  $(grep 'extra_link_args=\[' setup.py)"

# `setup.py build` (not `build_ext` alone) runs build_py AND build_ext:
# build_py is what copies PyIndi.py/__init__.py into the build tree, a
# SEPARATE step build_ext alone skips. Confirmed on the Debian side
# 2026-08-26 before this ever reached a real build: build_ext alone produces
# a directory with no __init__.py, which Python then treats as an implicit
# PEP 420 namespace package -- `import PyIndi` succeeds (PyIndi.__file__ is
# None) but has no BaseClient attribute at all, LESSONS_LEARNED.md #1's shape.
CFLAGS="%{optflags}" %{__python3} setup.py build

%install
# Fedora's check-rpaths rejects /opt/indi-stable/lib the same way it rejects
# every other RPATH this project sets -- see indi-stable-core.spec's own
# %%install for the full explanation of why 0x0002 is downgraded to a
# warning and nothing else is: the RPATH into the private libdir IS the
# coexistence guarantee for this package's one collision risk.
export QA_RPATHS=$(( 0x0002 ))

%{__python3} setup.py install --root=%{buildroot} --skip-build

test -e %{buildroot}%{python3_sitearch}/PyIndi/_PyIndi*.so \
  || { echo "ERROR: the compiled extension is missing from the buildroot; the build produced nothing"; exit 1; }

# pyproject.toml's [project] dependencies (requests, bottle, dbus-python) are
# for upstream's examples/ scripts, which this package does not ship at all
# (packages=["PyIndi"] only in setup.py) -- confirmed by reading them, none
# of PyIndi.py/_PyIndi*.so imports any of the three. Left in place, the
# installed egg-info's requires.txt would make RPM's python dependency
# generator add all three as unwanted Requires -- same defect, same fix, as
# pyindi-client/deb/rules's override_dh_auto_install (confirmed there via
# dpkg-deb -f 2026-08-26; deleting the egg-info before the file list is
# scanned is what stops it here too).
rm -rf %{buildroot}%{python3_sitearch}/pyindi_client-*.egg-info

%files
%license LICENSE
%doc README.md
%{python3_sitearch}/PyIndi/

%changelog
* Thu Aug 27 2026 Will Snyder <william@williamlsnyder.org> - 2.2.0-1
- Initial package. Builds pyindi-client's 2.2.0 PyPI release against
  indi-stable-core, RPATH into the private prefix, installed to the ordinary
  system Python location rather than /opt/indi-stable (see header comment
  and DESIGN.md). Not yet built or installed -- see STATUS.md.
