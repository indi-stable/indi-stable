#!/bin/bash
#
# Find driver-catalogue entries that name a binary the build will not install.
#
# This is the enforcement form of LESSONS_LEARNED.md #24. An indi_<x>.xml
# catalogue may list a <driver> whose binary is gated behind an upstream
# option that defaults off -- indi-eqmod's indi_ahpgt_telescope is the
# instance that cost real time. Left alone, such an entry survives our
# %install catalogue rewrite as a BARE name, and a bare name is what
# indiserver resolves through PATH. That makes it the one entry in our own
# catalogue capable of launching a DISTRIBUTION binary, which is precisely
# the coexistence guarantee this project exists to provide.
#
# Complements, and does not replace, scripts/test-catalogue-rewrite.sh:
#   - that one reads the BUILT artifact and asserts every path is absolute
#   - this one reads the UPSTREAM SOURCE and asks whether an entry should be
#     in the catalogue at all
# A driver whose catalogue names a binary we never build passes the first
# check (the rewrite leaves bare names alone precisely because it cannot
# know they are wrong) and fails this one. Run this BEFORE adding a driver
# to either packaging, while removing the entry is still a one-line patch.
#
# Read-only. Needs no root, builds nothing, touches nothing in the tree.
#
# Run as: bash scripts/check-catalogue-sources.sh <unpacked-indi-3rdparty> [driver-dir ...]
#   e.g.  bash scripts/check-catalogue-sources.sh ~/build/indi-3rdparty-2.2.4.1 indi-aok indi-ocs
#         bash scripts/check-catalogue-sources.sh ~/build/indi-3rdparty-2.2.4.1
#
# With no driver directories named it checks every indi-* directory present.
#
# WHY THIS IS PARSED AND NOT GREPPED, which was the first attempt and was
# wrong: a naive "is this target named in some install(TARGETS) line"
# comparison reports eqmod's own known-bad catalogue as clean, because the
# install() for indi_ahpgt_telescope IS present in indi-eqmod/CMakeLists.txt
# -- nested inside `if(WITH_AHP_GT)` and `if(AHP_GT_FOUND)`, both off. The
# gating is the whole point, so the if/endif stack has to be tracked. The
# control below plants exactly that shape and fails the script if it is not
# caught, so this cannot silently regress to the grep version.

set -euo pipefail

TREE="${1:-}"
if [ -z "$TREE" ] || [ ! -f "$TREE/CMakeLists.txt" ]; then
    echo "usage: bash scripts/check-catalogue-sources.sh <unpacked-indi-3rdparty> [driver-dir ...]" >&2
    echo "  (needs a directory containing indi-3rdparty's own top-level CMakeLists.txt)" >&2
    exit 2
fi
shift || true

SCAN_PY="$(cat <<'PYSCAN'

import os, re, glob, sys

tree = sys.argv[1]
dirs = sys.argv[2:]
if not dirs:
    dirs = sorted(d for d in os.listdir(tree)
                  if d.startswith("indi-")
                  and os.path.isfile(os.path.join(tree, d, "CMakeLists.txt")))

def installed_targets(path):
    """install(TARGETS ...) split into unconditional and gated, tracking if/endif.

    Also counts names created as symlinks. Several drivers ship extra driver
    names as symlinks to one binary rather than as targets of their own --
    indi-mi's four _usb/_eth aliases and indi-gphoto's five camera-brand
    aliases -- written by create_symlink inside a generated POST_INSTALL_SCRIPT.
    Those catalogue entries are correct and must not be reported.
    """
    uncond, cond, stack = set(), {}, []
    body = open(path, encoding="utf-8", errors="replace").read()
    for ln in body.splitlines():
        s = ln.strip()
        if re.match(r"^if\s*\(", s, re.I):
            g = re.search(r"if\s*\(\s*([^)]*)", s, re.I)
            stack.append(g.group(1).strip() if g else "?")
        elif re.match(r"^endif", s, re.I):
            if stack: stack.pop()
        elif re.match(r"^else\b", s, re.I):
            if stack: stack[-1] = "NOT " + stack[-1]
        m = re.search(r"install\s*\(\s*TARGETS\s+(.*)", s, re.I)
        if m:
            for t in m.group(1).split():
                if t.upper() in ("RUNTIME", "DESTINATION", "LIBRARY", "ARCHIVE"): break
                t = t.rstrip(")")
                if not t: continue
                if stack: cond[t] = list(stack)
                else: uncond.add(t)
    # create_symlink <existing> <path/to/newname>  -- take the basename created.
    # The destination is written unexpanded, e.g.
    #   create_symlink indi_mi_ccd \$ENV{DESTDIR}${CMAKE_INSTALL_FULL_BINDIR}/indi_mi_ccd_usb)
    # so the pattern must accept backslashes and ${...} and stop at the paren.
    # An earlier version excluded backslash, matched nothing, and reported all
    # nine of these aliases as dangling -- which is what the second control
    # below now prevents.
    for m in re.finditer(r"create_symlink\s+\S+\s+([^\s)]+)", body):
        name = os.path.basename(m.group(1))
        if name:
            uncond.add(name)
    return uncond, cond


