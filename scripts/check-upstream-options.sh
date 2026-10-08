#!/bin/bash
#
# Fail when upstream indi-3rdparty's set of top-level build options changes
# under us, so that a change of scope becomes a decision instead of a default.
#
# THE HAZARD THIS CLOSES. core/rpm/indi-stable-3rdparty-drivers.spec and
# core/deb-3rdparty-drivers/rules both configure upstream by turning things
# OFF: a list of -DWITH_<X>=OFF for everything out of scope, and whatever is
# left builds. That makes our scope a DENY-list, so anything upstream adds
# with a default of On is packaged automatically, with no decision from us.
#
# WITH_SCOPELINK is the case that proved it. New in v2.2.5, default On, out of
# scope -- and it was built, packaged, and caught only because indi-scopelink
# happens to ship a udev rule and both %install and override_dh_auto_install
# assert an exact rule count. A driver that shipped no udev rule would have
# been published to users as part of indi-stable with nobody choosing it.
# That assertion caught this by luck, not by design; this script is the
# by-design version.
#
# WHY IT SNAPSHOTS UPSTREAM AND NOT OUR RULINGS. The deny-list already exists,
# twice, in the spec and the Debian rules. Recording it a third time here
# would be a third copy to drift, which is the thing this repo's documents
# rule exists to prevent. So core/3rdparty-upstream-options.txt holds ONLY
# what upstream declares -- each option and its default -- and every ruling
# below is DERIVED by reading the real packaging. A consequence worth having:
# snapshotting the default too catches an option whose default FLIPS from Off
# to On, which the deny-list alone cannot see, because no OFF entry names an
# option that was previously off for free.
#
# WHAT FAILS THE CHECK
#   - an option upstream declares that the snapshot does not list        (NEW)
#   - an option the snapshot lists that upstream no longer declares     (GONE)
#   - an option whose default changed                                (CHANGED)
#   - the spec's OFF list and the Debian rules' OFF list disagreeing
# The first three are each resolved the same way: rule on the option (add a
# -DWITH_<X>=OFF to BOTH packagings, or decide to package it), then re-run
# with --regenerate to record the new surface. Do not regenerate first; the
# snapshot is the record of what was decided, so updating it before deciding
# is how this check becomes decoration.
#
# WHY IT PARSES RATHER THAN GREPS, which was the first attempt and was wrong:
# `option(WITH_LIBCAMERA "Install Libcamera Driver (Raspberry PI)" Off)` has a
# close paren inside its description, so a regex stopping at the first ')'
# loses the default that follows and misreads the option as having none. That
# option is default Off and correctly absent from our deny-list, so a parser
# that mangles it would classify it wrongly and quietly. The control at the
# bottom plants exactly that shape and fails the script if it is misread, so
# this cannot regress to the grep version.
#
# Read-only unless --regenerate is passed. Needs no root, builds nothing.
#
# Run as: bash scripts/check-upstream-options.sh <upstream-tag>
#         bash scripts/check-upstream-options.sh --file <CMakeLists.txt>
#         bash scripts/check-upstream-options.sh <upstream-tag> --regenerate
#   e.g.  bash scripts/check-upstream-options.sh v2.2.5
#         bash scripts/check-upstream-options.sh --file ~/build/v225-libs/CMakeLists.txt
#
# Fetches ONLY the top-level CMakeLists.txt from the tag (a few kB), not the
# 300 MB source tarball -- every option the deny-list names is declared there.
# Confirmed, not assumed: all 28 of our OFF entries resolve against that one
# file, which the "dead entry" report below would flag if one ever did not.
#
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SNAPSHOT="${SNAPSHOT:-$REPO_ROOT/core/3rdparty-upstream-options.txt}"
SPEC="${SPEC:-$REPO_ROOT/core/rpm/indi-stable-3rdparty-drivers.spec}"
RULES="${RULES:-$REPO_ROOT/core/deb-3rdparty-drivers/rules}"
SKIP_CONTROLS="${SKIP_CONTROLS:-0}"

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required" >&2; exit 1; }

REGEN=0
MODE=""
ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --regenerate) REGEN=1 ;;
    --file)       MODE=file; shift; ARG=${1:?--file needs a path} ;;
    -h|--help)    sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    *)            MODE=tag; ARG="$1" ;;
  esac
  shift
done
[ -n "$MODE" ] || { echo "usage: check-upstream-options.sh <upstream-tag> | --file <CMakeLists.txt> [--regenerate]" >&2; exit 1; }

