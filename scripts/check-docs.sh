#!/bin/bash
#
# Mechanical staleness checks for the .md files. Needs no root, no network, and
# touches nothing -- read-only over the repo.
#
# WHAT THIS IS FOR
#
# Six stale claims were found by hand on 2026-08-26, and the pattern across all
# of them was the same: each was TRUE when written, and was falsified later by a
# commit that had no reason to touch that file. Five of the six sat in a
# different file from the change that invalidated them. So this is not a
# one-off tidy-up -- it is a recurring failure mode, and the mechanically
# checkable part of it belongs in a script rather than in someone's memory.
#
# WHAT IT DELIBERATELY DOES NOT CHECK
#
# Only claims with a filesystem answer. "The Debian packaging has not been built
# yet" is stale prose that no script can catch, and pretending otherwise would
# produce a check that passes while the interesting staleness walks by
# (LESSONS_LEARNED.md #15). The three checks here are:
#
#   A  every repo path named in a doc exists
#   B  no two claims give one path different sha256s within a section
#   C  every cross-reference resolves -- file, quoted section, and
#      LESSONS_LEARNED.md #N by number
#
# EVERY CHECK CARRIES A POSITIVE CONTROL. Each one passes by finding nothing,
# which is the single highest-value trap in this project (LESSONS_LEARNED.md
# #1), so each is re-run against a copy of the docs with a fault planted in it
# and must report that fault. If a control does not fire, the check is broken
# and this script fails even though the docs may be fine.
#
# Run as: bash scripts/check-docs.sh [--quiet]
#
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
QUIET=0
test "${1:-}" = "--quiet" && QUIET=1

FAIL=0
fail() { echo "  *** STALE: $* ***"; FAIL=1; }
pass() { test "$QUIET" -eq 1 || echo "  PASS: $*"; }
ctl()  { test "$QUIET" -eq 1 || echo "  CONTROL: $*"; }
info() { test "$QUIET" -eq 1 || echo "  ....  $*"; }

# Normalise a section title for comparison: strip backticks, fold em-dash and
# "--" to "-", lowercase, squeeze whitespace. Without this, a reference written
# in a shell comment as "Resolution -- absolute paths in our drivers.xml"
# never matches the heading "Resolution — absolute paths in our `drivers.xml`",
# and a first pass at this by hand produced exactly two such false alarms.
norm() { sed -e 's/`//g' -e 's/—/-/g' -e 's/--/-/g' | tr '[:upper:]' '[:lower:]' | tr -s ' \t' '  ' | sed -e 's/^ //' -e 's/ $//'; }

