#!/bin/bash
#
# The distro-independent half of the pyindi-client smoke test: given an
# ALREADY-INSTALLED indi-stable-pyindi-client, decide whether the module is
# genuinely usable. Called by scripts/smoke-test-pyindi-client.sh and
# -deb.sh, which differ only in how they install; split out for the same
# reason scripts/probe-devel-compile-deb.sh is split from its driver -- the
# measuring half is worth having on its own, and duplicating it across two
# distros is how the two copies drift.
#
# Run as: bash scripts/probe-pyindi-import.sh [expected-lib-prefix]
#
# Exits non-zero if any check fails. Prints PASS/FAIL lines.
#
set -u

PREFIX=${1:-/opt/indi-stable}
FAIL=0
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

command -v python3 >/dev/null 2>&1 || { echo "*** ABORT: python3 not found ***"; exit 1; }

echo "--- check 1: the module imports and is a REAL module ---"
# PyIndi.__file__ being None is not a curiosity: a failed build leaves an
# importable namespace-package shell with no BaseClient in it, so
# `import PyIndi` succeeds and means nothing. Caught by hand on the Debian
# side before the first real dpkg-buildpackage (DEBIAN.md), which is why it
# is asserted rather than assumed.
OUT=$(python3 -c '
import sys
try:
    import PyIndi
except Exception as e:
    print("IMPORT-FAILED", type(e).__name__, e); sys.exit(1)
print("FILE", PyIndi.__file__)
' 2>&1)
echo "$OUT" | sed 's/^/      /'
case "$OUT" in
  IMPORT-FAILED*) fail "import PyIndi raised" ;;
  "FILE None")    fail "PyIndi.__file__ is None -- this is the namespace-package shell, not the built module" ;;
  FILE*)          pass "import PyIndi, __file__ is a real path" ;;
  *)              fail "unrecognized probe output" ;;
esac

echo "--- check 2: BaseClient instantiates ---"
if python3 -c 'import PyIndi; PyIndi.BaseClient()' 2>/dev/null; then
  pass "PyIndi.BaseClient() constructed"
else
  fail "PyIndi.BaseClient() failed -- the wrapper imported but the class is unusable"
fi

echo "--- check 3: every symbol the SWIG wrapper calls is actually exported ---"
# This exists because of a real, logged incident (DESIGN.md, "Evidence,
# 2026-09-03"): on ACS's NUC, two `pip install pyindi-client==2.2.0` runs
# against IDENTICAL unchanged headers produced different results, and the bad
# one gave a PyIndi.py calling _PyIndi.BaseDevice___nonzero__ while the
# compiled extension exported no such symbol. pip reported success. Every
# newDevice/newProperty callback then raised AttributeError inside libindi's
# own C++ callback thread, where nothing surfaces it -- it presented as a
# generic connection timeout.
#
# Checks 1 and 2 above would BOTH have passed on that broken build. This is
# the one that would not.
OUT=$(python3 -c '
import re, sys, os, importlib, PyIndi

# The extension may be a submodule of a PyIndi PACKAGE or a top-level module,
# depending on how upstream laid the release out. This build is the former:
# PyIndi/__init__.py does "from .PyIndi import *", the SWIG wrapper is
# PyIndi/PyIndi.py, and the extension is PyIndi/_PyIndi.<abi>.so. Reading
# PyIndi.__file__ alone finds only the 369-byte __init__.py and no
# references at all -- which is exactly what happened the first time this
# probe ran, 2026-09-04.
ext = None
for name in ("PyIndi._PyIndi", "_PyIndi"):
    try:
        ext = importlib.import_module(name); break
    except ImportError:
        pass
if ext is None:
    print("NO-EXTENSION"); sys.exit(1)
print("EXTENSION", ext.__file__)

# Scan every .py in the package, not just __file__, so both layouts work.
f = PyIndi.__file__
srcs = ([os.path.join(os.path.dirname(f), n) for n in os.listdir(os.path.dirname(f)) if n.endswith(".py")]
        if os.path.basename(f) == "__init__.py" else [f])
names = set()
for s in srcs:
    names |= set(re.findall(r"_PyIndi\.([A-Za-z_][A-Za-z0-9_]*)", open(s, encoding="utf-8", errors="replace").read()))
names = sorted(names)
missing = [n for n in names if not hasattr(ext, n)]
print("REFERENCED", len(names))
print("MISSING", len(missing))
for n in missing[:15]:
    print("  missing:", n)
sys.exit(1 if missing else 0)
' 2>&1)
echo "$OUT" | sed 's/^/      /'
REFCOUNT=$(echo "$OUT" | awk '/^REFERENCED/{print $2}')
# A zero-reference result would make this check pass by finding nothing --
# the exact shape LESSONS_LEARNED.md #1 warns about. If the wrapper stops
# looking like a SWIG wrapper, that is a finding, not a pass.
if [ -z "${REFCOUNT:-}" ] || [ "$REFCOUNT" -lt 50 ] 2>/dev/null; then
  fail "only ${REFCOUNT:-0} _PyIndi.* references found in the wrapper -- too few to be a real SWIG binding, so this check would pass vacuously"
elif echo "$OUT" | grep -q '^MISSING 0$'; then
  pass "all $REFCOUNT symbols referenced by PyIndi.py exist in _PyIndi"
else
  fail "the SWIG wrapper calls symbols the compiled extension does not export -- this is the 2026-09-03 failure mode"
fi

echo "--- check 4: the extension links against OUR libindiclient, not the distro's ---"
SO=$(python3 -c '
import importlib
for n in ("PyIndi._PyIndi", "_PyIndi"):
    try:
        print(importlib.import_module(n).__file__); break
    except ImportError:
        pass
' 2>/dev/null)
if [ -z "$SO" ] || [ ! -f "$SO" ]; then
  fail "could not locate the compiled _PyIndi extension"
else
  echo "      $SO"
  LDD=$(ldd "$SO" 2>&1)
  echo "$LDD" | grep -E 'libindi' | sed 's/^/      /'
  if echo "$LDD" | grep -q 'not found'; then
    fail "unresolved libraries in the extension"
  elif echo "$LDD" | grep -E 'libindi[A-Za-z]*\.so' | grep -qv "=> *${PREFIX}/"; then
    fail "an libindi* library resolved OUTSIDE ${PREFIX} -- the private-prefix RPATH is not winning"
  elif echo "$LDD" | grep -qE "libindiclient\.so.*=> *${PREFIX}/"; then
    pass "libindiclient.so resolves into ${PREFIX}"
  else
    fail "libindiclient.so was not resolved at all -- unexpected linkage"
  fi
fi

echo
[ $FAIL -eq 0 ] && echo "  PROBE: all checks passed" || echo "  PROBE: one or more checks FAILED"
exit $FAIL