# ------------------------------------------------------------------ parser
# Quote-aware walk to the MATCHING close paren. See the header for why a
# regex to the first ')' is not good enough.
PARSE_PY=$(cat <<'PYEOF'
import re, sys

def parse(text):
    out = []
    for m in re.finditer(r'\boption\s*\(', text):
        i = m.end()
        depth, inq, tok, toks = 1, False, '', []
        while i < len(text) and depth:
            c = text[i]
            if inq:
                if c == '"':
                    inq = False
                    toks.append(tok); tok = ''
                else:
                    tok += c
            elif c == '"':
                inq = True
                if tok: toks.append(tok); tok = ''
            elif c == '(':
                depth += 1; tok += c
            elif c == ')':
                depth -= 1
                if depth == 0:
                    if tok.strip(): toks.append(tok.strip())
                else:
                    tok += c
            elif c.isspace():
                if tok.strip(): toks.append(tok.strip())
                tok = ''
            else:
                tok += c
            i += 1
        toks = [t for t in toks if t != '']
        if len(toks) < 2 or not toks[0].startswith('WITH_'):
            continue
        out.append((toks[0], toks[-1].strip().upper()))
    return out

src = open(sys.argv[1], encoding='utf-8', errors='replace').read()

# An option declared more than once with DIFFERENT defaults is not a
# redeclaration to resolve -- upstream puts the two in mutually exclusive
# if/else branches, so the default depends on whether a dependency is
# present ON THE BUILD HOST. WITH_WEBCAM is On when FFmpeg is found and Off
# when it is not; WITH_NUT the same with NUTClient. Picking one branch would
# record a default no builder necessarily has, and would hide the real
# hazard: such an option can arrive On, so it needs a deny-list entry just
# as a plain default-On one does. Recorded as CONDITIONAL and treated as
# in-scope-by-default below.
seen = {}
for name, dflt in parse(src):
    seen.setdefault(name, set()).add(dflt)
for name in sorted(seen):
    d = seen[name]
    print(name, d.pop() if len(d) == 1 else 'CONDITIONAL')
PYEOF
)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fetch_cmakelists() {   # $1 = tag, $2 = destination
  local url="https://raw.githubusercontent.com/indilib/indi-3rdparty/$1/CMakeLists.txt"
  curl -fsSL -o "$2" "$url" \
    || { echo "ERROR: could not fetch $url" >&2; return 1; }
  # An HTML error page is a 200 on some proxies; a CMakeLists without a
  # single option() in it means we parsed the wrong thing, not that upstream
  # removed them all, and would report all 77 as GONE.
  grep -q 'option(' "$2" \
    || { echo "ERROR: $url has no option() lines -- fetched the wrong content" >&2; return 1; }
}

case "$MODE" in
  tag)
    echo "upstream tag:    $ARG" >&2
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required to check a tag" >&2; exit 1; }
    fetch_cmakelists "$ARG" "$WORK/CMakeLists.txt" || exit 1
    CML="$WORK/CMakeLists.txt"
    ;;
  file)
    test -f "$ARG" || { echo "ERROR: $ARG not found" >&2; exit 1; }
    echo "upstream source: $ARG" >&2
    CML="$ARG"
    ;;
esac

python3 -c "$PARSE_PY" "$CML" > "$WORK/upstream.txt"
UP_N=$(wc -l < "$WORK/upstream.txt")
[ "$UP_N" -gt 0 ] || { echo "ERROR: parsed zero WITH_ options from $CML" >&2; exit 1; }

# ------------------------------------------------------- our own deny-list
off_list() {   # $1 = file to read -DWITH_<X>=OFF out of
  grep -oE '\-DWITH_[A-Za-z0-9_-]+=OFF' "$1" | sed 's/^-D//; s/=OFF$//' | LC_ALL=C sort -u
}
test -f "$SPEC"  || { echo "ERROR: $SPEC not found" >&2; exit 1; }
test -f "$RULES" || { echo "ERROR: $RULES not found" >&2; exit 1; }
off_list "$SPEC"  > "$WORK/off-rpm.txt"
off_list "$RULES" > "$WORK/off-deb.txt"

