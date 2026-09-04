#!/bin/bash
#
# Rewrite every version-carrying field in the indi-stable-3rdparty packaging
# to a new upstream indi-3rdparty tag. Used by
# .github/workflows/3rdparty-release.yml's promote job, and runnable by hand.
#
# This exists as a script rather than inline YAML for one reason: the Debian
# -drivers packaging carries EIGHTEEN hardcoded literal version pins on
# -libs, and core/deb-3rdparty-drivers/control's own comment says to "update
# every line below by hand whenever -libs's own version changes". There is no
# dpkg substvar that can express one source package's dependency on another
# source package's version, so hand-synchronization is the only mechanism
# available -- which makes it exactly the thing to automate carefully and
# assert, not to sed hopefully in a workflow step.
#
# Run as: bash scripts/bump-3rdparty-version.sh <new-upstream-tag> [deb-revision]
#   e.g.  bash scripts/bump-3rdparty-version.sh v2.2.4.2
#
# Rewrites, all in the working tree (committing is the caller's job):
#   core/rpm/indi-stable-3rdparty-libs.spec       Version: + a %changelog entry
#   core/rpm/indi-stable-3rdparty-drivers.spec    Version: + a %changelog entry
#   core/deb-3rdparty-libs/changelog              a new dch entry
#   core/deb-3rdparty-drivers/changelog           a new dch entry
#   core/deb-3rdparty-drivers/control             every literal -libs pin
#
# Deliberately NOT rewritten: Release:/-1, which stays at 1 for a new upstream
# version. Re-releasing the SAME upstream tag with different packaging is the
# separate, still-unsolved "Release tagging across rebuilds" item in STATUS.md;
# this script would need a --release flag for that and does not pretend to
# have one.
#
# Idempotent by design. Running it twice for the same version rewrites the
# version fields to the same value and ADDS NO SECOND CHANGELOG ENTRY -- the
# duplicate-entry bug core-release.yml actually produced on 2026-08-28, whose
# core/deb/changelog had to be squashed back by hand afterward.
#
# NOT transactional: an abort partway through leaves the working tree half
# rewritten (the specs' Version: fields are rewritten before the Debian pins
# are validated). Discard with `git checkout -- .` and fix the cause. In CI
# this is automatic -- a failed step fails the job and nothing is committed --
# which is why it is documented rather than engineered around.
#
set -u

# --repackage: hold the upstream tag, advance the release. See
# bump-core-version.sh for why this exists; for THIS package it is the case
# that actually occurred -- the 2026-09-04 runtime-symlink fix
# (LESSONS_LEARNED.md #22) changed what -libs installs at an unchanged
# upstream tag, and without a release bump nobody on the broken build would
# ever be offered the fix.
REPACKAGE=0
if [ "${1:-}" = "--repackage" ]; then REPACKAGE=1; shift; fi

REPO=$(cd "$(dirname "$0")/.." && pwd)
SPEC_EARLY="$REPO/core/rpm/indi-stable-3rdparty-libs.spec"

