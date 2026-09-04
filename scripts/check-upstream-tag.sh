#!/bin/bash
#
# Poll a GitHub repository's own tags for a newer stable release than the
# matching candidate in versions.json. Read-only, safe to run anytime --
# locally for testing, or as the first job of a release workflow.
#
# Generalized from the core-only original (scripts/check-upstream-core.sh
# until 2026-09-04) when the same gate was extended to indi-3rdparty: the
# repository and the versions.json key were the only component-specific
# parts, so they became arguments rather than a second near-identical copy
# of this logic. pyindi-client does NOT use this script -- it releases on
# PyPI, not as a GitHub tag, so it needs a genuinely different check.
#
# "Stable" per DESIGN.md's versioning policy means a real vX.Y.Z(.W) tag,
# not git master and not an rc/beta/alpha -- filtered here by shape, not
# trusted from the API's own ordering (GitHub does not guarantee tags are
# returned newest-first).
#
# Run as: bash scripts/check-upstream-tag.sh <github-repo> <versions-key>
#   e.g.  bash scripts/check-upstream-tag.sh indilib/indi           core
#         bash scripts/check-upstream-tag.sh indilib/indi-3rdparty  3rdparty
#
# Emits `new_tag=<tag>` to $GITHUB_OUTPUT when running under GitHub Actions
# (GITHUB_OUTPUT set in the environment); always prints the result (empty
# string if nothing new) to stdout either way, so it composes in a shell
# pipeline too. Informational lines go to stderr, keeping stdout clean for
# `NEW=$(bash scripts/check-upstream-tag.sh ...)`.
#
set -u

REPO=${1:?usage: check-upstream-tag.sh <github-repo> <versions-key>}
KEY=${2:?usage: check-upstream-tag.sh <github-repo> <versions-key>}
VERSIONS_FILE="${VERSIONS_FILE:-$(cd "$(dirname "$0")/.." && pwd)/versions.json}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh (GitHub CLI) is required" >&2; exit 1; }
test -f "$VERSIONS_FILE" || { echo "ERROR: $VERSIONS_FILE not found" >&2; exit 1; }

# --arg, not a literal .${KEY} path: "3rdparty" starts with a digit, which
# is a jq SYNTAX ERROR as a bare path (.3rdparty -> "unexpected IDENT"), not
# a lookup that merely returns null. Confirmed by running it, 2026-09-04,
# before this script was ever wired to a workflow -- the bare-path form
# would have failed the 3rdparty gate on its very first run.
CURRENT=$(jq -r --arg k "$KEY" '.[$k].candidate' "$VERSIONS_FILE")
[ -n "$CURRENT" ] && [ "$CURRENT" != "null" ] \
  || { echo "ERROR: could not read .${KEY}.candidate from $VERSIONS_FILE" >&2; exit 1; }

# Only real vX.Y.Z(.W) release tags -- excludes rc/beta/alpha suffixes and
# anything else not shaped like a stable release.
LATEST=$(gh api "repos/${REPO}/tags" --paginate -q '.[].name' 2>/dev/null \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$' \
  | sort -V \
  | tail -1)

[ -n "$LATEST" ] || { echo "ERROR: could not find any vX.Y.Z-shaped tag in ${REPO} -- API call failed or upstream's tagging changed" >&2; exit 1; }

echo "component:         $KEY ($REPO)" >&2
echo "current candidate: $CURRENT" >&2
echo "latest upstream:   $LATEST" >&2

NEW_TAG=""
if [ "$LATEST" != "$CURRENT" ]; then
  # Confirm LATEST actually sorts newer than CURRENT, not just different --
  # a deleted/retagged release could otherwise fire this backwards.
  NEWEST=$(printf '%s\n%s\n' "$CURRENT" "$LATEST" | sort -V | tail -1)
  if [ "$NEWEST" = "$LATEST" ]; then
    echo "new tag found: $LATEST" >&2
    NEW_TAG="$LATEST"
  else
    echo "upstream's latest ($LATEST) does not sort newer than candidate ($CURRENT) -- not advancing" >&2
  fi
else
  echo "no new tag" >&2
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "new_tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
fi
echo "$NEW_TAG"
exit 0
