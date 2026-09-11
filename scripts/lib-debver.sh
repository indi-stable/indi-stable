#!/bin/bash
#
# Shared version derivation for the Debian-side harnesses.
# SOURCED, never executed: `. "$(dirname "$0")/lib-debver.sh"`.
#
# WHY THIS EXISTS. Three harnesses -- test-3rdparty-coexist-deb.sh,
# test-upgrade-path-3rdparty-deb.sh and test-upgrade-path-drivers-deb.sh --
# defaulted their version arguments to the literal `2.2.4.1-1`. That version
# stopped existing when the 2026-09-09 release moved this repo to `-2`, so
# every one of them aborted on a current build until the caller passed
# LIBS_VER/DRIVERS_VER/OLD_VER/NEW_VER by hand. Loud rather than wrong, but a
# default that can never be right again is a papercut that recurs every
# session, and it will recur again at `-3`.
#
# WHY A LIBRARY AND NOT THREE PASTED COPIES. lib-baseline.sh's own header
# already names this: the Debian harnesses each carrying their own inline
# version is why the coexistence one still had an eight-vendor literal a day
# after its two siblings were fixed (LESSONS_LEARNED.md #25 and #27). Three
# call sites at once is the shape that produces a fourth copy nobody updates.
#
# WHAT IT DOES NOT DO: guess. Where more than one version of a package is
# present in a directory it ABORTS and names the variable to set, rather than
# picking the highest. `~/build` routinely holds several revisions at once --
# a real release alongside an uncommitted `-2`/`-3` scratch build made for
# the upgrade harnesses -- and silently choosing between them is how a test
# ends up measuring the scratch build it was meant to upgrade FROM. The same
# refusal smoke-test-pyindi-client-deb.sh already makes ("pass one build
# only"), for the same reason.

# derive_deb_version <dir> <exact-package-name> <env-var-name>
#
# Echo the one version of <exact-package-name> present as a .deb in <dir>.
# The trailing underscore in the glob anchors the name, so `-dev` and
# `-dbgsym` siblings never match and cannot be mistaken for a version.
derive_deb_version() {
    local dir=$1 pkg=$2 var=$3
    local found vers n

    found=$(ls "$dir/${pkg}"_*_*.deb 2>/dev/null)
    if [ -z "$found" ]; then
        echo "*** ABORT: no ${pkg}_*.deb in $dir -- build it first (DEBIAN.md), or set $var explicitly ***" >&2
        return 1
    fi

    vers=$(printf '%s\n' "$found" \
           | sed -e 's|.*/||' -e "s|^${pkg}_||" -e 's|_[^_]*\.deb$||' \
           | sort -u)
    n=$(printf '%s\n' "$vers" | wc -l)
    if [ "$n" -ne 1 ]; then
        echo "*** ABORT: $dir holds $n versions of $pkg ($(printf '%s ' $vers)) -- set $var explicitly to choose ***" >&2
        return 1
    fi

    printf '%s\n' "$vers"
}