# Gates that are always satisfied in this project's own builds, so an entry
# behind one of them is NOT dangling here. Each is asserted by something the
# packaging already guarantees, not assumed:
#   CFITSIO/ZLIB/NOVA/USB1_FOUND -- BuildRequires in both packagings; a build
#     with these missing fails at configure long before the catalogue matters
#   the APPLE arm64 gate -- this project builds x86_64 Linux only
ALWAYS_TRUE = re.compile(
    r"^(CFITSIO_FOUND|ZLIB_FOUND|NOVA_FOUND|USB1_FOUND|INDI_FOUND"
    r"|NOT\s*\(?\s*APPLE\b.*)$", re.I)

findings = 0
checked = 0
for d in dirs:
    dd = os.path.join(tree, d)
    cml = os.path.join(dd, "CMakeLists.txt")
    if not os.path.isfile(cml): continue
    uncond, cond = installed_targets(cml)
    for tmpl in sorted(glob.glob(os.path.join(dd, "*.xml.cmake"))) + \
                sorted(glob.glob(os.path.join(dd, "*.xml"))):
        body = open(tmpl, encoding="utf-8", errors="replace").read()
        entries = [x.strip() for x in
                   re.findall(r"<driver\b[^>]*>([^<]*)</driver>", body) if x.strip()]
        # @FOO@ is a configure-time substitution, not a literal driver name
        entries = [e for e in entries if "@" not in e]
        if not entries: continue
        checked += 1
        hard, soft = [], []
        for e in sorted(set(entries)):
            if e in uncond:
                continue
            if e in cond:
                gates = cond[e]
                if all(ALWAYS_TRUE.match(g) for g in gates):
                    continue          # gate always holds in our build
                soft.append((e, " AND ".join(gates)))
            else:
                hard.append(e)
        if hard or soft:
            findings += 1
            print("  DANGLING: %s/%s" % (d, os.path.basename(tmpl)))
            for e in hard:
                print("      <driver>%s</driver> -- no install() and no symlink anywhere" % e)
            for e, g in soft:
                print("      <driver>%s</driver> -- gated by %s" % (e, g))
print("__CHECKED__=%d" % checked)
print("__FINDINGS__=%d" % findings)
PYSCAN
)"

# ---------------------------------------------------------------- CONTROL
# Plant a catalogue naming a target whose install() is real but gated off,
# and require it to be found. Without this the script could pass by parsing
# nothing at all -- LESSONS_LEARNED.md #1.
CTL="$(mktemp -d)"
trap 'rm -rf "$CTL"' EXIT
mkdir -p "$CTL/indi-control"
touch "$CTL/CMakeLists.txt"
cat > "$CTL/indi-control/CMakeLists.txt" <<'CTLEOF'
add_executable(indi_real_driver real.cpp)
install(TARGETS indi_real_driver RUNTIME DESTINATION bin)
option(WITH_GATED "gated off by default" OFF)
if(WITH_GATED)
    if(GATED_FOUND)
        add_executable(indi_gated_driver gated.cpp)
        install(TARGETS indi_gated_driver RUNTIME DESTINATION bin)
    endif(GATED_FOUND)
endif(WITH_GATED)
CTLEOF
cat > "$CTL/indi-control/indi_control.xml.cmake" <<'CTLEOF'
<driversList>
  <devGroup group="Telescopes">
    <device label="Real"><driver name="Real">indi_real_driver</driver></device>
    <device label="Gated"><driver name="Gated">indi_gated_driver</driver></device>
  </devGroup>
