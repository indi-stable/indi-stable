#!/bin/bash
#
# Rewrite every version-carrying field in the indi-stable-core packaging to a
# new upstream indi tag. Used by .github/workflows/core-release.yml's promote
# job, and runnable by hand.
#
# Run as: bash scripts/bump-core-version.sh <new-upstream-tag> [deb-revision]
#   e.g.  bash scripts/bump-core-version.sh v2.2.5
#
# Rewrites, all in the working tree (committing is the caller's job):
#   core/rpm/indi-stable-core.spec   Version: + a %changelog entry
#   core/deb/changelog               a new dch entry
#
# Source0 is NOT rewritten and must not be: the spec derives it from Version
# through `%global upstream_tag v%{version}`, so bumping Version moves the
# tarball URL with it. Confirmed by expanding the spec with rpmspec -P rather
# than by reading the template.
#
# Release:/-1 is deliberately not rewritten -- a new upstream version resets
# it to 1. Re-releasing the SAME tag with changed packaging is the separate,
# still-open "Release tagging across rebuilds" item in STATUS.md.
#
# This exists to close two real defects in the inline promote step it
# replaces, both recorded in STATUS.md:
#
#   1. It never added an RPM %changelog entry at all, only a Debian one via
#      dch, so a genuinely new promotion would have left the spec's changelog
#      silently behind Debian's.
#   2. Its dch call had no idempotency guard, and the 2026-08-28 end-to-end
#      run duly produced a duplicate core/deb/changelog entry that had to be
#      squashed back by hand afterward.
#
# Both %changelog guards below match on VERSION-RELEASE rather than on the
# whole rendered entry line. Matching the line matches its date stamp too,
# which is how bump-3rdparty-version.sh let the first real 3rdparty promotion
# add a second entry dated four days after the first -- the same bug in a
# different place, found only by reading what a real promotion committed.
#
# NOT transactional: an abort partway leaves the tree half rewritten.
# Discard with `git checkout -- .`. In CI a failed step fails the job and
# nothing is committed.
#
set -u

# --repackage: keep the CURRENT upstream version and advance the release
# number instead. This is the case Release: 1%{?dist} could not express --
# packaging changed, upstream did not -- and it is not hypothetical: the
# 2026-09-04 runtime-symlink fix (LESSONS_LEARNED.md #22) changed what the
# packages install at an unchanged upstream tag. Without a release bump,
# users already on the broken build get no update, because the NVR is
# identical.
REPACKAGE=0
if [ "${1:-}" = "--repackage" ]; then REPACKAGE=1; shift; fi

REPO=$(cd "$(dirname "$0")/.." && pwd)
SPEC_EARLY="$REPO/core/rpm/indi-stable-core.spec"

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
  NEW_TAG=${1:?usage: bump-core-version.sh [--repackage] <new-upstream-tag> [release]}
  REV=${2:-1}
fi
DEB_REV=$REV

: "${DEBFULLNAME:=Will Snyder}"
: "${DEBEMAIL:=william@williamlsnyder.org}"
export DEBFULLNAME DEBEMAIL

SPEC="$REPO/core/rpm/indi-stable-core.spec"
CHANGELOG="$REPO/core/deb/changelog"

die() { echo "*** ABORT: $* ***" >&2; exit 1; }
say() { echo "  $*"; }

test -f "$SPEC"      || die "missing: $SPEC"
test -f "$CHANGELOG" || die "missing: $CHANGELOG"
command -v dch >/dev/null 2>&1 || die "dch is required (apt-get install devscripts)"

case "$NEW_TAG" in
  v[0-9]*) ;;
  *) die "tag '$NEW_TAG' is not shaped like a vX.Y.Z upstream tag (indi tags carry a leading v)" ;;
