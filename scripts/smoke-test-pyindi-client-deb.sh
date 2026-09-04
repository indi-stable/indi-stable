#!/bin/bash
#
# CI smoke test (Debian/Ubuntu side) for indi-stable-pyindi-client. The twin
# of scripts/smoke-test-pyindi-client.sh: it differs only in how it installs,
# then hands off to scripts/probe-pyindi-import.sh for every actual
# assertion. Same gate shape as the other smoke tests -- fresh container, no
# baseline or coexistence checks. See smoke-test-core-deb.sh's header.
#
# Run as: sudo bash scripts/smoke-test-pyindi-client-deb.sh <deb-dir> [deb-dir ...]
#
set -u

test $# -ge 1 || { echo "usage: smoke-test-pyindi-client-deb.sh <deb-dir> [deb-dir ...]" >&2; exit 1; }
# Canonicalize before any path reaches apt-get -- a relative path is
# misparsed as apt's PACKAGE/RELEASE pin syntax. See smoke-test-core-deb.sh.
DEB_DIRS=()
for d in "$@"; do
  abs=$(cd "$d" 2>/dev/null && pwd) || { echo "ERROR: $d is not a directory" >&2; exit 1; }
  DEB_DIRS+=("$abs")
done

die() { echo; echo "*** ABORT: $* ***"; exit 1; }

echo "############ STEP 1: install core and pyindi-client ############"
echo "  searching: ${DEB_DIRS[*]}"
real_debs() { local d; for d in "${DEB_DIRS[@]}"; do ls "$d"/$1 2>/dev/null; done \
  | grep -v -e '-dev_' -e 'ddeb$'; }

CORE_DEBS=$( { real_debs 'indi-stable-core_*.deb'; real_debs 'indi-stable-core-libs_*.deb'; } | sort -u)
PY_DEBS=$(real_debs 'indi-stable-pyindi-client_*.deb' | sort -u)
test -n "$CORE_DEBS" || die "no indi-stable-core .debs in ${DEB_DIRS[*]}"
test -n "$PY_DEBS"   || die "no indi-stable-pyindi-client .deb in ${DEB_DIRS[*]}"

# Same multi-version guard as the 3rdparty gates -- see LESSONS_LEARNED.md #11.
DUPES=$(for f in $CORE_DEBS $PY_DEBS; do
          dpkg-deb -f "$f" Package Version 2>/dev/null | paste -sd' ' -
        done | sort -u | awk '{print $2}' | sort | uniq -d)
[ -z "$DUPES" ] || die "these package names appear at more than one version: $(echo $DUPES) -- pass one build only"

# shellcheck disable=SC2086
apt-get install -y $CORE_DEBS $PY_DEBS || die "install failed"
echo "  PASS: installed $(basename "$(echo "$PY_DEBS" | head -1)")"

echo "############ STEP 2: the module is genuinely usable ############"
bash "$(dirname "$0")/probe-pyindi-import.sh" /opt/indi-stable
