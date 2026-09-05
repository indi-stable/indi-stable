# Status — outstanding work and machine state

**The living document. Read this first, every session.**

Two rules keep it living rather than growing:

- **Completed items are deleted, not annotated.** Git holds the record; a
  document full of struck-through history is the thing this file exists to
  avoid. The commit that finished the work is where the evidence lives.
- **Nothing here explains *why*.** Rationale is `DESIGN.md`, procedure is
  `FEDORA.md` / `DEBIAN.md`, gotchas are `LESSONS_LEARNED.md`. This file says
  only what is left and what state the machines are in.

---

## Where the project is

| | |
|---|---|
| **Fedora `core/`** | **Testing complete.** Built, installed, coexisting (runtime, metadata, `-devel`, and Ekos in *both* the opt-in and bystander cases), upgraded and removed — all verified, and the whole suite re-run green on 2026-08-26. The one item left is release tooling, not a test. |
| **Debian `core/`** | **Testing complete.** Built, installed, coexisting (runtime, metadata, `-dev`), upgraded and removed — verified in **configuration B**, against a distribution INDI carrying the same SONAME and the same upstream release, and now scripted as four harnesses in `scripts/`. Nothing outstanding is a test. |
| **`3rdparty/`** | RPM and Debian sides both complete for both source packages, all three verified together (`indi-stable-core`, `-3rdparty-libs`, `-3rdparty-drivers`), on both distros. 9 vendors. **A serious defect was found and fixed 2026-09-04 that all of the earlier verification had missed: 45 of 56 driver binaries could not load on a runtime-only install**, because 17 vendor blobs carry an unversioned SONAME and their bare `.so` symlink was shipped in `-devel`/`-dev` rather than the runtime package (`LESSONS_LEARNED.md` #22). Fixed and re-verified on both distros — see the dated section below. See "3rdparty — remaining" for what is still genuinely open (QSI stays excluded for a confirmed reason; `flipro`/`flialgo` licence coverage; non-blob drivers). |
| **`pyindi-client/`** | Both sides built, installed, imported for real, and coexistence/upgrade-tested via scripted harnesses: Debian 2026-08-26/27 (`pyindi-client/deb/`), RPM 2026-08-27 (`pyindi-client/rpm/`). Release automation added 2026-09-04, including a smoke check that every symbol the SWIG wrapper references is actually exported — the `DESIGN.md` 2026-09-03 incident's failure mode, which `import PyIndi` and `BaseClient()` both survive. Nothing outstanding on the packaging itself. |
| **CI (all three)** | **Verified end to end ON THIS REPO, 2026-09-04**, not just inherited from the seed's own history. Core, 3rdparty and pyindi-client each ran a real (not dry-run) check → build → smoke-test → promote cycle here for the first time, each publishing a real GitHub Release and pushing a real promotion commit: `indi-stable-core-v2.2.4.2` (6 assets), `indi-stable-3rdparty-v2.2.4.1` (54 assets, at a clean `Release: 1` — see below for why that needed a real fix first), `indi-stable-pyindi-client-2.2.0` (2 assets, symbol-check counts 1172/1199 confirmed substantive, not vacuous). All three promote jobs now create the GitHub Release **before** committing the version bump (`53cef94`) — closing a real, if narrow, window where a downstream workflow reading `versions.json` could see a release referenced before it existed; confirmed on this run by the release's `publishedAt` and the promote commit's own timestamp landing in the same second, not by trusting the reorder alone. |
| **3rdparty's first real run here failed, and the cause was worth finding.** The fresh-history seed carried over the archived repo's already-bumped state (`Release: 2%{?dist}`, changelogs and all 18 control pins at `-2` — leftover from a repackage test run there). This repo's own release history starts fresh, so the first real promotion attempt collided: Debian's `dch` correctly refused to write a lower version than what its changelog already claimed, but the RPM side's plain `sed` had no equivalent check and **silently regressed `Release: 2` back down to `1`**, reporting success. Fixed in two parts, `01b52b9`: the seed's phantom `-2` content reset to a clean `-1` (nothing describing that content ever actually shipped from this repo), and all three bump scripts hardened to refuse moving RPM `Release:` backward for an unchanged upstream version, matching what `dch` already enforced on the Debian side. Re-run afterward: all 8 jobs passed. |

Work happens on `development`. Will merges to `main` himself, via PR.

**`main`, not `development`, is what every release workflow reads from and
publishes to, as of 2026-09-05.** Before that fix, `check`/`build-*`/
`smoke-test-*` used an unpinned `actions/checkout@v4`, which follows
whichever ref triggered the run — the default branch (`main`) on every
scheduled poll, but `development` on the `workflow_dispatch` runs that
happened to produce 2026-09-04's real first promotions. That split brain
went unnoticed until `main`'s now-stale `versions.json` candidates made
2026-09-05's scheduled polls re-detect core and 3rdparty as "new" and
rebuild them — failing harmlessly at `gh release create`, because those
releases already existed. Fixed by pinning every checkout to `ref: main`,
and by having `promote` open and self-merge a PR into `main` instead of
pushing to `development` (a plain push there was always incidental —
`main`'s protection blocks direct pushes outright, but never required the
target to be `development`; `required_approving_review_count: 0` is what
makes the bot's self-merge possible without weakening the "no direct
pushes" guarantee). `development` remains where hand-authored packaging
changes are made, and is fast-forwarded from `main` at the end of each
promotion job so it never lags behind main's own bumps.

**This is now the primary repo, as of 2026-09-04.** It began as a
fresh-history import of `indi-stable/packaging`'s `main` at `c22b7db` (see
this repo's own first commit, "Initial public import," for the full
reasoning and exact content differences from that repo). `indi-stable/packaging`
is retired to historical-reference-only — check there, not here, for "why"
questions about anything predating this repo's first commit; its commit
messages and `LESSONS_LEARNED.md` carry evidence this repo's shorter
history does not.

`main` is protected by real GitHub branch protection, not convention
alone: a pull request is required to merge, `enforce_admins` is on, and
force-pushes/deletion are disabled. Confirmed by testing, not just reading
the settings back — a direct push to `main` was rejected with GitHub's own
`GH006` error before this was trusted.

**Switching machines?** The clone on the box you are moving *to* will be behind
— `git pull` on `development` first. Both clones were in sync at the end of
2026-08-26. Two per-clone git settings, both already applied on both clones —
re-apply them on any new one, because neither travels with a `git clone`:

```bash
git config user.email william@williamlsnyder.org   # commit authorship
git config core.hooksPath .githooks                # or the pre-commit hook is inert
```

---

## 3rdparty — remaining, and where the next session starts

**`core/rpm/indi-stable-3rdparty-libs.spec` builds cleanly through `mock` as of
2026-08-26** on `fedoraastro` (`fedora-44-x86_64`, 1m27s warm-chroot,
`--no-clean` after installing `indi-stable-core`/`-libs`/`-devel` into the
chroot with `mock --install` since there is no repo to resolve that
`BuildRequires` from). All 8 vendor subpackages (+ `-devel`) came out:
apogee, asi, fli, inovasdk, micam, playerone, sbig, touptek. RPMs are in
`~/mock-result-3rdparty` on `fedoraastro`. Spot-checked directly against the
built RPMs (not yet through the full harness core got): everything stays
under `/opt/indi-stable` except udev rules/licenses/debuginfo, nothing under
`/usr/bin`, RPATH is set (`check-rpaths` WARNING 0002 on three libraries is
the downgrade firing as designed, not a failure).

**Seven real defects were found and fixed across the build and the first real
install/coexistence pass** — the project's own track record predicted
something would be wrong, and it was, several times over. Five surfaced from
the build itself:

1. `WITH_QSI` and `WITH_FISHCAMP` (both default `On` upstream) were missed by
   the original licence-tier survey entirely — no `%package`, no licence
   read, no mention in `DESIGN.md`. `WITH_QSI` failed configure outright
   (`libftdi1-devel` missing); `WITH_FISHCAMP` would have built and shipped
   an unaudited vendor SDK silently if rpmbuild's own unpackaged-file check
   hadn't caught it. Both now `OFF`, same tier as the other five.
2. `%license apogee-3.2/LICENSE` named a directory that doesn't exist — the
   real path is `libapogee/LICENSE`.
3. Apogee's 399 per-camera-model config files (`etc/Apogee/camera/*.txt`)
   were entirely missing from `%files apogee`.
4. `libasi`'s `USB2ST4Conv` target is real (an earlier reading of
   `libasi/CMakeLists.txt` concluded it wasn't) — added to `%files asi`,
   confirmed to share `libasi`'s single top-level `license.txt` with the
   four targets already bundled.
5. `flipro`/`flialgo` were being installed by `%cmake_install` but never
   actually deleted from the buildroot — omission from `%files` alone isn't
   enough; `%install` now `rm`s them explicitly.

**Installed and removed together with `indi-stable-core` on `fedoraastro`,
2026-08-26 — the first time core and 3rdparty-libs have ever been combined.**
Two more real defects surfaced only from that combination, neither visible
from the build or from either package installed alone:

6. Every `-devel` subpackage's auto-generated `Requires` on its own vendor's
   unversioned `.so` symlink (e.g. `libapogee.so.3()(64bit)`) was
   unsatisfiable, because `__provides_exclude_from` had already stripped the
   matching `Provides` from the runtime package — the exact bug core's own
   spec comment warns about, just missed here because the check that was
   actually run (libindi linkage) answered a different question. Fixed with
   a `__requires_exclude` enumerating every bundled vendor SONAME stem, same
   as core already has for `libindi*`. See `LESSONS_LEARNED.md` #21 for an
   unrelated but adjacent mistake made while re-testing this: installing the
   `.src.rpm` alongside the real RPMs installs its `BuildRequires` as
   `Requires`, pulling ~40 toolchain packages onto the gcc-less snapshot;
   caught immediately and reversed with `dnf history undo` before it was
   mistaken for a real result.
7. A full `dnf remove` of every package together left `/opt/indi-stable` and
   two subdirectories behind as empty directories, because directory
   ownership was split across packages inconsistently (only some declared
   `%dir`) — deterministic cleanup needs *every* package that places a file
   anywhere under a shared directory to also own that directory, not just
   the "primary" one. See `LESSONS_LEARNED.md` #20 for the full mechanism.
   Fixed; a full install→verify→remove cycle now restores `fedoraastro` to
   its exact baseline (2153 packages, `/opt/indi-stable` completely absent,
   not even empty) with `rpm -V` clean on `libindi`/`libindi-libs`/`kstars`
   and on our own packages, no `/usr/bin` escapes, and `Provides` still
   correctly package-name-only.

**Not yet done: any coexistence check against a distribution 3rdparty
package** — moot on `fedoraastro` specifically, since Fedora 44 ships none
(see `DESIGN.md`, "Resolution — two source packages, not one and not
sixty-one"). The install/removal round-trip verified
here is against distribution **core** INDI (`libindi`/`libindi-libs`/`kstars`)
only, which is the coexistence guarantee this project actually promises.

**Upgrade path also verified, 2026-08-26, `scripts/test-upgrade-path-3rdparty.sh`.**
Unlike core's upgrade test (which exists for a `%postun` scriptlet-ordering
bug), 3rdparty-libs has no scriptlets at all, so this one instead tests
upgrading 3rdparty-libs alone while `indi-stable-core` stays installed and
untouched — the real risk for two independent source packages sharing
`/opt/indi-stable` — plus file-replacement correctness (no orphaned files
left behind, with a planted-file control proving that check can find
something) and that the upgraded libraries still resolve and run. All checks
passed on the first run against a scratch `Release: 2%{?dist}` build (same
"bump Release in an uncommitted scratch copy" trick as core's own upgrade
test); `fedoraastro` re-verified back at exact baseline afterward (2153
packages, no `gcc`, `/opt/indi-stable` absent).

## `indi-stable-3rdparty-drivers` — builds, installs and removes cleanly

**`core/rpm/indi-stable-3rdparty-drivers.spec` builds cleanly through mock as
of 2026-08-26**, scoped to the SAME 8 vendors `-libs` bundles (apogee, asi,
fli, playerone, inovasdk, micam, sbig, touptek) and no others — see
`DESIGN.md`'s "Resolution — two source packages" for the shape. RPMs are in
`~/mock-result-drivers` on `fedoraastro`. Spot-checked directly against the
built RPMs (file placement, `Requires`/`Provides`, driver-catalogue rewrite,
RPATH) for apogee and touptek (the simplest and the most complex case).

**Installed and removed on the host itself, same day, alongside
`indi-stable-core` and `indi-stable-3rdparty-libs` together** — all three
source packages, 27 subpackages, in one transaction. Unlike `-libs`'s own
first coexistence pass, this one found **no new defects**: the fixes already
made for `-libs` (the `__requires_exclude` union of core's and -libs's own
patterns, and universal `%dir` ownership of every shared directory,
`LESSONS_LEARNED.md` #20) held on the first try even with a third source
package added to the mix. Verified beyond what RPM metadata alone can show:
`ldd` on an actually-installed `indi_apogee_ccd` resolves all four private-
prefix libraries (`libindidriver.so.2`, `libindiAlignmentDriver.so.2`,
`libindiclient.so.2`, `libapogee.so.3`) to `/opt/indi-stable/lib`, none of
them to a distro copy or "not found"; the binary runs and prints its usage
banner rather than dying at dynamic-link time. Distro core INDI
(`libindi`/`libindi-libs`/`kstars`) `rpm -V` clean and `/usr/bin/indiserver`
hash unchanged throughout. Full removal restores `fedoraastro` to its exact
baseline: 2153 packages, `/opt/indi-stable` completely absent (not even an
empty directory, across all three source packages' worth of shared
`%dir` declarations), only the distribution's own `99-indi_auxiliary.rules`
left in `/usr/lib/udev/rules.d`.

**Upgrade path also verified, 2026-08-26,
`scripts/test-upgrade-path-drivers.sh`.** Run together with `-libs`'s own
upgrade rather than standalone, because that is the only upgrade this
project's release process can actually produce — the two share one upstream
tag and `-drivers` pins its `BuildRequires` to `-libs`'s exact
`%{version}-%{release}`, not just its Version. `indi-stable-core` stayed
outside the upgrade transaction throughout (its own independent version
axis) and its NVR and `rpm -V` were both confirmed unaffected. All checks
passed on the first run against a scratch `Release: 2%{?dist}` build of
*both* packages (same uncommitted-scratch-copy trick as `-libs`'s and
core's own upgrade tests — the drivers scratch build had to be built
against the libs scratch build's `-devel` RPMs, not the repo's `Release: 1`
ones, for the pinned `BuildRequires` to resolve at all). No orphaned files
after the upgrade (with a planted-file control proving that check can find
something), and — the strongest check available, per this section's own
coexistence pass above — `indi_apogee_ccd` still resolves all its private-
prefix libraries and actually runs, prints its usage banner, after the
upgrade. `fedoraastro` re-verified back at exact baseline afterward (2153
packages, no `gcc`, `/opt/indi-stable` absent).

**Six real build failures on the way there, all found by reading what
`rpmbuild`/`mock` actually said (LESSONS_LEARNED.md #1/#2), not by
predicting them:**

1. `-DBUILD_LIBS=OFF` configures indi-3rdparty's FULL ~65-driver tree by
   default, unlike `-DBUILD_LIBS=ON` (`-libs`'s own build), which only ever
   touches vendors with an actual `lib*` blob directory. The first attempt
   configured straight into `indi-ticfocuser-ng` (needing libnova, FFmpeg,
   libudev, Qt, yaml, Bluetooth — none of them anywhere near this project's
   scope). Fixed with 47 `-DWITH_<X>=OFF` overrides, generated by diffing
   the complete `option(WITH_...)` list against the 18 flags actually
   wanted on, not hand-picked.
2. `omegonprocam_test.cpp` and `toupcam_test.cpp` (vendor SDK diagnostic
   tools, not INDI drivers, no `install()` rule for either) fail to compile
   / are irrelevant, but ninja builds cmake's default "all" target
   regardless of whether anything installs the result. Excluded from the
   default build via `EXCLUDE_FROM_ALL` rather than deleting the
   `add_executable()` blocks (fragile against the multi-line
   `target_link_libraries()` calls that follow them).
3. That same `EXCLUDE_FROM_ALL` patch's first version anchored its `sed`
   match to column 1 (`^add_executable(...`) and silently matched nothing —
   both `add_executable()` lines are indented 2 spaces, inside their
   `if(WITH_<BRAND>CAM)` blocks. Caught immediately by the very next build
   failing on the exact same line.
4. `indi-apogee/apogee_ccd.cpp` mixes `#include "Alta.h"` (unqualified,
   resolved fine by `APOGEE_INCLUDE_DIR` itself) and
   `#include <libapogee/Alta.h>` (qualified, needs the PARENT directory on
   the search path instead) for the SAME header. Fixed by appending
   `-I%{indi_includedir}` to `CFLAGS`/`CXXFLAGS` globally rather than
   patching the one file, since the same upstream inconsistency is
   plausible elsewhere.
5. `indi-mi` installs two real binaries (`indi_mi_ccd`, `indi_mi_sfw`) AND
   four `install(CODE ...)`-created symlinks to them (`indi_mi_ccd_usb`,
   `indi_mi_ccd_eth`, `indi_mi_sfw_usb`, `indi_mi_sfw_eth`) — missed by the
   `add_executable()`-only survey this spec's `%files` was first drafted
   from, since the symlinks are never their own `add_executable()` target.
   The other 7 vendor driver directories were checked directly and have no
   equivalent pattern.

Verified directly against the built RPMs: everything stays under
`/opt/indi-stable` except licenses/debuginfo, nothing under `/usr/bin`, the
driver-catalogue rewrite (absolute paths, not bare names — same mechanism as
core's own `%install`, generalized to loop over every `indi_<vendor>.xml`
this package installs rather than one shared `drivers.xml`) lands correctly,
RPATH is set, and `Requires`/`Provides` are clean (package-name `Requires`
on both `indi-stable-3rdparty-libs-<vendor>` (version-pinned, same tag) and
`indi-stable-core-libs` (unversioned — independent version axis), no leaked
vendor or `libindi*` SONAME `Requires`).

## `indi-stable-3rdparty-libs` — Debian side, builds/installs/removes cleanly

**`core/deb-3rdparty-libs/` built, installed and removed cleanly on the
first real `dpkg-buildpackage`**, 2026-08-26, on `ubuntuastro` in
**configuration B** (PPA active, `libindi1` sharing SONAME *and* version
with ours — the tightest collision case). Unlike either RPM spec, no
build-time defects at all. Full detail — the two decisions made *before*
building that avoided the RPM side's empirical discoveries, the three
lintian overrides needed (all tied to vendor prebuilt blobs, not this
packaging), and the full verification checklist — is in `DEBIAN.md`,
"Building and testing `indi-stable-3rdparty-libs`". `ubuntuastro` re-
verified back at its documented configuration-B baseline afterward:
`/usr/bin/indiserver` hash unchanged, `dpkg -V` clean on `libindi1`/
`indi-bin`, and a full `dpkg -r` of all 16 packages (plus the
`indi-stable-core-dev`/`-libs` installed only to satisfy the
`Build-Depends`) left no vendor-named file under `/opt/indi-stable` and no
`*3rdparty*` udev rule anywhere.

**Upgrade path also verified, 2026-08-26,
`scripts/test-upgrade-path-3rdparty-deb.sh`.** No maintainer-script-ordering
class of bug here (`-libs` ships no `postinst`/`prerm` at all), so this
tests what actually matters: upgrading `-libs` alone while
`indi-stable-core` stays installed and untouched, no orphaned files (planted-
file control), and the upgraded libraries still resolve via `ldd`. One real
finding on the first run, fixed the same run: the script itself wrongly
asserted every vendor library carries a RUNPATH and failed on
`libtoupcam.so`, which genuinely needs none (`readelf -d` shows only
ordinary system-library `NEEDED` entries) — consistent with the RPM side's
own `check-rpaths` run, which already showed only 3 of the bundled libraries
ever carry RPATH. Not a packaging defect; the script's assumption was wrong,
not the package. Full detail in `DEBIAN.md`. `ubuntuastro` re-verified back
at exact baseline afterward.

The 16 built `.deb`s are in `~/build/` on `ubuntuastro` alongside core's own,
named `indi-stable-3rdparty-libs-<vendor>[-dev]_2.2.4.1-1_amd64.deb`.

## `indi-stable-3rdparty-drivers` — Debian side, builds/installs/removes cleanly

**`core/deb-3rdparty-drivers/` built, installed and removed cleanly on the
first real `dpkg-buildpackage`**, 2026-08-26 — no build-time defects at all,
unlike this same package's RPM equivalent, which took six real iterations.
Every fix that spec needed was already known and translated directly into
the Debian packaging before this package was ever built. Full detail —
including the real, more-nuanced-than-expected `shlibs.local` finding — is
in `DEBIAN.md`, "Building and testing `indi-stable-3rdparty-drivers`".

**The headline finding: `shlibs.local` only engages for libraries with a
real, numbered SONAME.** This IS the package `DESIGN.md`'s "The Debian half
of the metadata layer" predicted would need it (drivers link against BOTH
core's `libindi*` and a vendor library, neither shipping a `shlibs` file) —
but for the 17 vendor libraries with no SONAME at all (`asi`'s five
prebuilt ZWO blobs) or an unversioned one (`micam`'s and `touptek`'s
twelve), `dpkg-shlibdeps` warns `cannot extract name and version` and skips
them **before** ever consulting `shlibs.local` at all. The build did not
fail only because `core/deb-3rdparty-drivers/control`'s own `Depends:`
lines name `indi-stable-core-libs` and `indi-stable-3rdparty-libs-<vendor>`
literally, not through `${shlibs:Depends}` — that explicit pinning, not
`shlibs.local`, is what actually protects these 17 dependencies.

Verified against the built `.deb`s: file placement, driver-catalogue
rewrite (both the simplest case and touptek's 11-brand case), `Depends:`
correctness on all 8 packages (confirmed via `dpkg-deb -f`, not the build
log), and a clean `lintian --profile debian` needing no overrides beyond
the standard pair — unlike `-libs`, none of its vendor-blob-specific
findings apply to a binary that merely *links against* a blob rather than
embedding one.

**Installed, coexistence-verified and removed cleanly on `ubuntuastro` in
configuration B**, alongside `indi-stable-core` and `indi-stable-3rdparty-libs`
together: `ldd` on `indi_apogee_ccd` resolves all four private-prefix
libraries, the binary runs and prints its usage banner, distro core INDI
(`libindi1`/`indi-bin`, same SONAME and version as ours) stayed a clean
bystander (`dpkg -V` clean, `/usr/bin/indiserver` hash unchanged), and a
full `dpkg -r` of all three source packages' worth of binaries left
`/opt/indi-stable` completely gone. `ubuntuastro` re-verified back at its
exact Configuration B baseline (`dpkg-query -W`: 1829 packages — **not**
`dpkg -l | grep '^ii' | wc -l`, which undercounted by 3 during this
session's own verification and should not be trusted for this comparison).

**Upgrade path also verified, 2026-08-26,
`scripts/test-upgrade-path-drivers-deb.sh`.** Run together with `-libs`'s
own upgrade, same reason as the RPM version of this test: `-drivers` pins
its `Depends`/`Build-Depends` to `-libs`'s exact version. No new defects
found this run — every check passed on the first try, including the
strongest one available (`indi_apogee_ccd` still resolves via `ldd` **and
runs**, printing its usage banner, after the upgrade — the functional check
`-libs`'s own Debian upgrade test could not offer, since that package ships
no executables). `ubuntuastro` re-verified back at exact baseline
afterward. Full detail in `DEBIAN.md`.

**Coexistence is now scripted too, 2026-08-26,
`scripts/test-3rdparty-coexist-deb.sh`** — the Debian analogue of core's
`test-config-b-coexist.sh`, applied to `indi_apogee_ccd`. It found a real
collision Fedora cannot: Ubuntu's *archive* (not the PPA) ships `indi-apogee`
against `libapogee3t64`, whose `libapogee.so.3` is byte-identical in SONAME
to ours (confirmed with `readelf`, not the package name). That archive
package is orphaned the same way Fedora's `indi-3rdparty` is — installing it
would remove `indi-bin`/`libindi1` to satisfy its pin to the pre-PPA
`libindidriver1` — so the harness downloads and extracts it with
`apt-get download` + `dpkg-deb -x` rather than installing it, then forces
`LD_LIBRARY_PATH` at the extracted artifact as a positive control. All checks
passed on the first run: distro core INDI stayed a clean bystander with all
24 3rdparty packages installed, none of those 24 ship anything under
`/usr/bin` or `/usr/include`, `indi_apogee_ccd` maps its private-prefix
`libapogee.so.3` unforced and the real archive one when forced. `ubuntuastro`
re-verified back at exact baseline afterward. Full detail in `DEBIAN.md`.

### Genuinely open, not just untested

- **`libfli`'s `flipro`/`flialgo` licence coverage.** Still open, now more
  thoroughly checked, 2026-08-27: no licence file anywhere in `flipro/`, no
  copyright header in `libflipro.h`, and only one commit in indi-3rdparty's
  git history ever touched the path (upstream added it in 2025 "for
  Kepler", no licensing discussion). Upstream's own `debian/libfli/copyright`
  claims BSD for the whole package but is dated 2008 — 17 years before
  `flipro` was added — and was never updated to mention it. Settling this
  needs asking FLI or upstream directly; no amount of further reading in
  this repo will resolve it. See `DESIGN.md`, "QSI and Fishcamp resolved",
  for how the other two members of this same "never actually read" group
  were settled the same day.
- **The ~50 non-blob indi-3rdparty drivers (eqmod, gpsd, celestronaux,
  ticfocuser-ng, ...) are entirely out of scope for `-drivers` as written.**
  Deliberately not decided either way (confirmed with Will, 2026-08-26) — they
  need no vendor blob and have no dependency on `-libs` at all, so bundling
  them is a wholly separate question from everything this spec's own scope
  answers. The 46 `-DWITH_<X>=OFF` overrides in `%build` are what currently
  keeps them out; extending this package to cover any of them means editing
  that list deliberately, not something a future add_subdirectory() upstream
  adds should silently slip through.
- **The License: tag's precision is a defensible aggregate, not a full
  per-file audit** — read in `indi-stable-3rdparty-libs.spec`'s own header
  comment for exactly which licences were read in full text versus inferred,
  and where `-only` vs `-or-later` was assumed rather than confirmed against
  source file headers.

## Fishcamp added to `3rdparty` — 9 vendors now, both distros, verified 2026-08-27

QSI and Fishcamp's licences were both read in full, resolving in opposite
directions (`DESIGN.md`, "QSI and Fishcamp resolved"): QSI's own
`libqsi/COPYING` explicitly forbids redistribution without written
permission, so `WITH_QSI=OFF` stays, now for a confirmed reason.
Fishcamp's `libfishcamp/COPYING.LIB` is genuine BSD-2-Clause despite the
LGPL-suggesting filename, so it moved into the bundled tier alongside
`fli` — `%package fishcamp`/`fishcamp-devel` (RPM) and
`indi-stable-3rdparty-libs-fishcamp[-dev]` (Debian) added to both `-libs`
packagings, and the matching `indi-fishcamp` driver added to both
`-drivers` packagings. `3rdparty` now bundles 9 vendors, not 8, on both
distros.

**One real defect found integrating it, same shape on both distros: the
shared firmware directory.** `sbig` and `fishcamp` both install into the
identical `FIRMWARE_INSTALL_DIR`. The RPM spec's existing `%files sbig`
claimed that whole directory with one recursive glob — harmless with sbig
as the sole occupant, but would have failed the build with "file listed
twice" once fishcamp's own files landed there too. Fixed by naming every
firmware image explicitly, one vendor's worth per subpackage, with both
`sbig` and `fishcamp` independently declaring `%dir
.../share/indi/firmware` (RPM's own ownership rule, same pattern `%files
asi`'s comment already established). The Debian side had the equivalent
risk in `indi-stable-3rdparty-libs-sbig.install`'s own directory-wide glob
— not a build failure there, but a real `dpkg` conflict the first time
both packages were installed together; fixed the same way, filenames named
explicitly in each vendor's own `.install`.

**Rebuilt and verified end to end on both distros, 2026-08-27:**

RPM (`fedoraastro`): both specs rebuilt clean through `mock` on the first
attempt with the fix already in place (no second iteration needed for the
directory bug — caught while writing the spec, not while building it).
Needed a genuine `Release: 2%{?dist}` scratch build of core
(`~/mock-result-core-rel2`, from the CURRENT committed spec — reused for
`scripts/test-pyindi-client-coexist-upgrade.sh` too) only incidentally;
the 3rdparty rebuild itself used the existing `~/mock-result-pcfix` core.
Installed all 29 packages (core, core-libs, 9×2 `-libs`, 9 `-drivers`) in
one transaction alongside Fedora's own distro `libindi`/`libindi-libs`:
`indi_fishcamp_ccd` resolves `libfishcamp.so.1`,
`libindidriver.so.2`/`libindiAlignmentDriver.so.2`/`libindiclient.so.2`
all into `/opt/indi-stable/lib` via `ldd`, and actually runs, printing its
usage banner. Distro INDI stayed a clean bystander (`rpm -V` clean,
`/usr/bin/indiserver` hash unchanged). Full removal restored
`fedoraastro` to its exact 2153-package baseline.

Debian (`ubuntuastro`, configuration B): re-hit and correctly avoided the
already-documented `rm -rf debian` trap (`DEBIAN.md`, "The `indi-3rdparty`
tarball ships its OWN `debian/` directory too") on the first attempt this
session, having tripped it once before fixing it. Both `-libs` and
`-drivers` built clean, `lintian --profile debian`: 0 errors on both, only
the standard `initial-upload-closes-no-bugs` warning every package here
carries plus one `appstream-metadata-missing-modalias-provide` on
fishcamp's udev rule (same class already accepted elsewhere, not new).
Installed all 27 packages together (core, 9×2 `-libs`, 9 `-drivers`)
alongside configuration B's `libindi1` (identical `libindiclient.so.2`
SONAME): same `ldd`-resolves-and-runs result as the RPM side. Distro
`indi-bin`/`libindi1` stayed clean (`dpkg -V` clean,
`/usr/bin/indiserver` hash unchanged). Full removal restored
`ubuntuastro` to its exact pre-work package count (1832, diffed not just
counted).

## `indi-stable-pyindi-client` — Debian side, builds/installs/imports for real

`pyindi-client/deb/` is the packaging source, a new top-level directory
(genuinely separate upstream project, not part of `indi` or `indi-3rdparty`
— see `DESIGN.md`). Two decisions made before writing it, both in
`DESIGN.md`, "`pyindi-client` — packaging decisions", 2026-08-26: built from
the untagged `2.2.0` PyPI release rather than the last real git tag
(`v2.1.2` needs a static `libindiclient.a` this project's `core/` does not
build), and the built module installs to the ordinary system Python
location rather than `/opt/indi-stable` — deliberately, not an oversight;
that section explains why it is not an exception to the coexistence rule.

**Built, installed and verified cleanly on the second real
`dpkg-buildpackage`**, 2026-08-26 — two real defects found and fixed, full
detail in `DEBIAN.md`: `dh_auto_clean` failing outright on
`compat 12`'s removed `python_distutils` buildsystem (fixed by pinning
`--buildsystem=pybuild` explicitly), and `setup.py build_ext` alone
producing an import that *looks* like it works (`import PyIndi` succeeds,
`PyIndi.__file__` is `None`) but is actually a namespace-package fallback
missing `PyIndi.BaseClient` entirely — caught by hand before the first real
`dpkg-buildpackage`, `LESSONS_LEARNED.md` #1's shape.

**The real, load-bearing collision this fixes**: configuration B has
`libindi-dev` installed, whose own unversioned `libindiclient.so` symlink
sits in the ordinary system libdir at the exact same SONAME as ours.
`debian/rules` replaces upstream's own `library_dirs` default entirely with
`["/opt/indi-stable/lib"]` — not appended, not reordered, so there is no
search-order mistake left to make — plus the same `-Wl,-rpath` every other
component here relies on.

**`dh_python3` also needed a correction unrelated to coexistence**: the
first successful build added `python3-bottle`/`python3-dbus`/
`python3-requests` to `Depends:`, read from `pyproject.toml`'s declared
deps for `examples/` scripts this package does not ship at all. Fixed by
deleting the installed `.egg-info` (which `dh_python3` reads from) in
`override_dh_auto_install`; confirmed gone via `dpkg-deb -f`.

**Installed and imported for real on `ubuntuastro` in configuration B**,
alongside `indi-stable-core`: `python3 -c 'import PyIndi;
PyIndi.BaseClient()'` succeeds with no `PYTHONPATH` needed, and `ldd` on the
installed `_PyIndi*.so` resolves `libindiclient.so.2` to
`/opt/indi-stable/lib`, not the distribution's copy at the identical
SONAME. Distro core INDI stayed a clean bystander throughout. Removed
cleanly afterward. `lintian --profile debian`: 0 errors, the one expected
`custom-library-search-path` override plus the same unoverridden
`initial-upload-closes-no-bugs` every package here carries.

**Coexistence and upgrade survival are now scripted, 2026-08-27,
`scripts/test-pyindi-client-coexist-upgrade-deb.sh`** — no maintainer
scripts to trace here, unlike core, so the interesting question was
narrower: does `import PyIndi` still resolve correctly after
`indi-stable-core-libs` alone is upgraded underneath it, with an
already-installed pyindi-client never itself touched. Reused the existing
`2.2.4.2-1`/`2.2.4.2-2` core builds in `~/build` on `ubuntuastro` (the
same pair core's own upgrade test already uses, both confirmed 2026-08-27
to carry the `libindi.pc` fixes — no new build needed). All checks passed
on the first run: fresh install alongside configuration B's `libindi1`
(identical `libindiclient.so.2` SONAME, confirmed real via `dpkg -S` on the
actual file) resolves to the private prefix; after the core-only upgrade
`import PyIndi; PyIndi.BaseClient()` still succeeds and the resolved
library is confirmed to be `indi-stable-core-libs`'s new file, not a stale
cached copy; pyindi-client's own version, file ownership and `dpkg -V`
stayed untouched throughout; distro `libindi1` and `/usr/bin/indiserver`
stayed clean bystanders; teardown restored `ubuntuastro` to its exact
package-set baseline (diffed, not counted — see `LESSONS_LEARNED.md` #6).
Two `import PyIndi`-fails controls (before install, after removal) prove
the succeeds-checks weren't vacuously true.

## `indi-stable-pyindi-client` — RPM side, builds/installs/imports for real

`pyindi-client/rpm/indi-stable-pyindi-client.spec` translates the
already-verified Debian packaging (same two decisions from `DESIGN.md`,
same `setup.cfg`/`setup.py` sed patches, same RPATH mechanism). `Source0`
pins the exact `files.pythonhosted.org` URL for the `2.2.0` sdist, sha256
`2f224edc...f571a` — verified 2026-08-27 two ways: against PyPI's own JSON
API digest and by hashing a local download directly, not trusted from
either source alone.

**Built cleanly through `mock` on `fedoraastro` on the second attempt,
2026-08-27** — one real defect, not zero: the first `mock` build failed at
`g++: No such file or directory`. `python3-devel` pulls in `gcc` but not
`gcc-c++`, and this package compiles a `.cxx` SWIG wrapper; core.spec's own
`gcc-c++` BuildRequires was the thing to copy and wasn't. Fixed by adding
it. Same `mock --install` pattern as `-libs`/`-drivers` for
`indi-stable-core-devel` (no repo to resolve it from); the first failed
build's `cleanup_on_failure=True` wiped those installed RPMs back out of the
chroot, so the fix required reinstalling them before the second attempt,
not just editing the spec.

`check-rpaths` fired `WARNING 0002` on the compiled extension's RUNPATH
into `/opt/indi-stable/lib`, same signature and same downgrade as every
other component here — confirms the RPATH mechanism transfers to a Python
C-extension unchanged.

Verified directly against the built RPM: `rpm -qp --provides` is
package-name-only (no accidental SONAME advertisement — Python extension
modules built without `-Wl,-soname` get no ELF Provides in the first place,
so no `__provides_exclude_from` was even needed here, unlike core/3rdparty);
`rpm -qp --requires` carries the same `%global __requires_exclude` fix as
core's own spec (no leaked `libindiclient.so.2()(64bit)`), an explicit
unversioned `Requires: indi-stable-core-libs%{?_isa}` (independent version
axis, same pattern as `-3rdparty-drivers.spec`), and ordinary
`libc`/`libgcc_s`/`libstdc++`/`python(abi)` Requires. `libz`/`libcfitsio`/
`libnova` are absent from both distros' Requires — confirmed via `readelf
-d` this is `--as-needed` correctly dropping libraries the SWIG wrapper
object doesn't reference directly (only `libindiclient.so.2` is), not a
regression; `libindiclient.so.2` carries those transitively on its own, and
Debian's already-verified `Depends:` shows the identical set
(`DEBIAN.md`). The installed egg-info is deleted in `%install` the same way
`pyindi-client/deb/rules` deletes it, for the same reason (unwanted
`requests`/`bottle`/`dbus-python` deps read from `pyproject.toml`'s
`examples/`-only dependencies) — confirmed absent from the built RPM's file
list.

**Installed and imported for real on `fedoraastro`'s host**, alongside
`indi-stable-core`/`-libs` and Fedora 44's own distro `libindi`/`libindi-libs`
(`libindiclient.so.2`, identical SONAME — the tightest collision case, same
as Debian's own configuration B): `python3 -c 'import PyIndi;
PyIndi.BaseClient()'` succeeds, `PyIndi.__file__` resolves to a real path
(not the namespace-package trap `LESSONS_LEARNED.md` #1 already caught on
the Debian side), and `ldd` on the installed `_PyIndi*.so` resolves
`libindiclient.so.2` to `/opt/indi-stable/lib`, not the distribution's copy
at the identical SONAME. Distro core INDI stayed a clean bystander
throughout: `rpm -V libindi libindi-libs kstars` clean, `/usr/bin/indiserver`
hash unchanged. Removed cleanly afterward; `fedoraastro` re-verified back at
its exact 2153-package baseline, `/opt/indi-stable` completely absent.

**Coexistence and upgrade survival are now scripted, 2026-08-27,
`scripts/test-pyindi-client-coexist-upgrade.sh`** — same shape as the
Debian version above, translated: fresh install alongside Fedora's own
distro `libindi`/`libindi-libs` (identical SONAME, confirmed real via
`rpm -q --provides`) resolves `libindiclient.so.2` into the private prefix;
a genuine `Release: 2%{?dist}` scratch build of core (`~/mock-result-core-
rel2` on `fedoraastro`, built from the CURRENT committed spec — the stale
`~/mock-result-rel2` predates the `libindi.pc` fixes and was deliberately
NOT reused) upgrades core/-libs alone while pyindi-client stays installed
and untouched; `import PyIndi; PyIndi.BaseClient()` still succeeds
afterward and `rpm -qf` on the resolved library confirms it is really
core-libs' new NVR, not a stale cached copy. One real bug found and fixed
in the script itself before it ever ran clean: the default paths used
`$HOME`, which under `sudo` resolves to `/root` (`LESSONS_LEARNED.md` #4,
already cited in the script's own header comment but not actually applied
to the defaults) — fixed to derive the real user's home from `SUDO_USER`,
same as every other script here. All checks passed after that fix;
`fedoraastro` re-verified back at its exact 2153-package baseline.

## Release automation (`core-release.yml`) — verified end to end, 2026-08-28

Built per `DESIGN.md`, "Release automation, v1" (core only, both distros,
GitHub-hosted runners, no COPR/OBS yet — see that section for the design).
Repo stays private throughout, per the same section's own note. Took two
`workflow_dispatch` dry runs (no new upstream tag, `check` correctly found
nothing and every downstream job skipped) and then five full end-to-end
runs, forcing `versions.json`'s `core.candidate` back to a genuine prior
real tag (`v2.2.4.1`) to make `v2.2.4.2` register as "new" — there being no
actually-newer upstream tag to test against for real. Three real defects
found and fixed, each caught by the gate rather than silently promoted:

1. **`ubuntu-latest` resolves to Ubuntu 24.04 "noble", whose archive ships
   `libxisf-dev 0.2.8-1`** — missing the
   `LibXISF::DataBlock::CompressionCodecSupported()`/`ZSTD` API
   `indiccd.cpp` calls in v2.2.4.2. `ubuntuastro` runs 26.04 "resolute",
   whose `libxisf-dev 0.2.13-1build1` has it — exactly why the identical
   source had always built cleanly there and never once on
   `ubuntu-latest`. Fixed by pinning `build-debian`/`smoke-test-debian` to
   the explicit `ubuntu-26.04` GitHub-hosted label (preview but real),
   matching `ubuntuastro`'s actual environment instead of a rolling label.
2. **`indilib/indi`'s own tarball ships its own `debian/`** (`indi-bin`,
   `libindi1`, `libindi-data`, `libindi-dev` — upstream's own packaging),
   contrary to this workflow's own first comment, which claimed otherwise
   without checking. `DEBIAN.md` already documented the `rm -rf debian`
   requirement for `core/deb` specifically; the workflow simply didn't
   apply it. Without it, `cp -r core/deb debian` copied our tree INSIDE
   theirs as `debian/deb` instead of replacing it, and the build silently
   produced upstream's own unmodified packaging — wrong names, no private
   prefix, none of this project's coexistence guarantees — while still
   reporting a clean build. Only caught because
   `scripts/smoke-test-core-deb.sh` looks for `indi-stable-core*.deb` by
   name specifically and found nothing, failing loudly rather than
   letting `promote` ship it.
3. **`apt-get` misparsed a relative artifact path.** Confirmed
   `CORE_DEB`/`LIBS_DEB` resolved correctly (`debs/indi-stable-core_...`,
   verified with an explicit bracketed dump) yet `apt-get install` still
   reported `Unable to locate package debs` — consistent with apt falling
   back to its `PACKAGE/RELEASE` pin syntax (splitting on the first `/`)
   when it doesn't recognize an argument as a real file, something
   `ubuntuastro`'s own `apt-get` does not do with the identical relative
   path. Root cause not chased to an exact apt version/config difference;
   fixed by canonicalizing `DEB_DIR`/`RPM_DIR` to an absolute path in both
   `scripts/smoke-test-core*.sh` before either package manager ever sees
   it, which removes the ambiguity regardless of mechanism.

Final run: `build-fedora` and `build-debian` both succeeded (~19–25 min
each, genuinely cold — no dnf/apt cache persists between runs),
`smoke-test-fedora` and `smoke-test-debian` both installed into a fresh
container and confirmed `indiserver-stable --version` and
`indi_simulator_ccd --help`, and `promote` committed
`indi-stable-core-v2.2.4.2` to `development`, tagged it, and created a
real GitHub Release with all six artifacts (core/core-libs/core-devel ×
RPM+DEB) attached. Since no genuinely newer upstream tag existed to test
against, this necessarily re-promoted the already-current `v2.2.4.2`;
`core/deb/changelog`'s resulting duplicate-version entry was squashed
back into one afterward. `versions.json` is back to its correct real
state (`candidate` = `release` = `v2.2.4.2` for `core`) automatically, as
a side effect of `promote` doing its job.

**The `%changelog` gap is fixed, 2026-09-04.** `promote` now calls
`scripts/bump-core-version.sh` rather than inline `sed`/`dch`, matching the
other two workflows. It adds the RPM `%changelog` entry that was missing,
is idempotent against re-promotion, and asserts that `Source0` still
resolves to the new tag. Two further defects in the inline step were found
while replacing it: `dch` had no idempotency guard (which is what produced
the 2026-08-28 duplicate), and the `sed` matched exactly eight literal
spaces after `Version:` — demonstrated to leave the file silently unchanged
if that column ever shifted. Not yet exercised in CI, deliberately — confirmed
with Will 2026-09-04. A forced re-promotion, the technique used to verify
the other two workflows, **cannot test this fix**: forcing `core.candidate`
back makes `check` rediscover `v2.2.4.2`, but the spec already carries a
`2.2.4.2-1` `%changelog` entry, so the bump would take its SKIP path on
every changelog and the new-entry path — the gap itself — would never run.
It would also fail at the last step regardless, because the release AND tag
`indi-stable-core-v2.2.4.2` already exist and `gh release create` refuses an
existing tag. **That last point applies to any future forced core run**, and
is the reason core cannot be re-run the way 3rdparty and pyindi-client were.
The new-entry path was exercised locally against `v2.2.5`, with `rpmspec`
and `dpkg-parsechangelog` agreeing; what remains untested is that path
inside a runner, and the identical script shape has now done that twice.
Harmless this run (`Version:` was already correct, so the `sed` was a
no-op and nothing needed changelogging), but a genuinely new promotion
would leave the RPM spec's own changelog silently behind Debian's.

## The runtime-symlink defect — found and fixed 2026-09-04, both distros

**45 of 56 driver binaries could not load on an ordinary runtime-only
install.** `touptek` 33/33, `asi` 6/6 and `micam` 6/6 were completely
broken; `apogee`, `fli`, `playerone`, `sbig`, `inovasdk` and `fishcamp`
were entirely fine.

Mechanism, measured with `readelf` rather than inferred: 17 of the bundled
vendor blobs carry an **unversioned** SONAME (`libtoupcam.so.60`'s SONAME is
`libtoupcam.so`; `libgxccd.so.0`'s is `libgxccd.so`) or none at all (the
five ZWO/ASI blobs). Each driver's `DT_NEEDED` is therefore the bare name,
which the dynamic loader needs at **run** time — but the packaging shipped
that symlink in `-devel`/`-dev`, following the ordinary convention that an
unversioned `.so` is a link-time artifact. That convention assumes a
versioned SONAME. Full rule in `LESSONS_LEARNED.md` #22.

These are exactly the 17 libraries this document already identified in a
different context (`dpkg-shlibdeps` skipping them, in the `-drivers` Debian
section below). The blobs were known to be unusual; nothing had connected
that to symlink placement.

**Why every earlier check missed it:** all of them used `indi_apogee_ccd` as
"a representative driver", and apogee is one of the six vendors the defect
could not affect. Both coexistence passes, all four upgrade-path harnesses
and the manual spot-checks ran green against the one case that worked.

**Fixed and verified on both distros.** RPM: rebuilt through `mock`, all 56
binaries resolve with ours inside `/opt/indi-stable`, `rpm -qf` confirms the
RUNTIME package now owns `libtoupcam.so`, and one driver from each of the 9
vendors executes with zero `-devel` packages installed. Debian: rebuilt on
`ubuntuastro` in configuration B, same result, `lintian --profile debian`
0 errors on all three changed packages and no objection to a runtime package
carrying the symlink. Both boxes restored to their exact baselines
afterward.

**Gated from here on** by `scripts/smoke-test-3rdparty.sh` and
`scripts/smoke-test-3rdparty-deb.sh`, which check *every* shipped driver's
`ldd` and execute one driver per *vendor* — proven to fail against the
pre-fix build and pass against the fixed one.

## Fedora — remaining

### `Release` tagging across rebuilds — done 2026-09-04, one step unrun

**Both halves are built.** The bump scripts rewrite RPM `Release:` from the
same number that drives the Debian revision and take `--repackage` to hold
the upstream version and advance the release. All three workflows take a
`repackage` **workflow_dispatch input** that rebuilds the current version at
the next release, so a repackage is now shippable rather than a by-hand
build.

Fixing it uncovered that the revision argument was already accepted and
already half-wired — it moved the Debian revision and the RPM `%changelog`
while leaving `Release:` at 1, so `bump-core-version.sh v2.2.4.2 2` built an
RPM whose NVR was `-1` while its own changelog claimed `-2`.

Release tags: release 1 keeps the plain name so existing tags stay valid; a
repackage gets an explicit `-N` suffix, without which `gh release create`
fails on the already-existing tag.

**Verified end to end on 3rdparty, 2026-09-04.** All 8 jobs passed:
`check` resolved `2.2.4.1-1 -> 2.2.4.1-2`, both specs built as `-2` (they
must move together, and `-drivers` building at all proves they did), the 18
Debian pins rewrote to `(= 2.2.4.1-2)` in CI, and the release published as
`indi-stable-3rdparty-v2.2.4.1-2` — the `-N` suffix avoiding the collision
with the existing `-v2.2.4.1` tag. Confirmed against the published
artifacts: RPM NVR `2.2.4.1-2.fc44`, deb `2.2.4.1-2`, the runtime-symlink
fix still present, and the drivers deb depending on
`indi-stable-3rdparty-libs-touptek (= 2.2.4.1-2)` rather than `-1`.
`versions.json` correctly did NOT move, a repackage being a rebuild rather
than a new upstream version.

That run also surfaced one cosmetic defect, fixed in `0e5d28d`: the promote
commit subject omitted the release, so the repackage commit was
byte-identical to the original promotion's. **`3rdparty` therefore now sits
at `Release: 2` with a published `-2` release that is functionally identical
to `-1`** — the cost of proving the path, agreed in advance.

## Debian / Ubuntu — remaining

For `core/`: nothing. All four checks named in `DEBIAN.md`, "The equivalent
of the tests that mattered", are scripted, were run on `ubuntuastro` on
2026-08-26 in configuration B, and passed with every positive control
watched firing.

For `3rdparty/`: nothing. Coexistence is scripted,
`scripts/test-3rdparty-coexist-deb.sh` — verified 2026-08-26, see the
`indi-stable-3rdparty-drivers` — Debian side section above. The upgrade path
is also scripted, `scripts/test-upgrade-path-3rdparty-deb.sh` and
`scripts/test-upgrade-path-drivers-deb.sh` — both verified 2026-08-26.

---

## Undecided

- **What distribution should the changelog name once there is an apt
  repository?** Settled for now as `unstable` — see `DEBIAN.md`, "The changelog
  distribution". Worth revisiting only when a repository exists, because
  `reprepro`/`aptly` read the field to choose a target suite and this project's
  channels are `release` and `candidate`.
- **Should a distribution package prune driver categories?** ACS prunes to
  `ccd`, which is right for a simulator-only box and probably wrong here —
  someone installing a *distribution package* expects their hardware supported.
  Current answer is build everything; revisit if build time or breakage surface
  proves unreasonable. (It does not: a full build is under four minutes.)