if [ "$REGEN" -eq 1 ]; then
  {
    echo "# Upstream indilib/indi-3rdparty top-level build options, and their"
    echo "# DEFAULTS, as last ruled on by this project. Generated by"
    echo "# scripts/check-upstream-options.sh --regenerate; see that script's"
    echo "# header for why this records upstream's surface and not our rulings,"
    echo "# and why regenerating BEFORE deciding defeats the check."
    echo "#"
    echo "# source: ${MODE}=${ARG}"
    echo ""
    cat "$WORK/upstream.txt"
  } > "$SNAPSHOT"
  echo "wrote $SNAPSHOT ($UP_N options)" >&2
  echo "REGENERATED"
  exit 0
fi

test -f "$SNAPSHOT" || { echo "ERROR: $SNAPSHOT not found -- create it with --regenerate once, after ruling on the current option set" >&2; exit 1; }
grep -vE '^\s*(#|$)' "$SNAPSHOT" | LC_ALL=C sort > "$WORK/snapshot.txt"
SNAP_N=$(wc -l < "$WORK/snapshot.txt")

echo "############ upstream option surface: $UP_N declared, $SNAP_N recorded ############"
FAIL=0
fail() { echo "  *** FAIL: $* ***"; FAIL=1; }
pass() { echo "  PASS: $*"; }

# ------------------------------------------------------------------- CHECK 1
echo
echo "--- CHECK 1: the recorded surface still matches upstream ---"
awk '{print $1}' "$WORK/upstream.txt" | LC_ALL=C sort > "$WORK/up-names.txt"
awk '{print $1}' "$WORK/snapshot.txt" | LC_ALL=C sort > "$WORK/snap-names.txt"

NEW=$(LC_ALL=C comm -23 "$WORK/up-names.txt" "$WORK/snap-names.txt")
GONE=$(LC_ALL=C comm -13 "$WORK/up-names.txt" "$WORK/snap-names.txt")

if [ -n "$NEW" ]; then
  for o in $NEW; do
    d=$(awk -v o="$o" '$1==o {print $2}' "$WORK/upstream.txt")
    if [ "$d" = "ON" ] || [ "$d" = "CONDITIONAL" ]; then
      fail "NEW option $o, default $d -- IN SCOPE BY DEFAULT and never ruled on"
      echo "         It will be built and packaged. Add -DWITH_${o#WITH_}=OFF to BOTH"
      echo "         $SPEC"
      echo "         $RULES"
      echo "         or decide deliberately to package it. Then --regenerate."
    else
      fail "NEW option $o, default $d -- not built, but record the decision"
      echo "         Default-off needs no deny-list entry. Re-run with --regenerate."
    fi
  done
else
  pass "no option upstream declares is missing from the record"
fi

if [ -n "$GONE" ]; then
  for o in $GONE; do
    fail "GONE: $o is recorded but upstream no longer declares it"
    if LC_ALL=C grep -qx "$o" "$WORK/off-rpm.txt"; then
      echo "         Our deny-list still names it, so that entry is now dead."
      echo "         Remove it from both packagings, then --regenerate."
    else
      echo "         Nothing in our deny-list names it. Re-run with --regenerate."
    fi
  done
else
  pass "every recorded option is still declared upstream"
fi

CHANGED=0
while read -r name dflt; do
  snap=$(awk -v o="$name" '$1==o {print $2}' "$WORK/snapshot.txt")
  [ -n "$snap" ] || continue
  if [ "$snap" != "$dflt" ]; then
    CHANGED=1
    fail "CHANGED: $name default went $snap -> $dflt"
    if [ "$dflt" != "OFF" ] && ! LC_ALL=C grep -qx "$name" "$WORK/off-rpm.txt"; then
      echo "         It is now in scope by default and nothing excludes it."
    fi
  fi
done < "$WORK/upstream.txt"
[ "$CHANGED" -eq 0 ] && pass "no recorded option changed its default"

# ------------------------------------------------------------------- CHECK 2
echo
echo "--- CHECK 2: the two packagings' deny-lists agree ---"
if LC_ALL=C diff -q "$WORK/off-rpm.txt" "$WORK/off-deb.txt" >/dev/null; then
  pass "$(wc -l < "$WORK/off-rpm.txt") OFF entries, identical in the spec and the Debian rules"
else
  fail "the spec and the Debian rules exclude different options"
  LC_ALL=C diff "$WORK/off-rpm.txt" "$WORK/off-deb.txt" | sed 's/^/         /'
fi