if [ "$REPACKAGE" -eq 1 ]; then
  test -f "$SPEC_EARLY" || { echo "*** ABORT: missing $SPEC_EARLY ***" >&2; exit 1; }
  CUR_V=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$SPEC_EARLY" | head -1)
  CUR_R=$(sed -n 's/^Release:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$SPEC_EARLY" | head -1)
  [ -n "$CUR_V" ] || { echo "*** ABORT: could not read Version: ***" >&2; exit 1; }
  [ -n "$CUR_R" ] || { echo "*** ABORT: could not read a numeric Release: ***" >&2; exit 1; }
  NEW_TAG="v${CUR_V}"
  REV=$((CUR_R + 1))
  echo "repackage mode: keeping ${CUR_V}, release ${CUR_R} -> ${REV}"
else
  NEW_TAG=${1:?usage: bump-3rdparty-version.sh [--repackage] <new-upstream-tag> [release]}
  REV=${2:-1}
fi
DEB_REV=$REV

: "${DEBFULLNAME:=Will Snyder}"
: "${DEBEMAIL:=william@williamlsnyder.org}"
export DEBFULLNAME DEBEMAIL

LIBS_SPEC="$REPO/core/rpm/indi-stable-3rdparty-libs.spec"
DRIVERS_SPEC="$REPO/core/rpm/indi-stable-3rdparty-drivers.spec"
LIBS_CHANGELOG="$REPO/core/deb-3rdparty-libs/changelog"
DRIVERS_CHANGELOG="$REPO/core/deb-3rdparty-drivers/changelog"
DRIVERS_CONTROL="$REPO/core/deb-3rdparty-drivers/control"

die() { echo "*** ABORT: $* ***" >&2; exit 1; }
say() { echo "  $*"; }

for f in "$LIBS_SPEC" "$DRIVERS_SPEC" "$LIBS_CHANGELOG" "$DRIVERS_CHANGELOG" "$DRIVERS_CONTROL"; do
  test -f "$f" || die "missing: $f"
done
command -v dch >/dev/null 2>&1 || die "dch is required (apt-get install devscripts)"

case "$NEW_TAG" in
  v[0-9]*) ;;
  *) die "tag '$NEW_TAG' is not shaped like a vX.Y.Z upstream tag" ;;