esac
NEW_VERSION=${NEW_TAG#v}

OLD_VERSION=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$SPEC" | head -1)
[ -n "$OLD_VERSION" ] || die "could not read Version: from $SPEC"

echo "############ bumping indi-stable-core: $OLD_VERSION -> $NEW_VERSION (release $REV) ############"
if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
  say "NOTE: already at $NEW_VERSION -- Version: rewritten to the same value, no changelog entry. Not an error."

  # Same-version rebuild: Release must not move BACKWARD. dch enforces this
  # for the Debian changelog natively; nothing protected the RPM side the
  # same way, and it silently regressed a spec's Release: for real,
  # 2026-09-04, when a seed carried a higher Release than the target repo's
  # own release history justified (found in bump-3rdparty-version.sh, same
  # gap here since both scripts share this shape). No constraint when the
  # upstream VERSION itself changed.
  OLD_RELEASE=$(sed -n 's/^Release:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$SPEC" | head -1)
  [ -n "$OLD_RELEASE" ] || die "could not read a numeric Release: from $SPEC"
  if [ "$REV" -lt "$OLD_RELEASE" ] 2>/dev/null; then
    die "refusing to move Release: backward for the SAME version $NEW_VERSION: $SPEC is already at ${NEW_VERSION}-${OLD_RELEASE}, and this run would rewrite it to ${NEW_VERSION}-${REV} -- an older release number describing content that has not changed upstream. If this repo's own release history genuinely never reached ${OLD_RELEASE}, fix the spec/changelog by hand first rather than silently overwriting them here."
  fi
fi

# ------------------------------------------------------------------ spec ----
# [[:space:]]* rather than a fixed run of spaces: the step this replaces
# matched "^Version:        .*" with exactly eight literal spaces, which
# silently rewrites nothing at all if the column ever shifts by one -- and a
# no-op sed reports success just as loudly as a real one.
sed -i "s/^Version:\([[:space:]]*\).*$/Version:\1${NEW_VERSION}/" "$SPEC"
GOT=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$SPEC" | head -1)
[ "$GOT" = "$NEW_VERSION" ] || die "Version: is '$GOT' after rewrite, expected '$NEW_VERSION'"
say "PASS: Version: -> $NEW_VERSION"

# Release: must carry the SAME number as the Debian revision. Until
# 2026-09-04 this line did not exist and Release: stayed at 1%{?dist} no
# matter what revision was passed -- so `bump-core-version.sh v2.2.4.2 2`
# built an RPM whose NVR was 2.2.4.2-1 while its own %changelog said
# 2.2.4.2-2, and Debian correctly produced -2. One promotion, two different
# revisions, and an RPM changelog describing a package that did not exist.
# Demonstrated by running it before this was fixed, not reasoned about.
sed -i "s/^Release:\([[:space:]]*\)[0-9][0-9]*/Release:\1${REV}/" "$SPEC"
GOT_REL=$(sed -n 's/^Release:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$SPEC" | head -1)
[ "$GOT_REL" = "$REV" ] || die "Release: is '$GOT_REL' after rewrite, expected '$REV'"
grep -qE '^Release:[[:space:]]*[0-9]+%\{\?dist\}' "$SPEC" \
  || die "Release: lost its %{?dist} suffix in the rewrite"
say "PASS: Release: -> ${REV}%{?dist}"

# Source0 must have followed Version through %{upstream_tag}. Asserted rather
# than assumed: if someone ever hardcodes the tag into Source0, this bump
# would otherwise keep building the OLD tarball under the NEW version number,
# which is the worst failure this script could produce silently.
if command -v rpmspec >/dev/null 2>&1; then
  SRC=$(rpmspec -P "$SPEC" 2>/dev/null | grep -m1 '^Source0:' || true)
  case "$SRC" in
    *"${NEW_TAG}.tar.gz"*) say "PASS: Source0 follows Version -- resolves to ${NEW_TAG}.tar.gz" ;;
    "") say "NOTE: rpmspec could not expand the spec; Source0 not verified" ;;
    *) die "Source0 does not resolve to ${NEW_TAG}: $SRC -- it is no longer derived from Version, so this bump would build the wrong tarball" ;;
  esac
else
  say "NOTE: rpmspec unavailable; Source0 derivation not verified"
fi

# ------------------------------------------------------------ %changelog ----
STAMP=$(date +'%a %b %d %Y')
ENTRY="* ${STAMP} ${DEBFULLNAME} <${DEBEMAIL}> - ${NEW_VERSION}-${DEB_REV}"
if grep -qE "^\*.* - ${NEW_VERSION}-${DEB_REV}[[:space:]]*$" "$SPEC"; then
  say "SKIP: %changelog already has an entry for ${NEW_VERSION}-${DEB_REV}"
else
  grep -q '^%changelog' "$SPEC" || die "no %changelog section in $SPEC"
  awk -v e="$ENTRY" -v s="New upstream release ${NEW_TAG}, built and gated by core-release.yml." '
    /^%changelog$/ && !d { print; print e; print "- " s; print ""; d=1; next } { print }
  ' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC"
  grep -qF "$ENTRY" "$SPEC" || die "%changelog entry was not inserted"
  say "PASS: %changelog entry added"
fi

# -------------------------------------------------------- deb changelog ----
TOP=$(head -1 "$CHANGELOG")
case "$TOP" in
  *"(${NEW_VERSION}-${DEB_REV})"*)
    say "SKIP: deb changelog top entry is already ${NEW_VERSION}-${DEB_REV}" ;;
  *)
    dch --changelog "$CHANGELOG" --newversion "${NEW_VERSION}-${DEB_REV}" \
        --distribution unstable \
        "New upstream release ${NEW_TAG}, built and gated by core-release.yml" \
      || die "dch failed on $CHANGELOG"
    head -1 "$CHANGELOG" | grep -qF "(${NEW_VERSION}-${DEB_REV})" \
      || die "deb changelog top entry is not ${NEW_VERSION}-${DEB_REV} after dch"
    say "PASS: deb changelog -> ${NEW_VERSION}-${DEB_REV}" ;;
esac

echo
echo "############ BUMP COMPLETE: indi-stable-core at ${NEW_VERSION}-${DEB_REV} ############"
exit 0
