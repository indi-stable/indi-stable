#!/bin/bash
#
# CI smoke test (RPM/Fedora side) for indi-stable-pyindi-client: clean
# install into a fresh container, then hand off to
# scripts/probe-pyindi-import.sh for every actual assertion. Same gate shape
# as smoke-test-core.sh and smoke-test-3rdparty.sh -- no baseline or
# coexistence checks here, because this only ever runs in a just-started
# container. See smoke-test-core.sh's header.
#
# Run as: bash scripts/smoke-test-pyindi-client.sh <rpm-dir> [rpm-dir ...]
#
set -u

test $# -ge 1 || { echo "usage: smoke-test-pyindi-client.sh <rpm-dir> [rpm-dir ...]" >&2; exit 1; }
RPM_DIRS=()
for d in "$@"; do
  abs=$(cd "$d" 2>/dev/null && pwd) || { echo "ERROR: $d is not a directory" >&2; exit 1; }
  RPM_DIRS+=("$abs")
done

die() { echo; echo "*** ABORT: $* ***"; exit 1; }

echo "############ STEP 1: install core and pyindi-client ############"
echo "  searching: ${RPM_DIRS[*]}"
real_rpms() { local d; for d in "${RPM_DIRS[@]}"; do ls "$d"/$1 2>/dev/null; done \
  | grep -v -e debuginfo -e debugsource -e '-devel-'; }

CORE_RPMS=$( { real_rpms 'indi-stable-core-2*.x86_64.rpm'; real_rpms 'indi-stable-core-libs-2*.x86_64.rpm'; } | sort -u)
PY_RPMS=$(real_rpms 'indi-stable-pyindi-client-*.x86_64.rpm' | sort -u)
test -n "$CORE_RPMS" || die "no indi-stable-core RPMs in ${RPM_DIRS[*]}"
test -n "$PY_RPMS"   || die "no indi-stable-pyindi-client RPM in ${RPM_DIRS[*]}"

# Same multi-version guard as the 3rdparty gates: a directory holding two
# builds of one package lets the package manager pick, and it picks by
# version, which is not the same as picking the one you meant to test
# (LESSONS_LEARNED.md #11).
DUPES=$(for f in $CORE_RPMS $PY_RPMS; do rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE}\n' "$f" 2>/dev/null; done \
        | sort -u | awk '{print $1}' | sort | uniq -d)
[ -z "$DUPES" ] || die "these package names appear at more than one version: $(echo $DUPES) -- pass one build only"

# shellcheck disable=SC2086
dnf install -y $CORE_RPMS $PY_RPMS || die "install failed"
echo "  PASS: installed $(basename $(echo "$PY_RPMS" | head -1))"

echo "############ STEP 2: the module is genuinely usable ############"
bash "$(dirname "$0")/probe-pyindi-import.sh" /opt/indi-stable