</driversList>
CTLEOF

echo "--- CONTROL: a gated-off driver in a catalogue must be reported ---"
ctl_out="$(python3 -c "$SCAN_PY" "$CTL" indi-control)"
if ! grep -q "indi_gated_driver" <<<"$ctl_out"; then
    echo "$ctl_out"
    echo "CONTROL FAILED: the planted gated-off catalogue entry was NOT reported." >&2
    echo "  This script cannot be trusted -- it has regressed to a plain grep." >&2
    exit 1
fi
if ! grep -q "gated by WITH_GATED AND GATED_FOUND" <<<"$ctl_out"; then
    echo "$ctl_out"
    echo "CONTROL FAILED: found the entry but not the gate that hides it." >&2
    exit 1
fi
if grep -q "indi_real_driver" <<<"$ctl_out"; then
    echo "$ctl_out"
    echo "CONTROL FAILED: an unconditionally installed driver was flagged." >&2
    echo "  A check that flags everything is as useless as one that flags nothing." >&2
    exit 1
fi
echo "  CONTROL: planted gated-off entry reported, with its gate named"
echo "  CONTROL: unconditionally installed entry NOT flagged"

# Second control: a driver name that exists ONLY as a create_symlink alias,
# written the way upstream actually writes it -- unexpanded, backslash first.
# The first version of this script excluded backslashes from the destination
# pattern, matched nothing, and reported all nine real aliases in indi-mi and
# indi-gphoto as dangling. A false positive here is not harmless: it would
# have had us strip working drivers out of two catalogues.
mkdir -p "$CTL/indi-symlink"
cat > "$CTL/indi-symlink/CMakeLists.txt" <<'CTLEOF'
add_executable(indi_base_ccd base.cpp)
install(TARGETS indi_base_ccd RUNTIME DESTINATION bin)
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/make_symlink.cmake
"execute_process(COMMAND \"${CMAKE_COMMAND}\" -E create_symlink indi_base_ccd \$ENV{DESTDIR}${CMAKE_INSTALL_FULL_BINDIR}/indi_alias_ccd)\n")
CTLEOF
cat > "$CTL/indi-symlink/indi_symlink.xml.cmake" <<'CTLEOF'
<driversList>
  <devGroup group="CCDs">
    <device label="Base"><driver name="Base">indi_base_ccd</driver></device>
    <device label="Alias"><driver name="Alias">indi_alias_ccd</driver></device>
  </devGroup>
</driversList>
CTLEOF
sym_out="$(python3 -c "$SCAN_PY" "$CTL" indi-symlink)"
if grep -q "indi_alias_ccd" <<<"$sym_out"; then
    echo "$sym_out"
    echo "CONTROL FAILED: a real create_symlink alias was reported as dangling." >&2
    echo "  Stripping it from a catalogue would remove a working driver." >&2
    exit 1
fi
echo "  CONTROL: create_symlink alias recognised, NOT flagged"
echo

# ------------------------------------------------------------------ SCAN
echo "--- SCANNING $TREE ---"
out="$(python3 -c "$SCAN_PY" "$TREE" "$@")"
checked="$(sed -n 's/^__CHECKED__=//p' <<<"$out")"
findings="$(sed -n 's/^__FINDINGS__=//p' <<<"$out")"
grep -v '^__' <<<"$out" || true

if [ "${checked:-0}" -eq 0 ]; then
    echo
    echo "NOTHING WAS CHECKED -- no catalogue templates found." >&2
    echo "  Passing here would mean nothing; treat this as a failure." >&2
    exit 1
fi

echo
echo "==================================================================="
if [ "${findings:-0}" -eq 0 ]; then
    echo "CATALOGUES CLEAN: $checked catalogue(s) checked, every <driver>"
    echo "  entry names a binary this build installs unconditionally."
else
    echo "$findings catalogue(s) name a driver this build will NOT install,"
    echo "  out of $checked checked. Strip the <device> block in BOTH"
    echo "  packagings before shipping the driver -- see LESSONS_LEARNED.md #24."
fi
echo "==================================================================="
[ "${findings:-0}" -eq 0 ]
