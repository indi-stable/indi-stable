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
| **`3rdparty/`** | RPM and Debian sides both complete for both source packages, all three verified together (`indi-stable-core`, `-3rdparty-libs`, `-3rdparty-drivers`), on both distros. **9 vendors plus 21 non-blob drivers as of 2026-09-09 — 30 `-drivers` packages, 86 driver binaries**, added across seven slices and each one built, installed, coexistence- and smoke-verified on both distros. None of it ships yet: `-drivers` needs a `Release: 2`/`-2` bump first, because its contents grew while the upstream tag stayed put. Only `dsi` and `rolloffino` remain unbuilt, both on licence grounds rather than packaging ones. **A serious defect was found and fixed 2026-09-04 that all of the earlier verification had missed: 45 of 56 driver binaries could not load on a runtime-only install**, because 17 vendor blobs carry an unversioned SONAME and their bare `.so` symlink was shipped in `-devel`/`-dev` rather than the runtime package (`LESSONS_LEARNED.md` #22). Fixed and re-verified on both distros — see the dated section below. See "3rdparty — remaining" for what is still genuinely open (QSI stays excluded for a confirmed reason; `flipro`/`flialgo` licence coverage; non-blob drivers). |
| **`pyindi-client/`** | Both sides built, installed, imported for real, and coexistence/upgrade-tested via scripted harnesses: Debian 2026-08-26/27 (`pyindi-client/deb/`), RPM 2026-08-27 (`pyindi-client/rpm/`). Release automation added 2026-09-04, including a smoke check that every symbol the SWIG wrapper references is actually exported — the `DESIGN.md` 2026-09-03 incident's failure mode, which `import PyIndi` and `BaseClient()` both survive. Nothing outstanding on the packaging itself. |
| **CI (all three)** | **Verified end to end ON THIS REPO, 2026-09-04**, not just inherited from the seed's own history. Core, 3rdparty and pyindi-client each ran a real (not dry-run) check → build → smoke-test → promote cycle here for the first time, each publishing a real GitHub Release and pushing a real promotion commit: `indi-stable-core-v2.2.4.2` (6 assets), `indi-stable-3rdparty-v2.2.4.1` (54 assets, at a clean `Release: 1` — see below for why that needed a real fix first), `indi-stable-pyindi-client-2.2.0` (2 assets, symbol-check counts 1172/1199 confirmed substantive, not vacuous). All three promote jobs now create the GitHub Release **before** committing the version bump (`53cef94`) — closing a real, if narrow, window where a downstream workflow reading `versions.json` could see a release referenced before it existed; confirmed on this run by the release's `publishedAt` and the promote commit's own timestamp landing in the same second, not by trusting the reorder alone. |
| **3rdparty's first real run here failed, and the cause was worth finding.** The fresh-history seed carried over the archived repo's already-bumped state (`Release: 2%{?dist}`, changelogs and all 18 control pins at `-2` — leftover from a repackage test run there). This repo's own release history starts fresh, so the first real promotion attempt collided: Debian's `dch` correctly refused to write a lower version than what its changelog already claimed, but the RPM side's plain `sed` had no equivalent check and **silently regressed `Release: 2` back down to `1`**, reporting success. Fixed in two parts, `01b52b9`: the seed's phantom `-2` content reset to a clean `-1` (nothing describing that content ever actually shipped from this repo), and all three bump scripts hardened to refuse moving RPM `Release:` backward for an unchanged upstream version, matching what `dch` already enforced on the Debian side. Re-run afterward: all 8 jobs passed. |

Work happens on `development`. Will merges to `main` himself, via PR.

**`main`, not `development`, is what every release workflow reads from and
publishes to, as of 2026-09-05** — see `DESIGN.md`, "Release automation —
`main`, not `development`, is the branch of record" for why and how
`promote` self-merges into a protected branch without a human click.
`development` remains where hand-authored packaging changes are made, and
is fast-forwarded from `main` at the end of each promotion job so it never
lags behind main's own bumps.

The reconciliation that preceded this fix (bringing `main`'s `versions.json`
up to what had actually been promoted) needed a follow-up correction: the
first attempt merged clean but silently kept `main`'s stale candidates
anyway, a merge-base pitfall recorded in `LESSONS_LEARNED.md` #23. Fixed
with a direct commit against `main`'s tip; confirmed byte-identical to
`development`'s `versions.json` and against upstream's actual latest tags
via `scripts/check-upstream-tag.sh`.

**`promote`'s new branch-create → PR → self-merge → delete-branch path is
still unexercised.** All three `workflow_dispatch` runs on 2026-09-05 that
confirmed the poll itself is quiet again correctly found nothing new, so
`build`/`smoke-test`/`promote` were all skipped in every one of them — the
YAML has been reviewed but never actually run. Deliberately not forced via
a `repackage: true` run (would publish a real extra GitHub Release just to
test plumbing); verify this for real on whichever component's `promote`
job runs next for a genuine reason, and check afterward that its
`ci/promote-<component>-...` branch was actually deleted, not just that
the job went green.

**This repo is public**, with Will as its only collaborator with write
access (`gh api repos/:owner/:repo/collaborators`, confirmed 2026-09-05).
Anyone can read, clone, or fork it, but pushing a branch — to `development`
or anywhere — requires write access nobody else has, so no outside PR can
reach the self-merge path above.

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

**Switching machines?** **Both boxes now have a clone of this repo at
`~/src/indi-stable`**, `fedoraastro`'s added 2026-09-09 and both sitting on
`development` at the same commit. `fedoraastro` still also carries
`~/src/packaging`, the retired predecessor repo — do not confuse the two; the
spec-copying workaround the 2026-09-08 Fedora build needed is no longer
required.

The box you are moving *to* will be behind — `git pull` on `development`
first. Two per-clone git settings, applied on both clones — re-apply them on
any new clone, because neither travels with a `git clone`:

```bash
git config user.email william@williamlsnyder.org   # commit authorship
git config core.hooksPath .githooks                # or the pre-commit hook is inert
```

**Baselines, both boxes, end of 2026-09-08.** Neither carries any
`indi-stable` package and `/opt/indi-stable` is absent on both.

- **`fedoraastro`: 2153 packages, byte-identical to its documented baseline**
  after everything below.
- **`ubuntuastro`: 1839 packages, not the 1832 this file used to say.** The
  difference is **not** leftover work — it is `unattended-upgrades` running a
  kernel and security update mid-session (7.0.0-30 → 7.0.0-31, plus
  openssl/sssd/webkit/bind9), which added seven `linux-*` packages and removed
  none. Diffed by package *name* to establish that, not by count. Re-baseline
  from 1839 rather than treating the delta as contamination — and note this is
  a live desktop that will drift again, so diff names, never counts (#6).

**Build artifacts left on both boxes**, reusable rather than rebuilt:

| Box | Path | What |
|---|---|---|
| `fedoraastro` | `~/mock-result-pcfix` | core `2.2.4.2-1` |
| `fedoraastro` | `~/mock-result-symlinkfix` | `-libs` `2.2.4.1-1`, **post**-#22 fix |
| `fedoraastro` | `~/mock-result-drivers-eqmod` | `-drivers` `2.2.4.1-1` **with eqmod**, 10 subpackages |
| `fedoraastro` | `~/mock-result-libs-rel2new` | `-libs` `2.2.4.1-2` scratch, for upgrade tests, 18 RPMs |
| `fedoraastro` | `~/mock-result-drivers-rel2full` | `-drivers` `2.2.4.1-2` scratch at **full scope, 30 subpackages** — replaces `-rel2new`, which held the 10-subpackage eqmod-era build |
| `fedoraastro` | `~/eqmod-build/` | the copied spec, harnesses and every build log |
| `fedoraastro` | `~/mock-result-drivers-slice7` | `-drivers` `2.2.4.1-1`, **30 subpackages** — the current build |
| `ubuntuastro` | `~/build/*_2.2.4.1-1_*.deb` | `-libs` and `-drivers` at `-1`; the `-drivers` set is the current **30-package** build |
| `ubuntuastro` | `~/build/slice7-stage/` | the runtime-only 41-deb set the slice-7 smoke test ran against, one version of each |
| `ubuntuastro` | `~/build/*_2.2.4.1-2_*.deb` | both at `-2`, freshly rebuilt from current packaging |

**Disk cleanup, 2026-09-09.** `ubuntuastro` reached 99% full (643 MB free)
during the driver widening. The cause was seven unpacked `indi-3rdparty`
build trees, one per slice, at ~1.5 GB each. All were deleted, along with
six superseded smoke-test staging directories and, on `fedoraastro`, the
six superseded `mock-result-drivers-slice*` sets. `ubuntuastro` went to 71%
used, `fedoraastro` to 59%.

**None of that was an artifact.** `dpkg-buildpackage` writes the `.deb`s to
the *parent* of the build tree, so they were always in `~/build` itself, and
every staging directory was a copy of files already there — both checked
before deleting rather than assumed. The trees are regenerable in one
`tar xf` from `~/build/indi-3rdparty-v2.2.4.1.tar.gz`, which is kept.

**`ubuntuastro` still holds ~9 GB of older unpacked trees from previous
sessions** — `indi-2.2.4.2`, `rel2-libs`, `rel2-drivers`,
`indi-3rdparty-2.2.4.1-libsfix`, `-drivers` and `-eqmod`. They were left
alone because they predate this session. `-eqmod` in particular is the tree
the upstream source surveys read from, so deleting it costs a re-unpack;
the rest look like ordinary leftovers.

`~/mock-result-3rdparty` and `~/mock-result-3rdparty-fishcamp` on
`fedoraastro` both **predate the #22 runtime-symlink fix** and must not be
used. They hold 18 RPMs each, exactly like `~/mock-result-symlinkfix`, and are
indistinguishable by name — tell them apart by asking whether the *runtime*
touptek RPM owns the bare `libtoupcam.so` (`FEDORA.md`).

The `~/build/*-2*.deb` set was rebuilt from the current packaging on
2026-09-08, replacing an older `-2` set that predated both fishcamp and eqmod.

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

**Both RPM upgrade harnesses re-run green at full scope, 2026-09-09.**
`-libs` against its own `-2` scratch, and `-drivers` against a fresh `-2`
scratch built at 30 subpackages — the previous one held 10 and dated from
eqmod. Neither harness needed changing: both glob their inputs and the
drivers one loops over `rpm -qa 'indi-stable-3rdparty-drivers-*'`, so both
scaled on their own. **All 30 driver packages were individually confirmed to
resolve and run after the upgrade**, not one representative.

Both controls fired: each harness plants a stray file under
`/opt/indi-stable` and requires its orphan check to report it. `fedoraastro`
back to its exact 2153-package baseline afterward, `gcc` still absent,
`rpm -V` clean on `libindi`/`libindi-libs`/`kstars`.

One thing worth not misreading in the teardown log: a distribution package,
`rtl-sdr`, appears in the removal list. It is pulled in by
`indi-stable-core`, not by anything here — checked, no `-drivers` subpackage
requires it — and the diff-based restore removed it correctly.

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
- **`eqmod` is packaged on both distros but has never been built.** Scope
  decided with Will 2026-09-08 — eqmod alone first as a complete vertical
  slice, then widen; one subpackage per driver. See `DESIGN.md`, "Decided:
  eqmod first, then widen", for the reasoning, the licence finding
  (`eqmod` is the only non-LGPL subpackage here) and the catalogue defect
  found while writing it.

  Done, no build yet: `-DWITH_EQMOD=OFF` removed and
  `-DWITH_WEBCAM=OFF`/`-DWITH_NUT=OFF` pinned in both
  `core/rpm/indi-stable-3rdparty-drivers.spec` and
  `core/deb-3rdparty-drivers/rules`; `libnova`/`GSL` BuildRequires added on
  both; `%package`/`%files eqmod` and the Debian `-eqmod` binary package,
  `.install` and `.lintian-overrides` written; `debian/copyright` given
  eqmod's two licence stanzas; the AHP GT catalogue entry stripped and a
  no-bare-names assertion added to both packagings.

  **The Debian side is done, 2026-09-08.** Built clean on the first real
  `dpkg-buildpackage` (ten binary packages now, not nine), `lintian` 0
  errors, coexistence verified in configuration B against a distro
  `libindi1` carrying a byte-identical `libindidriver.so.2` SONAME, and
  `scripts/smoke-test-3rdparty-deb.sh` passed with eqmod included — 60
  driver binaries where there were 56, `indi_azgti_telescope` executing in
  the per-vendor loop. `ubuntuastro` restored to its exact baseline, package
  set diffed rather than counted. Full detail in `DEBIAN.md`, "`eqmod` added
  — built and verified".

  **The Fedora side is done too, 2026-09-08.** Built clean through `mock` on
  the first attempt (44s, ten subpackages), `libnova-devel`/`gsl-devel`
  confirmed present in the base `fedora` repo — the one dependency question
  that had been open — and `scripts/smoke-test-3rdparty.sh` passed with eqmod
  included, 60 driver binaries where there were 56. Coexistence verified
  against Fedora 44's own `libindi-libs` at the identical SONAME;
  `fedoraastro` restored to its exact 2153-package baseline. Both packagings
  independently reported the same 63 catalogue entries, which is the
  cross-check that they strip the dangling AHP GT entry identically. Full
  detail in `FEDORA.md`, "`eqmod` added — built and verified".

  **All four upgrade-path harnesses pass, 2026-09-08**, run against genuine
  `Release: 2` / `-2` scratch builds of *both* `-libs` and `-drivers` on both
  distros (built via `scripts/bump-3rdparty-version.sh v2.2.4.1 2` in an
  uncommitted scratch copy of the repo, which rewrote all 18 Debian pins). Both
  `-drivers` harnesses now confirm every one of the ten driver packages
  resolves and runs after the upgrade, eqmod included, not just
  `indi_apogee_ccd`. **Three real defects in the harnesses themselves were
  found by running them** — see `LESSONS_LEARNED.md` #25 and the note below.

  **What is left for eqmod:**
  1. `-drivers` needs a `Release: 2` / `-2` revision before it can ship, the
     upstream tag being unchanged while its contents have grown. Do not
     hand-edit it — the bump scripts own `Release:`, and the repackage path's
     `-N` suffix has never actually run in a runner (see the correction in
     the release-automation section below).
  2. Nothing else. Build, install, coexistence, smoke test and upgrade path
     are all verified on both distros.

  **Three harness defects found by running them, all now fixed** — the tests
  were wrong, the packaging was not, which is this project's usual ratio:
  - Both **Debian** harnesses hardcoded an eight-vendor list and had silently
    not covered `fishcamp` since 2026-08-27, nor could they express eqmod at
    all (a driver with no `-libs` counterpart). They now derive the list from
    the `.deb`s present and abort if it comes back empty. Their RPM twins glob
    and were never affected. `LESSONS_LEARNED.md` #25.
  - Both **`-drivers`** harnesses checked only `indi_apogee_ccd` after the
    upgrade — the same single-representative flaw that let #22's 45 broken
    binaries through. Fixed then in the smoke tests only; fixed here now.
  - `scripts/test-upgrade-path-drivers.sh` and
    `scripts/test-upgrade-path-3rdparty.sh` both defaulted `CORE_DIR` to
    `$HOME/mock-result-pcfix`, which under `sudo` is `/root` — #4 again, in
    two scripts that had never been run under `sudo` with the default.

  **`mock`'s `cleanup_on_success=True` wipes `--install`ed RPMs from the
  chroot after a *successful* build**, not just a failed one. Building `-libs`
  at `-2` and then `-drivers` against it needs core's `-devel` reinstalled in
  between, or the `-drivers` build fails at `No match for argument:
  indi-stable-core-devel`. `FEDORA.md` already documented the
  `cleanup_on_failure` half of this; this is its success-path twin.
- **Widening past eqmod: the ~40 remaining non-blob drivers.** Still wanted,
  deliberately sequenced after eqmod. `DESIGN.md`'s dependency table was
  re-derived mechanically 2026-09-08, corrected again 2026-09-09, and has been
  wrong twice — build any batch from the table as it stands now, not from
  memory. `qhy` and `atik-efw` specifically need their licence relationship to
  the existing "bundle by licence tier" decision checked before either is
  included, not assumed clear by omission from the blob-driver list.

  **Slice 2 is built and verified on both distros, 2026-09-09:
  `armadillo-platypus` and `maxdomeii`.** Twelve `-drivers` packages now, 67
  driver binaries where there were 60. Chosen small, and for the mechanisms
  rather than the count: first six-binary subpackage, first udev rule in this
  source package, first catalogue whose filename matches neither its directory
  nor any binary in it (`indi_lunatico.xml`), first uninstalled upstream test
  target. Both LGPL-2.1-or-later, read per file. Build, install,
  runtime-only smoke test and coexistence all pass on both distros; both boxes
  restored to exact baseline. Detail in `FEDORA.md` and `DEBIAN.md`.

  **Two real defects found, both by building rather than by reading:**
  1. **The udev rule installed itself un-namespaced**, to the exact filename a
     distribution package for the same hardware owns. Five driver directories
     use `RULES_INSTALL_DIR` set without `CACHE`, which no `-D` can override,
     so the `-libs` redirect approach silently does nothing. Fixed by
     re-homing on destination in both packagings, with an assertion that
     nothing is left at an upstream filename.
  2. **`INDI_DATA_DIR` was resolved from the build host.** On `ubuntuastro`,
     where the distro's `libindi-data` owns `/usr/share/indi`, every catalogue
     except `eqmod`'s installed outside the private prefix. Fedora never
     showed it — a `mock` chroot has no `libindi-data` to find. Both
     packagings now pin it. The build failed later and elsewhere, at
     `dh_install` complaining about touptek, which pointed nowhere near the
     cause.

  **Slice 3 done, 2026-09-09: `aok`, `avalon`, `celestronaux`.** Fifteen
  `-drivers` packages, 70 driver binaries. No new build dependency —
  `libnova` and `GSL` have been `BuildRequires` here since `eqmod`. Built,
  smoke-tested runtime-only and coexistence-verified on both distros, both
  packagings independently reporting 70 binaries and 86 catalogue entries;
  both boxes back at baseline. **No defects.** First slice in this line of
  work to find nothing, which is what "repetition of a proven shape" is
  supposed to look like — the udev and `INDI_DATA_DIR` fixes from slice 2
  carried these three with no new work.

  These three were chosen because they are the only members of the Nova-only
  group whose licence is unambiguous. The licence survey that picked them is
  the real output of this slice, and it blocks most of the rest.

  **Slice 4 done, 2026-09-09: `nexdome`, `talon6`, `ocs`, `starbook-ten`.**
  Nineteen `-drivers` packages, 74 driver binaries. Unblocked by Will's
  decision on what licence text an LGPL-2.0-only driver should ship — see
  `DESIGN.md`, "Decided: ship the exact LGPL-2.0 text". All four carry their own
  `License: LGPL-2.0-only`; `starbook-ten` is `LGPL-2.0-only AND MIT`,
  because it compiles in cpp-httplib. `ocs`'s own bundled `LICENSE.txt` is
  deliberately not shipped: it is the GPL-2 text and contradicts every
  source header in its directory. No defects. Both packagings independently
  report 74 binaries and 90 catalogue entries; both boxes back at baseline.

  **Slice 5 done, 2026-09-09: `aagcloudwatcher-ng`, `nightscape`,
  `openogma`, `orion-ssg3`, `atik-efw`.** Twenty-four `-drivers` packages, 79
  driver binaries. The udev rule count went 1 → 4 and the exact-count
  assertion in both packagings moved with it. Both packagings independently
  report 79 binaries and 96 catalogue entries; both boxes at exact baseline,
  `ubuntuastro` diffed by package NAME and identical, not merely 1839 again.

  Licence outcomes, all read per file: `aagcloudwatcher-ng` is
  GPL-3.0-or-later with a matching bundled GPL-3 text. `nightscape` has no
  source header anywhere and its bundled `COPYING.LIB` is the LGPL-2.0 text,
  so it is the one driver here whose shipped text exactly matches its tag.
  `openogma` is **AGPL-3.0-only**, the only AGPL package in this project.
  `orion-ssg3` bundles a GPL-3 `LICENSE` contradicting its own
  LGPL-2.1-or-later headers, so that file is not shipped. `atik-efw` has **no
  relationship to the Atik vendor SDK** — checked directly, its CMakeLists
  asks only for INDI and Threads.

  **`nightscape` needed a new build dependency nobody had found, and it took
  a build failure.** `FIND_PACKAGE(FTDI1 REQUIRED)` is upper case, and the
  survey regex that produced `DESIGN.md`'s dependency table was
  case-sensitive, so two passes both reported nightscape as needing nothing.
  It is the only non-obsolete driver affected. `libftdi-devel` /
  `libftdi1-dev` added to both packagings; both dependency generators pick up
  the runtime `libftdi1.so.2` on their own.

### Closed: the LGPL-2.0 licence text, re-decided on correct facts

`nexdome`, `talon6`, `ocs` and `starbook-ten` now ship the **exact LGPL-2.0
text**, `indi-inovaplx/COPYING.LIB` on the RPM side and a
`/usr/share/common-licenses/LGPL-2` reference on the Debian side. Verified by
extracting the licence file from each built RPM and reading its version line,
not from the `%license` line.

They briefly shipped the LGPL-2.1, because Will was told no LGPL-2.0 text
existed in the tree. Seven directories bundle it, byte-identical, and this
package was already shipping one of them with its `inovasdk` subpackage. The
error and its lesson are recorded in `DESIGN.md` where the decision lives.

  **Slice 7 done, 2026-09-09: `beefocus`, and its licence was not what the
  file count suggested.** Thirty `-drivers` packages, 86 driver binaries.
  The concern that deferred it — 24 of 29 files carrying no licence header,
  three of them compiled in — dissolved on a proper read: `firmware/` ships
  **its own full LGPL-2.1 text as `firmware/LICENSE`**, missed earlier
  because the licence-file check only looked at each driver's top level. So
  the headerless firmware sources are governed by their own directory's
  licence, not inherited by inference.

  `beefocus` is genuinely two licences and is the only subpackage here
  shipping **two** licence texts: `driver/` is LGPL-2.0-only (five of six
  files grant "version 2" with no "or later") and `firmware/` is
  LGPL-2.1-only. Both texts come from the tarball, neither is guessed at.
  `unit_tests/` is gated behind `INDI_BUILD_UNITTESTS` and never built.

  **Slice 6 done, 2026-09-09: the GPL-2.0-or-later group** —
  `bresserexos2`, `rtklib`, `shelyak`, `gpsnmea`, `astarbox`. Twenty-nine
  `-drivers` packages, 85 driver binaries. No new build dependency, no udev
  rules, no defects. Both packagings independently report 85 binaries and
  102 catalogue entries; both boxes identical to baseline by package name.

  Unblocked by the same sibling-directory answer the LGPL-2.0 group got.
  All five ship `indi-starbook-ten/COPYING`, and **which GPL-2 file matters**:
  the tarball has two, and `indi-ocs/LICENSE.txt` is an 86-line abridgement,
  not the licence. `indi-starbook-ten/COPYING` is the full 339 lines. They
  are indistinguishable from their first two lines; tell them apart by line
  count or sha256.

  Two carry a second licence: `gpsnmea` bundles minmea under the **WTFPL**
  (SPDX `WTFPL`, accepted by both distros, text in `debian/copyright` since
  the tarball has none), and `astarbox` is genuinely mixed — its own sources
  GPL-2.0-or-later, its bundled PCA9685 PWM driver LGPL-2.1-or-later.
  `astarbox`'s `COPYING.LGPL` is misnamed and holds GPL-3, so it is not
  shipped.

### Genuinely open, not just untested — continued

**Batch 1 is finished except for two drivers, and neither is packaging
work.** 30 of the 32 non-blob drivers originally scoped are built and
verified on both distros — 86 driver binaries, 30 `-drivers` packages.

- **`dsi` — decided 2026-09-09, not shipping.** Will researched the Meade
  firmware situation independently and found it a hard no on Linux. The
  driver bundles `meade-deepskyimager.hex`, Meade's proprietary EZUSB FX2
  device firmware, with no licence statement anywhere in the directory or
  the README — the same "no COPYING" situation that excluded QSI and QHY.
  Upstream's `INDI_INSTALL_FIRMWARE=OFF` would let the driver ship without
  the blob, but the camera cannot enumerate as a DSI until firmware is
  loaded, so that ships something unusable. Reopen only if the firmware's
  terms are established with Meade. (Its `FIRMWARE_INSTALL_DIR` is also a
  plain `set()` to `/usr/lib/firmware`, unredirectable, the same class as
  `RULES_INSTALL_DIR` — relevant only if it is ever revisited.)
- **`rolloffino` — nothing to reason from.** Not one of its files states any
  grant, and it ships no licence file. Unlike the headerless files elsewhere
  here, there is no grant anywhere in the directory for them to inherit.
  Needs upstream contact, not analysis.
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

**NOT verified end to end — see the correction below.** This paragraph
previously claimed a 2026-09-04 run in which all 8 jobs passed, both specs
built as `-2`, the 18 Debian pins rewrote to `(= 2.2.4.1-2)` and a release
published as `indi-stable-3rdparty-v2.2.4.1-2`. No such release, tag or
`Release: 2` spec state exists anywhere, and the claim was checked and
withdrawn on 2026-09-08. What is genuinely verified is the bump-script half:
the scripts rewrite `Release:` and the Debian revision together, refuse to
move `Release:` backward, and were exercised locally. What is **not** verified
is any of that running inside a runner and producing a `-N`-suffixed release.

That run also surfaced one cosmetic defect, fixed in `0e5d28d`: the promote
commit subject omitted the release, so the repackage commit was
byte-identical to the original promotion's.

**Correction, 2026-09-08: the `-2` release described above does not exist,
and `3rdparty` is at `Release: 1`.** This section previously claimed
`3rdparty` "now sits at `Release: 2` with a published `-2` release",
contradicting this same file's own table entry above it, which says the
release published "at a clean `Release: 1`". Checked directly rather than
choosing between the two claims: `git ls-remote --tags` has exactly one
`3rdparty` tag (`indi-stable-3rdparty-v2.2.4.1`, no `-2` suffix),
`gh release list` has exactly one `3rdparty` release, and `Release:` reads
`1%{?dist}` in the spec on both `development` and `origin/main`. The table
entry was right; this section was wrong.

**What actually happened, and it was never recorded:** the scheduled run on
2026-09-05 (`33969183934`) built all four packages successfully over ten
minutes and then **failed at `Create GitHub Release`** — consistent with
`gh release create` refusing the already-existing
`indi-stable-3rdparty-v2.2.4.1` tag, the same failure mode this file already
documents for core. Its `Commit to development` step never ran, which is
exactly why `Release:` stayed at 1 and no `-2` artifact exists anywhere. The
repackage path's `-N` suffix logic is therefore **not** verified end to end;
treat the claim above that it was as covering the bump scripts only.
Subsequent scheduled runs (09-06, 09-07, 09-08) all complete in ~13s with
`check` correctly finding nothing, so nothing is failing now.

## Debian / Ubuntu — remaining

For `core/`: nothing. All four checks named in `DEBIAN.md`, "The equivalent
of the tests that mattered", are scripted, were run on `ubuntuastro` on
2026-08-26 in configuration B, and passed with every positive control
watched firing.

For `3rdparty/`: nothing. Coexistence is scripted,
`scripts/test-3rdparty-coexist-deb.sh` — **re-run green 2026-09-09 across
all 30 driver packages**, 48 3rdparty packages in one transaction, with all
three of its controls firing: the SONAME collision shown real (same soname,
different sha256), `LD_LIBRARY_PATH` shown able to override `DT_RUNPATH` so
the clean result in the step before it is a real outcome and not a blind
check, and the restore diff shown able to report a planted difference.
`ubuntuastro` back to baseline, diffed by package name.

Its first run that day aborted, and correctly: the vendor list had just been
made derived, and a **literal `24` further down** — 8 vendors × 2 plus 8
drivers — no longer matched the 48 actually installed. Both the list and the
count are derived now. Originally verified 2026-08-26, when it covered 8 of
what were then 8 driver packages. The upgrade path
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
