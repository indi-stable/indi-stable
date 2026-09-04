#!/bin/bash
#
# Poll PyPI for a newer stable release of a package than the matching
# candidate in versions.json. Read-only, safe to run anytime -- locally for
# testing, or as the first job of a release workflow.
#
# pyindi-client does NOT use scripts/check-upstream-tag.sh: it releases on
# PyPI rather than as a git tag, so "what is the newest release" is a
# different question against a different API, with two failure modes the
# GitHub version simply does not have (see below). DESIGN.md, "`pyindi-client`
# -- packaging decisions", records why this project builds the PyPI sdist
# rather than a git tag at all.
#
# Run as: bash scripts/check-upstream-pypi.sh <pypi-name> <versions-key>
#   e.g.  bash scripts/check-upstream-pypi.sh pyindi-client pyindi-client
#
# On finding something newer, emits to $GITHUB_OUTPUT (when set) and stdout:
#   new_version, sdist_url, sdist_sha256
# The URL and hash are emitted here rather than re-derived later because a
# PyPI sdist URL contains a content-addressed path segment
# (.../packages/55/92/bbde78.../pyindi_client-2.2.0.tar.gz) that is NOT
# derivable from the version -- so whatever consumes this must be told the
# URL, not construct it. Informational lines go to stderr.
#
set -u

PKG=${1:?usage: check-upstream-pypi.sh <pypi-name> <versions-key>}
KEY=${2:?usage: check-upstream-pypi.sh <pypi-name> <versions-key>}
VERSIONS_FILE="${VERSIONS_FILE:-$(cd "$(dirname "$0")/.." && pwd)/versions.json}"

command -v jq >/dev/null 2>&1   || { echo "ERROR: jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required" >&2; exit 1; }
test -f "$VERSIONS_FILE" || { echo "ERROR: $VERSIONS_FILE not found" >&2; exit 1; }

CURRENT=$(jq -r --arg k "$KEY" '.[$k].candidate' "$VERSIONS_FILE")
[ -n "$CURRENT" ] && [ "$CURRENT" != "null" ] \
  || { echo "ERROR: could not read .${KEY}.candidate from $VERSIONS_FILE" >&2; exit 1; }

JSON=$(curl -fsSL "https://pypi.org/pypi/${PKG}/json") \
  || { echo "ERROR: could not fetch PyPI metadata for ${PKG}" >&2; exit 1; }

# Candidate releases, newest last. Three filters, each guarding a real
# failure mode rather than being defensive in the abstract:
#
#  1. SHAPE -- only X.Y.Z(.W). PyPI versions may carry rc/b/a/.postN/.devN
#     suffixes, which are not stable releases. .info.version is deliberately
#     NOT trusted for this: it reflects PyPI's own notion of "latest", which
#     this project's versioning policy does not define.
#  2. NOT YANKED -- PyPI lets a maintainer yank a release in place, something
#     a git tag cannot do. Promoting a yanked release would ship a build
#     upstream has withdrawn.
#  3. HAS AN SDIST -- this packaging builds from source. A release published
#     as wheels only would satisfy every version check and then fail at
#     download time, which is the worst place to find out.
LATEST=$(printf '%s' "$JSON" | jq -r '
  .releases
  | to_entries[]
  | select(.key | test("^[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))
  | select([.value[] | select(.packagetype=="sdist" and .yanked==false)] | length > 0)
  | .key' | sort -V | tail -1)

[ -n "$LATEST" ] || { echo "ERROR: no stable, non-yanked, sdist-bearing release found for ${PKG} -- upstream's publishing changed, or the API call failed" >&2; exit 1; }

echo "component:         $KEY (PyPI: $PKG)" >&2
echo "current candidate: $CURRENT" >&2
echo "latest upstream:   $LATEST" >&2

NEW_VERSION=""
if [ "$LATEST" != "$CURRENT" ]; then
  # Confirm LATEST actually sorts newer, not merely different -- a yanked or
  # deleted release could otherwise drive this backwards.
  NEWEST=$(printf '%s\n%s\n' "$CURRENT" "$LATEST" | sort -V | tail -1)
  if [ "$NEWEST" = "$LATEST" ]; then
    echo "new version found: $LATEST" >&2
    NEW_VERSION="$LATEST"
  else
    echo "upstream's latest ($LATEST) does not sort newer than candidate ($CURRENT) -- not advancing" >&2
  fi
else
  echo "no new version" >&2
fi

SDIST_URL=""
SDIST_SHA=""
if [ -n "$NEW_VERSION" ]; then
  read -r SDIST_URL SDIST_SHA <<<"$(printf '%s' "$JSON" | jq -r --arg v "$NEW_VERSION" '
    .releases[$v][] | select(.packagetype=="sdist" and .yanked==false)
    | "\(.url) \(.digests.sha256)"' | head -1)"
  [ -n "$SDIST_URL" ] && [ -n "$SDIST_SHA" ] \
    || { echo "ERROR: could not resolve an sdist URL and sha256 for ${PKG} ${NEW_VERSION}" >&2; exit 1; }
  echo "sdist url:         $SDIST_URL" >&2
  echo "sdist sha256:      $SDIST_SHA" >&2
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "new_version=$NEW_VERSION"
    echo "sdist_url=$SDIST_URL"
    echo "sdist_sha256=$SDIST_SHA"
  } >> "$GITHUB_OUTPUT"
fi
echo "$NEW_VERSION"
exit 0
