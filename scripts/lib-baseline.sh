#!/bin/bash
#
# Shared baseline snapshot/restore for the RPM-side root-run harnesses.
# SOURCED, never executed: `. "$(dirname "$0")/lib-baseline.sh"`.
#
# WHY THIS IS A LIBRARY AND NOT A COPIED BLOCK. Three Fedora harnesses needed
# this at once -- test-snapshot-a-depsolve.sh, test-snapshot-b-coexist.sh and
# test-upgrade-path.sh, none of which had any teardown at all. Pasting the
# same forty lines into three files is the exact shape of LESSONS_LEARNED.md
# #25 and #27: the fourth copy is the one that does not get the fix. The
# Debian harnesses each carry their own inline version, which is why the
# coexistence one still had an eight-vendor literal a day after its two
# siblings were corrected.
#
# WHAT THE DEBIAN PATTERN GETS RIGHT, and this reproduces:
#   - record the package set BEFORE, never assume it
#   - undo by DIFFING, never by a hardcoded removal list -- a depsolver pulls
#     in things no list can predict (LESSONS_LEARNED.md #6)
#   - prove the diff can see a difference before trusting its silence (#1)
#
# WHAT IT ADDS, because the Fedora harnesses need it and the Debian ones did
# not: these tests REMOVE distribution packages as part of the test.
# test-snapshot-a-depsolve.sh takes out kstars -- the package the whole
# coexistence guarantee exists to protect -- and the original had no step
# that put it back. A restore that only removes what was added is not a
# restore. This puts back what was removed as well.
#
# WHAT IT CANNOT UNDO, stated rather than hidden: a package UPGRADED in place.
# `dnf install stellarium` against live repositories upgraded eleven qt6
# packages from 6.11.1 to 6.11.2 on fedoraastro, and no amount of removing
# reverses that. Version drift is therefore reported as a WARNING with the
# packages named, not as a pass and not as a failure -- it is real, it is
# outside the test's control, and pretending either way would be worse.

# Record the package set. Two files: names decide restore, name+version
# detects in-place upgrades the name diff cannot see.
baseline_record() {   # $1 = workdir
    rpm -qa --qf '%{NAME}\n' | LC_ALL=C sort > "$1/base-names.txt"
    rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' | LC_ALL=C sort > "$1/base-nvr.txt"
    test -s "$1/base-names.txt" || { echo "*** ABORT: could not record the installed package set ***" >&2; return 1; }
    echo "  baseline recorded: $(wc -l < "$1/base-names.txt") packages"
}

# Put the box back. Returns 0 if the package set matches by name, 1 otherwise.
# Prints its own PASS/FAIL/CONTROL lines in this project's house style.
baseline_restore() {  # $1 = workdir
    local W="$1" rc=0
    echo "  ....  restoring by diffing the package set, not by naming packages"

    rpm -qa --qf '%{NAME}\n' | LC_ALL=C sort > "$W/now-names.txt"
    LC_ALL=C comm -13 "$W/base-names.txt" "$W/now-names.txt" > "$W/added.txt"
    LC_ALL=C comm -23 "$W/base-names.txt" "$W/now-names.txt" > "$W/removed.txt"

    if test -s "$W/added.txt"; then
        echo "  ....  this run added, removing: $(tr '\n' ' ' < "$W/added.txt")"
        xargs -a "$W/added.txt" -d '\n' dnf remove -y --no-autoremove \
            >"$W/restore-remove.log" 2>&1 \
            || { echo "  *** FAIL: cleanup removal failed -- box left dirty, see $W/restore-remove.log ***"; rc=1; }
    fi

    # The half test-devel-coexist.sh does not have, and the half
    # test-snapshot-a-depsolve.sh needed: put back what the run took away.
    if test -s "$W/removed.txt"; then
        echo "  ....  this run REMOVED, reinstalling: $(tr '\n' ' ' < "$W/removed.txt")"
        xargs -a "$W/removed.txt" -d '\n' dnf install -y \
            >"$W/restore-install.log" 2>&1 \
            || { echo "  *** FAIL: could not reinstall what the run removed, see $W/restore-install.log ***"; rc=1; }
    fi

    # A diff that cannot see a difference proves nothing (#1). Plant one.
    local ctl="$W/ctl-names.txt"
    { cat "$W/base-names.txt"; echo "zzz-not-a-real-package"; } | LC_ALL=C sort > "$ctl"
    if LC_ALL=C comm -13 "$W/base-names.txt" "$ctl" | grep -q 'zzz-not-a-real-package'; then
        echo "  CONTROL: the package-set diff reports a planted difference, so its silence below is a real result"
    else
        echo "  *** FAIL: the package-set diff cannot see a planted difference -- its verdict is worthless ***"
        rc=1
    fi

    rpm -qa --qf '%{NAME}\n' | LC_ALL=C sort > "$W/final-names.txt"
    if diff -u "$W/base-names.txt" "$W/final-names.txt" > "$W/names.diff"; then
        echo "  PASS: the package set matches the baseline exactly ($(wc -l < "$W/final-names.txt") packages)"
    else
        echo "  *** FAIL: the box is NOT back to its baseline: ***"
        sed 's/^/        /' "$W/names.diff"
        rc=1
    fi

    # In-place upgrades: real, unrecoverable, and reported rather than buried.
    #
    # NOT a plain `join` on the name. Six package names on a normal Fedora box
    # have MORE THAN ONE version installed at once -- kernel, kernel-core,
    # kernel-modules, kernel-modules-core, kernel-modules-extra and
    # gpg-pubkey -- and joining on the name cross-products them into a pile of
    # invented "6.19.10 -> 7.1.9" and "7.1.9 -> 6.19.10" pairs in the same
    # breath. The first version of this function did exactly that and reported
    # 12 upgrades on a run that changed nothing. Multi-version names are
    # excluded and named instead.
    rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' | LC_ALL=C sort > "$W/final-nvr.txt"
    awk -F'\t' '
        NR==FNR { n1[$1]++; v1[$1]=$2; next }
                { n2[$1]++; v2[$1]=$2 }
        END {
            for (p in v1)
                # Only names installed exactly ONCE on both sides can be
                # compared; a name with two versions has no single "before".
                if (n1[p] == 1 && n2[p] == 1 && v1[p] != v2[p])
                    print "        " p ": " v1[p] " -> " v2[p]
        }' "$W/base-nvr.txt" "$W/final-nvr.txt" | LC_ALL=C sort > "$W/drift.txt"

    if test -s "$W/drift.txt"; then
        echo "  WARNING: $(wc -l < "$W/drift.txt") package(s) were UPGRADED IN PLACE and cannot be undone by removing:"
        cat "$W/drift.txt"
        echo "        This is repository drift, not test residue. Re-baseline rather than trying to reverse it."
    else
        echo "  PASS: no package was upgraded in place during this run"
    fi

    if test -e /opt/indi-stable; then
        echo "  *** FAIL: /opt/indi-stable survived removal ***"; rc=1
    else
        echo "  PASS: /opt/indi-stable is gone"
    fi
    return $rc
}
