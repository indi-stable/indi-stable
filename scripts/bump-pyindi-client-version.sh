#!/bin/bash
#
# Rewrite every version-carrying field in the indi-stable-pyindi-client
# packaging to a new PyPI release. Used by
# .github/workflows/pyindi-client-release.yml's promote job, and runnable by
# hand.
#
# Run as: bash scripts/bump-pyindi-client-version.sh [--spec-only] <version> <sdist-url> <sha256> [deb-revision]
#
# The URL and hash are ARGUMENTS, not derived here, and that is the whole
# reason this differs from bump-3rdparty-version.sh. A PyPI sdist URL carries
# a content-addressed path segment --
#   .../packages/55/92/bbde7827.../pyindi_client-2.2.0.tar.gz
# -- which cannot be constructed from the version string. scripts/check-
# upstream-pypi.sh resolves both from the same API response and passes them
# through, so the URL and the hash can never come from two different fetches.
#
# Rewrites, all in the working tree (committing is the caller's job):
#   pyindi-client/rpm/indi-stable-pyindi-client.spec   Version:, Source0:,
#                                                      the %prep sha256, and
#                                                      a %changelog entry
#   pyindi-client/deb/changelog                        a new dch entry
#
# Release:/-1 is deliberately NOT rewritten -- a new upstream version resets
# it to 1. Re-releasing the SAME version with changed packaging is the
# separate, still-open "Release tagging across rebuilds" item in STATUS.md.
#
# Idempotent: rerunning at the same version rewrites the same values and adds
# no second changelog entry. The %changelog guard matches on VERSION-RELEASE
# rather than the whole rendered line, because matching the line matches its
# date stamp too -- which is how bump-3rdparty-version.sh let the first real
# CI promotion add a duplicate entry dated four days after the original.
#
# NOT transactional: an abort partway leaves the tree half rewritten.
# Discard with `git checkout -- .`. In CI a failed step fails the job and
# nothing is committed.
#
set -u

# --spec-only rewrites the RPM spec and leaves the Debian changelog alone.
# It exists for the Fedora BUILD job, which needs Version:/Source0:/the %prep
# hash pointed at the new release in its own transient checkout but has no
# business touching Debian packaging -- and, concretely, has no dch: dch comes
# from devscripts, which is a Debian tool and not dependably present in a
# fedora container. Without this the script would either die on a missing dch
# or, worse, quietly skip a step it claims to perform.
SPEC_ONLY=0
if [ "${1:-}" = "--spec-only" ]; then SPEC_ONLY=1; shift; fi

NEW_VERSION=${1:?usage: bump-pyindi-client-version.sh [--spec-only] <version> <sdist-url> <sha256> [release]}
SDIST_URL=${2:?usage: bump-pyindi-client-version.sh [--spec-only] <version> <sdist-url> <sha256> [release]}
SDIST_SHA=${3:?usage: bump-pyindi-client-version.sh [--spec-only] <version> <sdist-url> <sha256> [release]}
REV=${4:-1}
DEB_REV=$REV
REPO=$(cd "$(dirname "$0")/.." && pwd)

: "${DEBFULLNAME:=Will Snyder}"
: "${DEBEMAIL:=william@williamlsnyder.org}"
export DEBFULLNAME DEBEMAIL

SPEC="$REPO/pyindi-client/rpm/indi-stable-pyindi-client.spec"
CHANGELOG="$REPO/pyindi-client/deb/changelog"

die() { echo "*** ABORT: $* ***" >&2; exit 1; }
say() { echo "  $*"; }

test -f "$SPEC" || die "missing: $SPEC"
if [ "$SPEC_ONLY" -eq 0 ]; then
  test -f "$CHANGELOG" || die "missing: $CHANGELOG"
  command -v dch >/dev/null 2>&1 || die "dch is required (apt-get install devscripts), or pass --spec-only"
fi

case "$NEW_VERSION" in
  [0-9]*) ;;
  *) die "'$NEW_VERSION' is not shaped like a PyPI version (no leading v -- pyindi-client releases as 2.2.0, not v2.2.0)" ;;
esac
# A 64-hex sha256, checked before it is written into a spec that will
# sha256sum -c against it at build time. A malformed hash here does not fail
# until the build, in a place that looks like an upstream tarball problem.
case "$SDIST_SHA" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
  *) die "'$SDIST_SHA' does not look like a lowercase hex sha256" ;;