esac
NEW_VERSION=${NEW_TAG#v}

# The libs spec is the source of truth for what version we are moving FROM --
# every other file is required below to agree with it.
OLD_VERSION=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$LIBS_SPEC" | head -1)
[ -n "$OLD_VERSION" ] || die "could not read Version: from $LIBS_SPEC"

# Versions contain dots, which are regex metacharacters -- escape before any
# of them reaches sed or grep as a pattern.
esc() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
OLD_RE=$(esc "$OLD_VERSION")

echo "############ bumping indi-stable-3rdparty: $OLD_VERSION -> $NEW_VERSION (deb revision $DEB_REV) ############"

if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
  say "NOTE: already at $NEW_VERSION -- version fields will be rewritten to the"
  say "      same value and no changelog entry added. Not an error."
fi

# ---------------------------------------------------------------- specs ----
# Version: only. Release: deliberately untouched -- see the header.
# Both specs must carry the SAME Version AND Release: -drivers pins -libs
# by %{version}-%{release}, so a release skew between them makes the drivers
# BuildRequires unsatisfiable. Until 2026-09-04 Release: was never rewritten
# at all here, so passing a revision moved the Debian side and the RPM
# %changelog while leaving the actual RPM NVR at -1.
for spec in "$LIBS_SPEC" "$DRIVERS_SPEC"; do
  sed -i "s/^Version:\([[:space:]]*\).*$/Version:\1${NEW_VERSION}/" "$spec"
  GOT=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$spec" | head -1)
  [ "$GOT" = "$NEW_VERSION" ] \
    || die "$(basename "$spec"): Version: is '$GOT' after rewrite, expected '$NEW_VERSION'"
  sed -i "s/^Release:\([[:space:]]*\)[0-9][0-9]*/Release:\1${REV}/" "$spec"
  GOT_REL=$(sed -n 's/^Release:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$spec" | head -1)
  [ "$GOT_REL" = "$REV" ] \
    || die "$(basename "$spec"): Release: is '$GOT_REL' after rewrite, expected '$REV'"
  grep -qE '^Release:[[:space:]]*[0-9]+%\{\?dist\}' "$spec" \
    || die "$(basename "$spec"): Release: lost its %{?dist} suffix"
  say "PASS: $(basename "$spec") -> ${NEW_VERSION}-${REV}%{?dist}"
done

# ------------------------------------------------------- the 18 deb pins ----
# Anchored on the package name, so the rewrite can only ever touch a real
# dependency line. The explanatory comment in this same file was changed to
# say "(= X.Y.Z-1)" rather than a real version precisely so that it can never
# be caught by this pattern nor go stale.
# The invariant asserted here is NOT "every pin I recognized, I rewrote" --
# that version of this check passed while silently rewriting 9 of 18 pins,
# found by a planted control on 2026-09-04 that mangled `(=` to `(>=` on the
# Build-Depends half only. The 9 runtime Depends lines still matched, so
# "found 9, rewrote 9" was self-consistent and reported success. A pin that
# changes shape simply dropped out of the count it was being compared against.
#
# The invariant is instead: EVERY dependency-shaped mention of a -libs
# sibling must end up exactly-pinned at the new version. The two patterns
# below differ only in that one is operator-agnostic, so any pin whose
# operator, spacing or version fails to match the rewrite is still counted as
# something that SHOULD have been pinned, and the mismatch aborts.
#
# "Dependency" is decided by PARSING the Depends:/Build-Depends: fields, not
# by matching a shape in the raw text. A regex anchored on "name followed by
# (" was tried first and was itself defeated by a planted control the same
# day: a dependency with NO version clause at all is not followed by "(", so
# it silently dropped out of the count and an entirely UNPINNED -libs
# dependency -- the most dangerous case of the three, since -drivers would
# then accept any -libs version -- passed as clean.
#
# Parsing the fields also disposes of the nine prose mentions in Description:
# blocks ("...the bundled Apogee SDK (indi-stable-3rdparty-libs-apogee).")
# structurally rather than by pattern luck: a Description is a different
# field, so those lines can never reach this output at all.
dep_tokens() {   # emit one dependency token per line, Depends:/Build-Depends: only
  awk '
    /^[ \t]*#/                { next }
    /^(Build-)?Depends:/      { inf=1; v=$0; sub(/^[^:]*:[ \t]*/,"",v); buf=buf v; next }
    /^[A-Za-z][A-Za-z0-9-]*:/ { if(inf){emit()} inf=0; next }
    inf && /^[ \t]/           { v=$0; sub(/^[ \t]+/," ",v); buf=buf v; next }
                              { if(inf){emit()} inf=0 }
    END                       { if(inf) emit() }
    function emit(   n,a,i,t) {
      n=split(buf,a,",")
      for(i=1;i<=n;i++){ t=a[i]; gsub(/^[ \t]+|[ \t]+$/,"",t); if(t!="") print t }
      buf=""
    }
  ' "$1"
}

DEPS_TOTAL=$(dep_tokens "$DRIVERS_CONTROL" | grep -c 'indi-stable-3rdparty-libs')
[ "$DEPS_TOTAL" -gt 0 ] \
  || die "found NO -libs dependencies in $(basename "$DRIVERS_CONTROL")'s Depends:/Build-Depends: fields -- the file's format has changed and this script no longer understands it"
say "found $DEPS_TOTAL -libs dependencies (every one must end up exactly pinned)"

sed -i -E "s/(indi-stable-3rdparty-libs-[a-z0-9]+(-dev)?[[:space:]]*\([[:space:]]*=[[:space:]]*)${OLD_RE}-[0-9]+\)/\1${NEW_VERSION}-${DEB_REV})/g" \
  "$DRIVERS_CONTROL"

# Anchored whole-token: a bare unpinned name fails this, as does any other
# operator, spacing or version.
PINNED_RE="^indi-stable-3rdparty-libs-[a-z0-9]+(-dev)?[[:space:]]*\([[:space:]]*=[[:space:]]*$(esc "$NEW_VERSION")-${DEB_REV}\)$"
UNPINNED=$(dep_tokens "$DRIVERS_CONTROL" | grep 'indi-stable-3rdparty-libs' | grep -vE "$PINNED_RE" || true)

if [ -n "$UNPINNED" ]; then
  echo "--- -libs dependencies NOT exactly pinned at ${NEW_VERSION}-${DEB_REV}: ---" >&2
  printf '%s\n' "$UNPINNED" | sed 's/^/    /' >&2
  die "$(printf '%s\n' "$UNPINNED" | wc -l) of $DEPS_TOTAL -libs dependencies are not exactly pinned at ${NEW_VERSION}-${DEB_REV} (listed above) -- a changed operator, a missing version clause, or a stale version all land here, and leaving any of them is how -drivers ends up accepting a -libs build CI is not producing"
fi
say "PASS: all $DEPS_TOTAL -libs dependencies pinned at ${NEW_VERSION}-${DEB_REV}"

# ------------------------------------------------------- RPM %changelog ----
# core-release.yml's promote job never did this for core -- STATUS.md records
# it as a known gap ("a genuinely new promotion would leave the RPM spec's
# own changelog silently behind Debian's"). Done here from the start.
rpm_changelog_add() {   # $1 = spec, $2 = one-line summary
  local spec=$1 summary=$2 stamp entry
  stamp=$(date +'%a %b %d %Y')
  entry="* ${stamp} ${DEBFULLNAME} <${DEBEMAIL}> - ${NEW_VERSION}-${DEB_REV}"

  # Match on the VERSION-RELEASE alone, never on the whole line. Matching the
  # full line meant matching the date stamp too, so a pre-existing entry for
  # the same version written on a DIFFERENT day did not count as present --
  # and the first real CI promotion duly added a second "- 2.2.4.1-1" entry
  # beneath the existing one, dated four days later. That is the very
  # duplicate this function was written to prevent; the Debian half never had
  # the bug because it always compared versions rather than rendered lines.
  if grep -qE "^\*.* - ${NEW_VERSION}-${DEB_REV}[[:space:]]*$" "$spec"; then
    say "SKIP: $(basename "$spec") already has a %changelog entry for ${NEW_VERSION}-${DEB_REV}"
    return 0
  fi
  grep -q '^%changelog' "$spec" || die "$(basename "$spec") has no %changelog section"

  awk -v entry="$entry" -v summary="$summary" '
    /^%changelog$/ && !done { print; print entry; print "- " summary; print ""; done=1; next }
    { print }
  ' "$spec" > "$spec.tmp" && mv "$spec.tmp" "$spec"

  grep -qF "$entry" "$spec" \
    || die "$(basename "$spec"): %changelog entry was not inserted"
  say "PASS: $(basename "$spec") %changelog entry added"
}

rpm_changelog_add "$LIBS_SPEC" \
  "New upstream release ${NEW_TAG}, built and gated by 3rdparty-release.yml."
rpm_changelog_add "$DRIVERS_SPEC" \
  "New upstream release ${NEW_TAG}, built and gated by 3rdparty-release.yml."

# ---------------------------------------------------------- deb changelog ----
deb_changelog_add() {   # $1 = changelog path
  local cl=$1 top
  top=$(head -1 "$cl")
  case "$top" in
    *"(${NEW_VERSION}-${DEB_REV})"*)
      say "SKIP: $(basename "$(dirname "$cl")")/changelog top entry is already ${NEW_VERSION}-${DEB_REV}"
      return 0 ;;
  esac
  dch --changelog "$cl" --newversion "${NEW_VERSION}-${DEB_REV}" \
      --distribution unstable \
      "New upstream release ${NEW_TAG}, built and gated by 3rdparty-release.yml" \
    || die "dch failed on $cl"
  head -1 "$cl" | grep -qF "(${NEW_VERSION}-${DEB_REV})" \
    || die "$cl top entry is not ${NEW_VERSION}-${DEB_REV} after dch"
  say "PASS: $(dirname "$cl" | xargs basename)/changelog -> ${NEW_VERSION}-${DEB_REV}"
}

deb_changelog_add "$LIBS_CHANGELOG"
deb_changelog_add "$DRIVERS_CHANGELOG"

# ------------------------------------------------------------ final sweep ----
# The specs' BuildRequires pin -libs by %{version}-%{release}, which tracks
# automatically -- but the Debian side has no such mechanism, so confirm by
# reading the files back that no packaging file still names the old version
# in a dependency position. Comments and %changelog history legitimately
# still mention it, and are excluded.
if [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
  STRAY=$(grep -nE "\([[:space:]]*[<>=]*=[[:space:]]*${OLD_RE}-" "$DRIVERS_CONTROL" | grep -v '^[0-9]*: *#' || true)
  [ -z "$STRAY" ] || die "stray old-version dependency pin(s) remain:
$STRAY"
fi

echo
echo "############ BUMP COMPLETE: indi-stable-3rdparty at ${NEW_VERSION}-${DEB_REV} ############"
echo "Review with: git diff"
exit 0