# ---------------------------------------------------------------- CHECK A ----
# Repo-relative file paths named in the docs. Anchored on a known top-level
# directory AND on the final component containing a dot, so that bare directory
# mentions (core/deb, 3rdparty/) are not treated as missing files -- those are
# legitimately absent while marked "not started", and flagging them would make
# this script cry wolf on its first run.
check_paths() {   # $1 = directory holding the .md files, $2 = repo root to resolve against
  local docdir=$1 root=$2 p found=0
  for p in $(grep -ohE '(scripts|core)/[A-Za-z0-9._/-]+' "$docdir"/*.md 2>/dev/null \
             | grep -E '/[^/]*\.[A-Za-z0-9]+$' | sort -u); do
    if ! test -e "$root/$p"; then echo "$p"; found=1; fi
  done
  # Bare `<name>.sh` mentions carrying no scripts/ prefix, resolved against
  # scripts/. Added 2026-09-04: the prefixed form above is structurally blind
  # to these, and a real dangling reference proved it -- renaming
  # check-upstream-core.sh to check-upstream-tag.sh left STATUS.md naming the
  # deleted file, and CHECK A passed anyway. The docs refer to harnesses by
  # bare name routinely, so this is the common shape, not an edge case.
  #
  # The leading [A-Za-z0-9] is load-bearing, not cosmetic: DESIGN.md writes
  # the pair of smoke tests as "scripts/smoke-test-core.sh / `-core-deb.sh`",
  # a continuation shorthand whose second half is not a filename at all.
  # Surveyed before writing this (2026-09-04) rather than discovered by the
  # check crying wolf on its first run.
  for p in $(grep -ohE '`[A-Za-z0-9][A-Za-z0-9._-]*\.sh`' "$docdir"/*.md 2>/dev/null \
             | tr -d '`' | sort -u); do
    if ! test -e "$root/scripts/$p"; then echo "scripts/$p"; found=1; fi
  done
  return $found
}

# ---------------------------------------------------------------- CHECK B ----
# A sha256 is only meaningful next to the thing it hashes, so each hash is keyed
# by the absolute path named on the same line, scoped to the enclosing section.
# Two different hashes for one path inside one section is the defect this found
# for real: STATUS.md gave /usr/bin/indiserver two hashes two rows apart, one of
# them the archive binary from a configuration the box had left.
hash_pairs() {   # $1 = directory holding the .md files -> "file<TAB>section<TAB>path<TAB>hash"
  local f
  for f in "$1"/*.md; do
    awk -v FN="$(basename "$f")" '
      /^#+ / { sect = $0; gsub(/^#+ /, "", sect) }
      /[0-9a-f]{64}/ {
        line = $0
        if (match(line, /[0-9a-f]{64}/)) {
          h = substr(line, RSTART, RLENGTH)
          rest = line
          gsub(/[0-9a-f]{64}/, "", rest)
          if (match(rest, /\/(usr|opt|etc|var|bin|home)\/[A-Za-z0-9._\/-]+/)) {
            p = substr(rest, RSTART, RLENGTH)
            print FN "\t" sect "\t" p "\t" h
          }
        }
      }' "$f"
  done
}

# Deliberate exceptions, PINNED TO THE EXACT HASH SET.
#
# The first version of this keyed on the path alone, and that was wrong in the
# way this project keeps catching: the one place the real defect occurred is
# the one place it would then have been permanently switched off. Replayed
# against the docs as they stood at 3b51dc2 -- where the second hash was
# genuinely stale -- a path-keyed exception suppresses the finding.
#
# Pinning to the hash values keeps the exception from becoming a blind spot: a
# third hash appearing, or either of these two changing, does not match and
# fires again. The exception is a statement about two specific measured values,
# not about a path.
#
#   /usr/bin/indiserver in ubuntuastro's table legitimately carries two: the
#   PPA binary the box runs in configuration B, and the archive 1.9.9 binary it
#   would run after `ppa-purge`. Both rows are labelled. Confirmed 2026-08-26 by
#   hashing indi-bin=1.9.9+dfsg-6 out of the archive .deb.
#
# The list existing at all is the signal. If it grows past a couple of entries
# the rule is wrong, not the docs.
hash_dup_allowed() {   # $1 = section, $2 = path, $3 = space-separated hashes
  local want_a=185e970f1a0f983626e0e126ec1c8ee982f54620d9857eab88b4d9864bde5a2a
  local want_b=b47e51213343be547ac7be122e9337fd6e5e16665153191e000a1c6f211317b7
  local got
  got=$(printf '%s' "$3" | tr ' ' '\n' | grep . | LC_ALL=C sort -u | tr '\n' ' ')
  case "$1|$2" in
    *ubuntuastro*"|/usr/bin/indiserver")
      test "$got" = "$(printf '%s\n%s\n' "$want_a" "$want_b" | LC_ALL=C sort -u | tr '\n' ' ')" && return 0 ;;
  esac
  return 1
}

check_hashes() {   # $1 = directory holding the .md files
  hash_pairs "$1" | LC_ALL=C sort -u | awk -F'\t' '
    { key = $1 "\t" $2 "\t" $3; if (key in seen) { seen[key] = seen[key] " " $4 } else { seen[key] = $4; n[key] = 0 }
      cnt[key]++ }
    END { for (k in seen) if (cnt[k] > 1) print k "\t" seen[k] }'
}

# ---------------------------------------------------------------- CHECK C ----
# Three kinds of reference, all mechanical:
#   1. `SOMEFILE.md`                     -> the file exists
#   2. `SOMEFILE.md`, "Quoted Section"   -> a heading matching it exists there
#   3. LESSONS_LEARNED.md #N             -> "## N." exists
# The corpus of text that may CONTAIN a reference: the .md files, plus the
# COMMENT lines of the harnesses, which cite sections and lesson numbers too.
#
# Two exclusions, both learned by getting it wrong on the first run:
#   * only comment lines of .sh files. Scanning shell code matched quoted
#     fragments and produced a "dangling section" called ' || { echo '.
#   * never this script. It contains the control fixtures below as string
#     literals -- a deliberately dangling section name and lesson #99 -- so
#     scanning itself made the real run report its own test data as findings.
#     A checker is part of the corpus it checks unless it says otherwise.
ref_corpus() {   # $1 = doc dir, $2 = repo root
  cat "$1"/*.md 2>/dev/null
  grep -h '^#' "$2"/scripts/*.sh 2>/dev/null | grep -v 'check-docs'
}

# What a quoted reference may point at. Headings, obviously -- but this project
# also uses a bold lead-in as a de-facto subsection ("**The measurement was
# shown able to fail.**"), and those get cited by name just as headings do, so
# both count as anchors. Checking headings alone reported a live reference as
# dangling.
anchors() {   # $1 = path to a .md file
  grep -E '^#+ ' "$1" 2>/dev/null | sed -E 's/^#+ //'
  # Bold lead-ins, both as their own paragraph and as the head of a bullet --
  # the "residual gap" bullet was cited by name from two other files for days.
  grep -ohE '^[[:space:]]*[-*][[:space:]]+\*\*[^*]{4,}\*\*' "$1" 2>/dev/null | sed -E 's/^[[:space:]]*[-*][[:space:]]+\*\*//; s/\*\*$//'
  grep -ohE '^\*\*[^*]{4,}\*\*' "$1" 2>/dev/null | sed -E 's/^\*\*//; s/\*\*$//'
}

check_refs() {   # $1 = doc dir, $2 = repo root
  local out=0 f target sect n tmp
  tmp=$(mktemp); ref_corpus "$1" "$2" > "$tmp"

  # 1. referenced .md files exist
  for target in $(grep -ohE '\b(README|STATUS|DESIGN|FEDORA|DEBIAN|LESSONS_LEARNED)\.md' "$tmp" | sort -u); do
    test -f "$1/$target" || { echo "missing file: $target"; out=1; }
  done

  # 2. quoted section references resolve, after normalisation
  while IFS=$'\t' read -r f sect; do
    test -n "${f:-}" || continue
    test -f "$1/$f.md" || continue
    if ! anchors "$1/$f.md" | norm | grep -qF -- "$(printf '%s' "$sect" | norm)"; then
      echo "dangling section: $f.md -> \"$sect\""
      out=1
    fi
  done < <(grep -ohE '(README|STATUS|DESIGN|FEDORA|DEBIAN|LESSONS_LEARNED)\.md[^"]{0,14}"[^"]{4,}"' "$tmp" \
           | sed -E 's/^([A-Z_]+)\.md.*"([^"]+)"$/\1\t\2/' | LC_ALL=C sort -u)

  # 3. LESSONS_LEARNED.md #N numbers exist
  for n in $(grep -ohE 'LESSONS_LEARNED\.md[^0-9#]{0,6}#[0-9]+' "$tmp" \
             | grep -oE '#[0-9]+$' | tr -d '#' | sort -un); do
    grep -qE "^## $n\. " "$1/LESSONS_LEARNED.md" || { echo "dangling lesson: #$n"; out=1; }
  done
  rm -f "$tmp"
  return $out
}

# ============================================================== RUN =========
echo "############ checking $(ls "$REPO"/*.md | wc -l) .md files in $REPO ############"

echo
echo "--- CHECK A: every repo path named in a doc exists ---"
MISSING=$(check_paths "$REPO" "$REPO")
if test -z "$MISSING"; then
  pass "all referenced scripts/ and core/ files exist"
else
  echo "$MISSING" | while read -r m; do fail "referenced but absent: $m"; done
  FAIL=1
fi

echo
echo "--- CHECK B: no path carries two different sha256s in one section ---"
DUPS=$(check_hashes "$REPO")
DUPFOUND=0
if test -n "$DUPS"; then
  while IFS=$'\t' read -r f sect path hashes; do
    if hash_dup_allowed "$sect" "$path" "$hashes"; then
      info "allowed (documented exception): $f \"$sect\" $path"
    else
      fail "$f, section \"$sect\": $path has more than one hash -> $hashes"
      DUPFOUND=1
    fi
  done <<< "$DUPS"
fi
test "$DUPFOUND" -eq 0 && pass "no contradictory hashes"

echo
echo "--- CHECK C: cross-references resolve ---"
REFOUT=$(check_refs "$REPO" "$REPO")
if test -z "$REFOUT"; then
  pass "every referenced file, quoted section and lesson number resolves"
else
  echo "$REFOUT" | while read -r r; do fail "$r"; done
  FAIL=1
fi

# ========================================================== CONTROLS ========
# Each check above passes by finding NOTHING. Plant one fault of each kind in a
# throwaway copy and require it to be found (LESSONS_LEARNED.md #1).
echo
echo "--- CONTROLS: plant a fault of each kind and require it to be found ---"
W=$(mktemp -d /tmp/check-docs-control.XXXXXX)
cp "$REPO"/*.md "$W"/ 2>/dev/null

printf '\nSee `scripts/test-not-a-real-harness.sh` for details.\n' >> "$W/STATUS.md"
if check_paths "$W" "$REPO" | grep -q 'test-not-a-real-harness.sh'; then
  ctl "A reports a planted missing path"
else
  fail "CONTROL A did not fire -- CHECK A cannot see a missing path, so its pass means nothing"
fi

printf '\nThe harness `not-a-real-bare-name.sh` covers this.\n' >> "$W/STATUS.md"
if check_paths "$W" "$REPO" | grep -q 'not-a-real-bare-name.sh'; then
  ctl "A reports a planted missing BARE script name (no scripts/ prefix)"
else
  fail "CONTROL A2 did not fire -- CHECK A cannot see a bare <name>.sh mention, the exact gap that let a renamed script dangle in STATUS.md"
fi

# The continuation-shorthand exclusion must STAY excluded -- if this starts
# firing, the [A-Za-z0-9] anchor has been lost and the check will cry wolf on
# DESIGN.md's own prose.
printf '\nSee `scripts/smoke-test-core.sh` / `-core-deb.sh` for the pair.\n' >> "$W/STATUS.md"
if check_paths "$W" "$REPO" | grep -q -- '-core-deb.sh'; then
  fail "CONTROL A3: CHECK A is treating a '-suffix' continuation shorthand as a filename -- it will cry wolf on DESIGN.md"
else
  ctl "A ignores a '-suffix' continuation shorthand, not a real filename"
fi

printf '\n### Control section\n\n| `/usr/bin/indiserver` | `%s` |\n| `/usr/bin/indiserver` again | `%s` |\n' \
  "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..64})" >> "$W/STATUS.md"
if check_hashes "$W" | grep -q '/usr/bin/indiserver'; then
  ctl "B reports a planted contradictory hash"
else
  fail "CONTROL B did not fire -- CHECK B cannot see two hashes for one path"
fi

# The allowlist is the most dangerous line in this script -- it is the only
# thing that can silence a real finding -- so it gets a control of its own.
# Add a THIRD hash for the allowed path and the exception must stop matching.
printf '\n| `/usr/bin/indiserver` yet again | `%s` |\n' "$(printf 'c%.0s' {1..64})" >> "$W/STATUS.md"
ALLOWCTL=0
while IFS=$'\t' read -r f sect path hashes; do
  test -n "${path:-}" || continue
  case "$path" in */usr/bin/indiserver|/usr/bin/indiserver)
    hash_dup_allowed "$sect" "$path" "$hashes" || ALLOWCTL=1 ;;
  esac