esac
[ ${#SDIST_SHA} -eq 64 ] || die "sha256 is ${#SDIST_SHA} characters, expected 64"
case "$SDIST_URL" in
  https://files.pythonhosted.org/*) ;;
  *) die "'$SDIST_URL' is not a files.pythonhosted.org URL" ;;
esac

OLD_VERSION=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$SPEC" | head -1)
[ -n "$OLD_VERSION" ] || die "could not read Version: from $SPEC"

esc() { printf '%s' "$1" | sed 's/[.[\*^$/&]/\\&/g'; }

echo "############ bumping indi-stable-pyindi-client: $OLD_VERSION -> $NEW_VERSION (deb revision $DEB_REV) ############"
[ "$OLD_VERSION" = "$NEW_VERSION" ] && say "NOTE: already at $NEW_VERSION -- fields rewritten to the same value, no changelog entry. Not an error."

# ------------------------------------------------------------------ spec ----
sed -i "s/^Version:\([[:space:]]*\).*$/Version:\1${NEW_VERSION}/" "$SPEC"
GOT=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$SPEC" | head -1)
[ "$GOT" = "$NEW_VERSION" ] || die "Version: is '$GOT' after rewrite, expected '$NEW_VERSION'"
say "PASS: Version: -> $NEW_VERSION"

# Release: must carry the same number as the Debian revision -- until
# 2026-09-04 it was never rewritten, so a revision argument moved the deb
# side and the RPM %changelog while the RPM NVR stayed at -1.
sed -i "s/^Release:\([[:space:]]*\)[0-9][0-9]*/Release:\1${REV}/" "$SPEC"
GOT_REL=$(sed -n 's/^Release:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$SPEC" | head -1)
[ "$GOT_REL" = "$REV" ] || die "Release: is '$GOT_REL' after rewrite, expected '$REV'"
grep -qE '^Release:[[:space:]]*[0-9]+%\{\?dist\}' "$SPEC" \
  || die "Release: lost its %{?dist} suffix in the rewrite"
say "PASS: Release: -> ${REV}%{?dist}"

sed -i "s|^Source0:\([[:space:]]*\).*$|Source0:\1$(esc "$SDIST_URL")|" "$SPEC"
GOT=$(sed -n 's|^Source0:[[:space:]]*\(.*\)$|\1|p' "$SPEC" | head -1)
[ "$GOT" = "$SDIST_URL" ] || die "Source0: is '$GOT' after rewrite, expected '$SDIST_URL'"
say "PASS: Source0: -> $(basename "$SDIST_URL")"

# The %prep hash line. Anchored on the sha256sum -c construct rather than on
# the old hash value, so a spec whose hash was already changed by hand still
# gets corrected rather than silently skipped.
OLD_SHA=$(grep -oE '^echo "[0-9a-f]{64}' "$SPEC" | head -1 | sed 's/^echo "//')
[ -n "$OLD_SHA" ] || die "could not find the 64-hex sha256 line in $SPEC's %prep -- the verification construct has changed and this script no longer understands it"
sed -i "s/^echo \"${OLD_SHA}/echo \"${SDIST_SHA}/" "$SPEC"
grep -qF "echo \"${SDIST_SHA}" "$SPEC" || die "sha256 line was not rewritten"
# And the old hash must be gone, or the spec would carry two and check the wrong one.
if [ "$OLD_SHA" != "$SDIST_SHA" ]; then
  grep -qF "$OLD_SHA" "$SPEC" && die "the previous sha256 $OLD_SHA is still present after the rewrite"
fi
say "PASS: %prep sha256 -> ${SDIST_SHA:0:16}..."

# ------------------------------------------------------------ %changelog ----
STAMP=$(date +'%a %b %d %Y')
ENTRY="* ${STAMP} ${DEBFULLNAME} <${DEBEMAIL}> - ${NEW_VERSION}-${DEB_REV}"
if grep -qE "^\*.* - ${NEW_VERSION}-${DEB_REV}[[:space:]]*$" "$SPEC"; then
  say "SKIP: %changelog already has an entry for ${NEW_VERSION}-${DEB_REV}"
else
  grep -q '^%changelog' "$SPEC" || die "no %changelog section in $SPEC"
  awk -v e="$ENTRY" -v s="New upstream release ${NEW_VERSION}, built and gated by pyindi-client-release.yml." '
    /^%changelog$/ && !d { print; print e; print "- " s; print ""; d=1; next } { print }
  ' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC"
  grep -qF "$ENTRY" "$SPEC" || die "%changelog entry was not inserted"
  say "PASS: %changelog entry added"
fi

# -------------------------------------------------------- deb changelog ----
if [ "$SPEC_ONLY" -eq 1 ]; then
  say "SKIP: --spec-only, deb changelog deliberately untouched"
  echo
  echo "############ BUMP COMPLETE (spec only): indi-stable-pyindi-client at ${NEW_VERSION}-${DEB_REV} ############"
  exit 0
fi

TOP=$(head -1 "$CHANGELOG")
case "$TOP" in
  *"(${NEW_VERSION}-${DEB_REV})"*)
    say "SKIP: deb changelog top entry is already ${NEW_VERSION}-${DEB_REV}" ;;
  *)
    dch --changelog "$CHANGELOG" --newversion "${NEW_VERSION}-${DEB_REV}" \
        --distribution unstable \
        "New upstream release ${NEW_VERSION}, built and gated by pyindi-client-release.yml" \
      || die "dch failed on $CHANGELOG"
    head -1 "$CHANGELOG" | grep -qF "(${NEW_VERSION}-${DEB_REV})" \
      || die "deb changelog top entry is not ${NEW_VERSION}-${DEB_REV} after dch"
    say "PASS: deb changelog -> ${NEW_VERSION}-${DEB_REV}" ;;
esac

echo
echo "############ BUMP COMPLETE: indi-stable-pyindi-client at ${NEW_VERSION}-${DEB_REV} ############"
exit 0
