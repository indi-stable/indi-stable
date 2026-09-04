#!/bin/bash
#
# Read a spec's CURRENT Version: and Release: and emit the version unchanged
# plus the NEXT release number. This is what a repackage needs: same upstream
# source, new release, because the packaging changed and upstream did not.
#
# Run as: bash scripts/next-release.sh <spec-path>
#
# Emits to $GITHUB_OUTPUT (when set) and stdout:
#   version=<current version, verbatim -- no leading v is added or removed>
#   release=<current release + 1>
#
# Exists as a script rather than six lines inlined into three workflows for
# the reason this repo keeps rediscovering: parallel copies drift, and the
# copies that drift are the ones nobody can test. The RPM/Debian halves of
# the %changelog guard were written minutes apart and only one was right
# (see 9676c74). This one can be run and controlled on a laptop.
#
# The version is emitted VERBATIM. core and 3rdparty carry a leading v on
# their upstream tags and pyindi-client does not, so adding or stripping one
# here would be wrong for someone; each workflow forms the tag it needs.
#
set -u

SPEC=${1:?usage: next-release.sh <spec-path>}
test -f "$SPEC" || { echo "ERROR: $SPEC not found" >&2; exit 1; }

VERSION=$(sed -n 's/^Version:[[:space:]]*\(.*\)$/\1/p' "$SPEC" | head -1)
[ -n "$VERSION" ] || { echo "ERROR: could not read Version: from $SPEC" >&2; exit 1; }

# The numeric prefix of Release:, which is "1" in "1%{?dist}". A Release:
# that does not START with a number -- a macro, a snapshot string -- cannot
# be incremented, and guessing would produce a package whose NVR does not
# sort the way anyone expects. Better to stop.
RELEASE=$(sed -n 's/^Release:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "$SPEC" | head -1)
[ -n "$RELEASE" ] || { echo "ERROR: Release: in $SPEC does not begin with a number -- cannot compute the next one" >&2; exit 1; }

NEXT=$((RELEASE + 1))

echo "spec:            $SPEC" >&2
echo "current:         ${VERSION}-${RELEASE}" >&2
echo "next release:    ${VERSION}-${NEXT}" >&2

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=$VERSION"
    echo "release=$NEXT"
  } >> "$GITHUB_OUTPUT"
fi
echo "version=$VERSION"
echo "release=$NEXT"
exit 0
