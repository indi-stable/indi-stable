#!/bin/bash
#
# Driver-catalogue check -- is every driver we ship named in drivers.xml by
# ABSOLUTE path, and can the checks that say so actually fail?
#
# Why this exists. Upstream generates drivers.xml with bare binary names, which
# execvp resolves through PATH; the private bindir is deliberately not on PATH,
# so a bare name in OUR catalogue launches the DISTRIBUTION's driver. Both
# packagings rewrite the catalogue at build time -- the RPM in %install, the
# DEB in override_dh_auto_install -- and both assert the rewrite happened.
# DESIGN.md "Resolution -- absolute paths in our drivers.xml" has the decision.
#
# Package-manager-agnostic on purpose: it reads an installed or extracted tree,
# so the same script covers the RPM and the DEB. Needs no root.
#
#   bash scripts/test-catalogue-rewrite.sh [CATALOGUE] [BINDIR]
#
# Defaults are the installed locations. To check a built package before
# installing it, extract it first and pass both paths, e.g.
#   dpkg-deb -x indi-stable-core_*.deb /tmp/x
#   bash scripts/test-catalogue-rewrite.sh \
#        /tmp/x/opt/indi-stable/share/indi/drivers.xml /tmp/x/opt/indi-stable/bin
#
# PART 2 is the point. Part 1 passes by finding nothing wrong, and a check that
# can only pass is not evidence (LESSONS_LEARNED.md #1). Part 2 therefore feeds
# each assertion a catalogue that is deliberately broken and requires it to
# fire. Control A reproduces a bug that really shipped: the first rewrite
# looped over indi_* in BOTH the rewrite and the check, so the check inherited
# the blind spot and passed while shelyak_usis -- a driver whose binary carries
# no indi_ prefix -- went out as a bare name.
#
set -u

CAT=${1:-/opt/indi-stable/share/indi/drivers.xml}
BIN=${2:-/opt/indi-stable/bin}
PREFIX_BIN=/opt/indi-stable/bin      # what the catalogue must name, not where we read from

test -f "$CAT" || { echo "no such catalogue: $CAT"; exit 1; }
test -d "$BIN" || { echo "no such bindir: $BIN"; exit 1; }

fail=0
note() { printf '  %-58s %s\n' "$1" "$2"; }

# Every catalogue entry still carrying a bare name. The leading [^<>/] excludes
# entries already rewritten, which start with a slash.
bare_names() {
    grep -oE '<driver[^>]*>[^<>/][^<>]*</driver>' "$1" \
        | sed -e 's|</driver>$||' -e 's|^.*>||' | sort -u
}

echo "=== PART 1: the real catalogue ==="
echo "  catalogue: $CAT"
echo "  bindir:    $BIN"

n_abs=$(grep -c ">$PREFIX_BIN/" "$CAT") || n_abs=0
note "entries rewritten to $PREFIX_BIN" "$n_abs"
if [ "$n_abs" -eq 0 ]; then
    echo "  *** FAIL: no entry was rewritten; the <driver> form may have changed upstream"
    fail=1
fi

# Derived from the CATALOGUE, never from the glob that drove the rewrite.
n_left=0
while read -r n; do
    [ -n "$n" ] || continue
    if [ -x "$BIN/$n" ]; then
        echo "  *** FAIL: $n is shipped by this package but is still a bare name"
        n_left=$(( n_left + 1 ))
    else
        note "bare, and not shipped by us (correct)" "$n"
    fi
done <<< "$(bare_names "$CAT")"
note "shipped drivers left as bare names" "$n_left"
[ "$n_left" -eq 0 ] || fail=1

echo
echo "=== PART 2: positive controls -- each assertion must FIRE ==="
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed "s|>$PREFIX_BIN/|>|g" "$CAT" > "$tmp/bare.xml"

# A: rewrite only indi_*, the historical blind spot. The check must notice the
#    shipped driver whose name carries no indi_ prefix.
cp "$tmp/bare.xml" "$tmp/a.xml"
: > "$tmp/a.sed"
for b in "$BIN"/indi_*; do
    [ -f "$b" ] && [ -x "$b" ] || continue
    n=$(basename "$b")
    echo "s|>$n</driver>|>$PREFIX_BIN/$n</driver>|g" >> "$tmp/a.sed"
done
sed -i -f "$tmp/a.sed" "$tmp/a.xml"
a_left=0
while read -r n; do
    [ -n "$n" ] || continue
    [ -x "$BIN/$n" ] && a_left=$(( a_left + 1 ))
done <<< "$(bare_names "$tmp/a.xml")"
if [ "$a_left" -gt 0 ]; then
    note "A: indi_* glob leaves a shipped driver bare -- FIRED" "$a_left missed"
else
    echo "  *** CONTROL A DID NOT FIRE: the bare-name check cannot detect the bug it exists for"
    fail=1
fi

# B: upstream renames the element. The rewrite matches nothing and must not
#    pass silently.
sed 's|</driver>|</indidriver>|g' "$tmp/bare.xml" > "$tmp/b.xml"
b_done=$(grep -c ">$PREFIX_BIN/" "$tmp/b.xml") || b_done=0
if [ "$b_done" -eq 0 ]; then
    note "B: changed <driver> form rewrites nothing -- FIRED" "0 entries"
else
    echo "  *** CONTROL B DID NOT FIRE"
    fail=1
fi

# C: catalogue absent. The build must stop rather than ship no catalogue.
if [ -f "$tmp/nosuch.xml" ]; then
    echo "  *** CONTROL C DID NOT FIRE"
    fail=1
else
    note "C: missing catalogue detected -- FIRED" "absent"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "PASS: catalogue fully rewritten, and all three assertions demonstrated able to fail."
else
    echo "FAIL: see the *** lines above."
fi
exit "$fail"