# ------------------------------------------------------------------- CHECK 3
# Dead entries are not a scope error, but they are how the list rots: an OFF
# for an option upstream dropped reads as a deliberate exclusion forever.
echo
echo "--- CHECK 3: no deny-list entry names an option upstream does not declare ---"
DEAD=$(LC_ALL=C comm -13 "$WORK/up-names.txt" "$WORK/off-rpm.txt")
if [ -n "$DEAD" ]; then
  for o in $DEAD; do fail "dead entry: -D${o}=OFF excludes an option upstream does not declare"; done
else
  pass "every OFF entry resolves against upstream's own option list"
fi

# ------------------------------------------------------------- what we ship
echo
echo "--- derived scope (read from the packaging, not recorded anywhere) ---"
PACKAGED=0; EXCLUDED=0; UPOFF=0; REDUNDANT=0; COND=0
while read -r name dflt; do
  in_off=0
  LC_ALL=C grep -qx "$name" "$WORK/off-rpm.txt" && in_off=1
  if [ "$dflt" = "CONDITIONAL" ]; then
    COND=$((COND+1))
    # Not excluded and host-dependent means the package SET depends on the
    # builder, which is a scope that moves without anyone editing anything.
    if [ "$in_off" -eq 0 ]; then
      fail "$name's default depends on a build-host dependency and nothing excludes it"
      echo "         Whether it is packaged then varies by builder. Rule on it explicitly."
    fi
  elif [ "$dflt" = "ON" ] && [ "$in_off" -eq 1 ]; then EXCLUDED=$((EXCLUDED+1))
  elif [ "$dflt" = "ON" ];                          then PACKAGED=$((PACKAGED+1))
  elif [ "$in_off" -eq 1 ];                         then REDUNDANT=$((REDUNDANT+1))
  else                                                   UPOFF=$((UPOFF+1))
  fi
done < "$WORK/upstream.txt"
printf '  default On, we exclude:            %3d\n' "$EXCLUDED"
printf '  default On, we package:            %3d\n' "$PACKAGED"
printf '  default Off upstream, not built:   %3d\n' "$UPOFF"
printf '  default Off and in our OFF list:   %3d  (harmless, kept against a future flip)\n' "$REDUNDANT"
printf '  conditional on a host dependency:  %3d  (all excluded, or CHECK above fails)\n' "$COND"

# ---------------------------------------------------------------- CONTROL
# A check that passes by parsing nothing is worthless -- LESSONS_LEARNED.md
# #1. Each control plants one fault and requires it to be reported, and the
# last one requires a CLEAN input to stay clean, because a check that flags
# everything is no better than one that flags nothing.
if [ "$SKIP_CONTROLS" = "1" ]; then
  echo
  echo "--- CONTROLS SKIPPED (SKIP_CONTROLS=1) ---"
else
echo
echo "--- CONTROLS: plant a fault of each kind and require it to be found ---"
CTL="$WORK/ctl"; mkdir -p "$CTL"

# A snapshot and a deny-list of our own, so the controls do not depend on
# the real ones and cannot be broken by a legitimate scope change.
cat > "$CTL/snapshot.txt" <<'CTLEOF'
WITH_KEPT ON
WITH_SHIPPED ON
WITH_SLEEPER OFF
WITH_RETIRED ON
CTLEOF
cat > "$CTL/spec" <<'CTLEOF'
    -DWITH_KEPT=OFF \
    -DWITH_RETIRED=OFF \
CTLEOF
cp "$CTL/spec" "$CTL/rules"

ctl_run() {   # $1 = CMakeLists to parse; prints the script's own output
  SNAPSHOT="$CTL/snapshot.txt" SPEC="$CTL/spec" RULES="$CTL/rules" \
    SKIP_CONTROLS=1 bash "$0" --file "$1" 2>&1
}

# 1. A new default-On option: the WITH_SCOPELINK shape.
cat > "$CTL/new-on.txt" <<'CTLEOF'
option(WITH_KEPT "kept" On)
option(WITH_SHIPPED "shipped" On)
option(WITH_SLEEPER "sleeper" Off)
option(WITH_RETIRED "retired" On)
option(WITH_INTRUDER "brand new, default on" On)
CTLEOF
out=$(ctl_run "$CTL/new-on.txt") || true
if ! grep -q "NEW option WITH_INTRUDER, default ON -- IN SCOPE BY DEFAULT" <<<"$out"; then
  echo "$out"; echo "CONTROL FAILED: a new default-On option was NOT reported." >&2
  echo "  This is the WITH_SCOPELINK case. The script cannot be trusted." >&2; exit 1
fi
echo "  CONTROL: new default-On option reported as in-scope-by-default"