done < <(check_hashes "$W")
test "$ALLOWCTL" -eq 1 \
  && ctl "the pinned exception STOPS matching when a third hash appears -- it cannot become a blind spot" \
  || fail "CONTROL B2 did not fire -- the exception still matches after a hash changed, so it silences real findings"

printf '\nSee `DESIGN.md`, "A Section That Does Not Exist Anywhere".\n' >> "$W/DEBIAN.md"
printf '\nAlso `LESSONS_LEARNED.md` #99 applies.\n' >> "$W/DEBIAN.md"
CREF=$(check_refs "$W" "$REPO")
echo "$CREF" | grep -q 'A Section That Does Not Exist' \
  && ctl "C reports a planted dangling section reference" \
  || fail "CONTROL C1 did not fire -- CHECK C cannot see a dangling section reference"
echo "$CREF" | grep -q 'dangling lesson: #99' \
  && ctl "C reports a planted dangling lesson number" \
  || fail "CONTROL C2 did not fire -- CHECK C cannot see a dangling lesson number"

rm -rf "$W"

echo
echo "==================================================================="
if test "$FAIL" -eq 0; then
  echo "DOCS: no mechanical staleness found, and every control fired."
else
  echo "DOCS: findings above."
fi
echo "  Prose claims are NOT checked here -- see this file's header."
echo "==================================================================="
exit "$FAIL"