# 2. The parenthesis-in-description case, which the first attempt got wrong.
cat > "$CTL/paren.txt" <<'CTLEOF'
option(WITH_KEPT "kept" On)
option(WITH_SHIPPED "shipped" On)
option(WITH_RETIRED "retired" On)
option(WITH_SLEEPER "Install Something (Raspberry PI)" Off)
CTLEOF
out=$(ctl_run "$CTL/paren.txt") || true
if grep -qE "CHANGED: WITH_SLEEPER|NEW option WITH_SLEEPER" <<<"$out"; then
  echo "$out"
  echo "CONTROL FAILED: an option whose description contains ')' was misread." >&2
  echo "  The parser has regressed to stopping at the first close paren." >&2; exit 1
fi
echo "  CONTROL: default read correctly past a ')' inside the description"

# 3. A default flipped Off -> On, which the deny-list alone cannot see.
cat > "$CTL/flip.txt" <<'CTLEOF'
option(WITH_KEPT "kept" On)
option(WITH_SHIPPED "shipped" On)
option(WITH_RETIRED "retired" On)
option(WITH_SLEEPER "sleeper, now on" On)
CTLEOF
out=$(ctl_run "$CTL/flip.txt") || true
if ! grep -q "CHANGED: WITH_SLEEPER default went OFF -> ON" <<<"$out"; then
  echo "$out"; echo "CONTROL FAILED: a default flipped Off->On was NOT reported." >&2; exit 1
fi
if ! grep -q "now in scope by default and nothing excludes it" <<<"$out"; then
  echo "$out"; echo "CONTROL FAILED: the flip was reported without naming its consequence." >&2; exit 1
fi
echo "  CONTROL: default flipped Off->On reported, with its consequence named"

# 4. An option upstream dropped, leaving a dead deny-list entry.
cat > "$CTL/gone.txt" <<'CTLEOF'
option(WITH_KEPT "kept" On)
option(WITH_SHIPPED "shipped" On)
option(WITH_SLEEPER "sleeper" Off)
CTLEOF
out=$(ctl_run "$CTL/gone.txt") || true
if ! grep -q "GONE: WITH_RETIRED is recorded but upstream no longer declares it" <<<"$out"; then
  echo "$out"; echo "CONTROL FAILED: a withdrawn option was NOT reported." >&2; exit 1
fi
if ! grep -q "that entry is now dead" <<<"$out"; then
  echo "$out"; echo "CONTROL FAILED: the withdrawal did not name the dead deny-list entry." >&2; exit 1
fi
echo "  CONTROL: withdrawn option reported, and its dead OFF entry named"

# 5. Disagreeing deny-lists.
cat > "$CTL/rules" <<'CTLEOF'
    -DWITH_KEPT=OFF \
CTLEOF
out=$(ctl_run "$CTL/new-on.txt") || true
if ! grep -q "the spec and the Debian rules exclude different options" <<<"$out"; then
  echo "$out"; echo "CONTROL FAILED: divergent deny-lists were NOT reported." >&2; exit 1
fi
echo "  CONTROL: spec and Debian rules disagreeing is reported"
cp "$CTL/spec" "$CTL/rules"

# 6. NEGATIVE control: an unchanged surface must come back clean.
cat > "$CTL/clean.txt" <<'CTLEOF'
option(WITH_KEPT "kept" On)
option(WITH_SHIPPED "shipped" On)
option(WITH_SLEEPER "sleeper" Off)
option(WITH_RETIRED "retired" On)
CTLEOF
if ! out=$(ctl_run "$CTL/clean.txt"); then
  echo "$out"; echo "CONTROL FAILED: an UNCHANGED option surface was reported as a failure." >&2
  echo "  A check that flags everything is as useless as one that flags nothing." >&2; exit 1
fi
if grep -q "FAIL" <<<"$out"; then
  echo "$out"; echo "CONTROL FAILED: clean input produced a FAIL line." >&2; exit 1
fi
echo "  CONTROL: an unchanged surface is NOT flagged"
fi

echo
echo "==================================================================="
if [ "$FAIL" -ne 0 ]; then
  echo "UPSTREAM OPTION SURFACE CHANGED -- rule on the options above, then"
  echo "re-run with --regenerate. Do not regenerate first."
  echo "==================================================================="
  exit 1
fi
echo "UPSTREAM OPTIONS: surface unchanged, both deny-lists agree, controls fired."
echo "==================================================================="
exit 0
