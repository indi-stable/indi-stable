# Debian / Ubuntu — building and verifying the DEB

**Built and verified on Ubuntu 26.04.** The packaging mechanics below have run,
and so have the runtime and coexistence tests — by hand on 2026-08-25 and as
scripted harnesses on 2026-08-26, in **configuration B**, against a
distribution INDI carrying the same SONAME *and* the same upstream release. See
"So test two configurations" for what a configuration-A result does and does
not license you to claim.

Debian and Ubuntu share `core/deb/` entirely and are covered by this one
document. Split them only if the packaging actually diverges.

The Fedora side is a solid baseline to port from — see `FEDORA.md` — but see
"What does NOT transfer" below before assuming any Fedora result covers this.

## Building

`core/deb/` is laid out as packaging *source*. It has to be copied to `debian/`
inside an unpacked upstream tree:

```bash
sudo apt-get install -y devscripts debhelper dpkg-dev
tar xf indi-v2.2.4.2.tar.gz && cd indi-2.2.4.2
rm -rf debian                             # SEE BELOW -- not optional
cp -r ~/src/packaging/core/deb debian     # the repo clone, NOT ~/src/indi-stable
sudo apt-get build-dep .
dpkg-buildpackage -us -uc -b 2>&1 | tee /tmp/indi-stable-deb.log
lintian --profile debian ../indi-stable-core_*.changes
```

**`--profile debian` is required, not cosmetic**, and only when checking on an
Ubuntu box. See "The changelog distribution" below before removing it.

**The `rm -rf debian` is load-bearing and this file previously omitted it.** The
upstream tarball ships INDI's *own* `debian/` directory — the packaging for
`indi-bin`, `libindi1`, `libindi-data`, `libindi-dev`. Without the removal,
`cp -r core/deb debian` copies our tree *inside* theirs as `debian/deb` and
leaves upstream's `debian/rules` in charge, so the build silently produces the
distribution-shaped packages that conflict with `indi-bin` — precisely the
outcome this project exists to prevent. `ls debian` after the copy should show
`rules`, `control` and the `indi-stable-core*` files and nothing named
`libindi*`.

The GitHub tarball for tag `vX.Y.Z` unpacks to `indi-X.Y.Z` — the leading `v` is
stripped. See `DESIGN.md`.

## What does NOT transfer from the Fedora findings

This is the section to read before assuming anything is already covered.
`LESSONS_LEARNED.md` #12 is the general form of the rule: a protection on one
packaging is not evidence it exists on the other.

- **The dependency-shadowing guarantee is implemented by a different mechanism.**
  Fedora filters `Provides`/`Requires` with `%__provides_exclude_from`; Debian
  relies on **skipping `dh_makeshlibs` entirely**. The RPM side lacked its half
  for two builds while the Debian notes read as though the guarantee were
  covered generally. **Verified on its own, 2026-08-26**, from the `.deb`
  control archives rather than from `rules`: no `shlibs`, no `symbols`, no
  `Provides:` — and the distribution's `libindi1` run through the same pipeline
  does ship one, which is what shows the check can see one. The mechanism, and
  the `dpkg-shlibdeps` half that turned out to matter more, are in `DESIGN.md`,
  "The Debian half of the metadata layer".
- **The `alternatives` install/remove name pairing lives in two files here**,
  `postinst` and `prerm`, rather than in one spec. A rename applied to one and
  not the other strands the admin record. Check both sides together when
  touching either — this is the failure Fedora's uninstall test was built to
  catch. Exercised on Debian 2026-08-25: install, upgrade and removal all
  keep the pair consistent, and removal leaves no `/usr/bin/indiserver-stable`,
  no `/etc/alternatives` entry and no `/var/lib/dpkg/alternatives` admin
  record.
- **`dh_shlibdeps` needs `debian/shlibs.local`, not just `-l`.** This entry
  predicted the step would fail on a wrong `-l` path. It does fail, but not for
  that reason: the `-l` path is correct and the library *is* found. Skipping
  `dh_makeshlibs` (the bullet above) and running `dpkg-shlibdeps` are in direct
  conflict — the latter refuses to finish while any linked library lacks
  dependency information, and every driver links `libindidriver.so.2`.
  `core/deb/shlibs.local` resolves it: consulted ahead of every other source,
  never installed into a binary package. Do not "simplify" it to
  `--ignore-missing-info`, which would suppress the same error for *system*
  libraries and turn a build failure into a silently under-specified
  dependency.
- **`lintian` will emit `dir-or-file-in-opt` and `custom-library-search-path`.**
  Both are overridden deliberately; the RPATH into the private libdir *is* the
  coexistence guarantee and must not be "fixed". Check that nothing *else*
  appears — that instruction is what caught `alien-tag`, which had left the
  `-libs` and `-dev` overrides silently inert.

  The overrides live in **one file per binary package**. `dh_lintian` installs
  a given file only into the package it is named for, and lintian rejects lines
  naming any other package, so a single combined file leaves the rest inert
  while looking correct.

## What should transfer

The requirements are identical even though the mechanisms are not. All of these
are verified on Fedora and must hold here too:

- Everything under `/opt/indi-stable`; **no packaged file under `/usr/bin`**.
- Headers never under `/usr/include/libindi`.
- RPATH into the private libdir, on the **drivers** — `indiserver` links no
  INDI library at all, so checking it alone proves nothing.
- The udev rules re-homed and renamed with their numeric prefixes preserved.
- `libindi.pc` inside the private prefix, not the system pkgconfig directory.

The Fedora checklist in `FEDORA.md` is the model; the equivalents are
`dpkg -c` for file lists, `dpkg -f` / `dpkg-deb -I` for control metadata, and
`readelf -d` unchanged.

## The equivalent of the tests that mattered

The Fedora harnesses in `scripts/` are RPM-specific but the *questions* are not,
and those questions are what found every real defect. All four are now scripted
for Debian. **Run them from a clean box in any order**; each installs what it
needs, asserts the collision it depends on is real, and restores the package set
by diffing against a baseline it took itself.

| Question | Harness |
|---|---|
| Does the package manager still pull in the distribution's INDI when ours is installed? | `scripts/test-apt-depsolve.sh` |
| Do two `indiserver`s with byte-identical SONAMEs each map their own libraries? | `scripts/test-config-b-coexist.sh` |
| Does an upgrade keep the alternative alive? | `scripts/test-upgrade-path-deb.sh` |
| Does a real consumer compile, link and **run** against the `-dev` package? | `scripts/test-devel-compile-deb.sh` (+ `probe-devel-compile-deb.sh`) |

Four things about them that are not obvious from the file names:

1. **The apt depsolve question is not the RPM one in another spelling.** `dpkg`
   has no soname-level dependencies, so `apt` *cannot* pick ours by soname and
   an apt-only test would pass on a box where the guarantee had been thrown
   away entirely. The layer that can actually shadow here is `dpkg-shlibdeps`
   at a *consumer's build time*. `DESIGN.md`, "The Debian half of the metadata
   layer", has the mechanism and the measurements; the depsolve harness checks
   the install-time half and the compile harness checks the build-time half.
2. **`scripts/test-runtime-maps.sh` does work here unchanged**, as it was
   predicted to — confirmed by running it against both servers rather than
   assumed. `test-config-b-coexist.sh` calls it, and then goes further and runs
   both servers *simultaneously* with distinct `-u`, which is the form with
   teeth. **Only meaningful in configuration B** — on a stock archive box the
   SONAMEs differ and the question cannot fail. The harness reads the SONAMEs
   out of the ELF files of both trees and aborts if they do not actually
   collide.
3. **The upgrade ordering was observed, not reasoned about.** `dpkg -D2` logs
   each maintainer script as it runs. The answer is in `DESIGN.md`, "`dpkg`
   runs the maintainer scripts in the opposite order to RPM" — and it is the
   opposite of RPM's hazard, so the RPM assumption would have been wrong.
4. **The compile check runs on the host, not in a chroot**, and that is
   deliberate rather than a shortcut. See `scripts/test-devel-compile-deb.sh`'s
   header, and `LESSONS_LEARNED.md` #12 for the general form: `mock` exists on
   the Fedora side to protect a gcc-less snapshot that `ubuntuastro` does not
   have, so `sbuild`/`pbuilder` would reproduce a condition this box already
   satisfies. What the chroot bought — a guarantee the run did not change the
   box — is asserted directly instead.

Whichever harnesses get written next, carry over the two properties that made
the Fedora ones trustworthy: **assert the setup landed before measuring it**,
and **give any check that passes by finding nothing a positive control**. See
`LESSONS_LEARNED.md` #1 and #5. Every one of the four above carries controls
that were watched firing, including one that reproduces the pre-fix
`libindi.pc` defect and one that plants a mismatched `prerm`.

## The test machine, and why one configuration is not enough

Fedora's results were only trustworthy once they were run on a box with no
pre-existing INDI and no build toolchain. Provision this machine the same way,
and snapshot before installing anything, so the clean-slate case stays
reachable. `LESSONS_LEARNED.md` #13.

If the root steps are to be run from an agent session rather than by hand, set
up passwordless `sudo` while provisioning — `LESSONS_LEARNED.md` #14 has the
drop-in and why the obvious diagnosis of the failure is wrong.

**Prefer Ubuntu 26.04 LTS over Debian 13**, for one reason: it is the only one
of the two that can host the configuration where the coexistence test can
actually fail. Everything else about the two is equivalent for this packaging.

### The neighbour is not one version — checked 2026-08-25

| Environment | INDI | Library SONAME | Against ours (2.2.4) |
|---|---|---|---|
| Fedora 44 | 2.2.4.1 | `.so.2` | same SONAME, different point release |
| Debian 13 trixie, archive | 1.9.9 | `.so.1` (`libindiclient1`, `libindidriver1`, …) | **no collision** |
| Ubuntu 26.04 archive | 1.9.9 | `.so.1` | **no collision** |
| Ubuntu + `ppa:mutlaqja/ppa` | **2.2.4** | `.so.2` | **same SONAME *and* same upstream version** |

Debian and Ubuntu both froze on 1.9.9 in their archives — Debian removed the old
`libindi` source in 2019 and only *experimental* carries 2.x. So on a
stock Debian or Ubuntu box **our `.so.2` cannot collide with their `.so.1`**,
and the runtime library-mapping test passes because the situation cannot
arise. That is a check that cannot fail, not a check that passed
(`LESSONS_LEARNED.md` #12).

But a stock box is not what the users this project must not break are running.
INDI's own Ubuntu instructions are `apt-add-repository ppa:mutlaqja/ppa`
followed by `indi-full` and `kstars-bleeding`, and that PPA — "INDI Stable
Builds" — ships **libindi 2.2.4**, the same upstream release this project
packages. A machine set up the way the documentation tells people to set it up
is therefore a *tighter* collision case than the Fedora VM: same SONAME and the
same version, differing only in our fourth tag component.

### So test two configurations, and label which one a result came from

- **A — archive only** (1.9.9, `.so.1`). Everything in "What should transfer"
  above, all the packaging mechanics, and the `-dev` coexistence test, which
  collides by *path* (`/usr/include/libindi`) regardless of SONAME. Do **not**
  report the runtime-maps or depsolve results from this box as evidence of
  anything: record them as not-applicable, or they will read later as passes.

  **Add the udev rename to that not-applicable list.** Checked 2026-08-25:
  Ubuntu's 1.9.9 packaging ships *no* udev rules at all — not in `indi-bin`,
  `libindi-data`, `libindi-plugins`, `libindidriver1` or `indi-eqmod`, and
  nothing under `/usr/lib/udev/rules.d` matches `*indi*`. Fedora's `libindi`
  does ship `99-indi_auxiliary.rules`, which is where the collision the rename
  avoids actually exists. On configuration A our renamed files cannot collide
  with anything, so "no collision" here is a check that cannot fail. The rename
  is only genuinely under test against the PPA build.
- **B — archive plus `ppa:mutlaqja/ppa`** (2.2.4, `.so.2`). The configuration
  where the coexistence guarantee is genuinely under test. Snapshot A before
  adding the PPA so both remain reachable.

  **The udev rules that configuration A does not have are here** — checked
  2026-08-26, and by a different package than expected. They belong to
  **`indi-bin`**, not `libindi1`: `99-indi_auxiliary.rules` and
  `80-dbk21-camera.rules`. Ours are `99-indi-stable-indi_auxiliary.rules` and
  `80-indi-stable-dbk21-camera.rules`, so the numeric prefixes are preserved
  and no filename collides. This is the configuration in which the rename is
  genuinely load-bearing.

  Two traps in checking that, both hit: `indi-bin` records the files under
  `/lib/udev/rules.d/`, while they exist on disk at `/usr/lib/udev/rules.d/` —
  the same inode by way of the merged-`/usr` symlink — so `dpkg -S` on the
  physical path answers **"no path found"** for a file that is plainly owned
  (`LESSONS_LEARNED.md` #19). And `core/deb/rules` deliberately installs *ours*
  under `/usr/lib`, not `/lib`, because shipping through the alias symlink is
  an error on merged-`/usr`; the distribution's own packaging has not caught up
  with that.

A third exists and is out of scope for now: INDI recommends the **KStars
Flatpak**, which bundles INDI inside the sandbox. Nothing of ours is visible to
it and nothing of its is visible to us, so there is no collision surface — worth
stating so nobody spends a machine proving it.

### The changelog distribution — decided 2026-08-25

`core/deb/changelog` says `unstable`, and it stays that way. On an Ubuntu box
lintian reports it as an error:

```
E: indi-stable-core changes: bad-distribution-in-changes-file unstable
```

**That is lintian checking against the wrong vendor, not a defect.** Ubuntu's
lintian defaults to the `ubuntu` profile, whose list of known distributions
holds Ubuntu codenames only. `unstable` is a Debian suite. Run
`lintian --profile debian` and the error is gone — verified, 0 errors, exit 0.

Do not "fix" it by choosing another value, because **no value can satisfy
both**. The two lists are disjoint — checked by comparing them directly, and
their intersection is empty:

| value | `debian` profile | `ubuntu` profile |
|---|---|---|
| `unstable` | accepted | rejected |
| `resolute` | rejected | accepted |
| `candidate` (this project's channel) | rejected | rejected |

So any archive suite name is wrong under one vendor, and this project's own
channel names are wrong under both. `unstable` is kept because it is the
conventional value for a Debian-format source not aimed at a specific stable
release, and because the complaint it draws is fixable with a flag while the
alternatives' complaints are not — a permanently-firing error is worse than a
documented flag, since it trains people to stop reading lintian output.

`UNRELEASED` is a trap here for a separate reason: `dpkg-buildpackage` treats
it specially and refuses to sign such a build.

If this project ever publishes an apt repository, the field gains a second
consumer — `reprepro`/`aptly` read it to choose a target suite — and that is
the point to revisit this, because the channels are `release` and `candidate`.

### Two things to confirm on the box rather than infer

- ~~**Is `/usr/bin/indiserver` alternatives-managed on Debian?**~~ **Settled on
  the box, 2026-08-25 (Ubuntu 26.04, `indi-bin` 1.9.9+dfsg-6).** It is not.
  `dpkg -S /usr/bin/indiserver` returns `indi-bin`, `ls -l` shows a plain
  regular file rather than a symlink, and `update-alternatives --display
  indiserver` reports "no alternatives for indiserver". The Fedora finding
  transfers unchanged, so the namespaced `indiserver-stable` link name in
  `postinst`/`prerm` stays right for the same reason it is right there:
  registering the plain name would silently no-op against a real file.
- ~~**What the PPA's binary packages are called, and their SONAMEs.**~~
  **Settled 2026-08-25, and the guess in this file was wrong.** The PPA does
  *not* mirror the archive's split naming. It ships one library package:

  | | |
  |---|---|
  | `libindi1` | 2.2.4+202608202231~ubuntu26.04.1 |
  | `indi-bin`, `libindi-data`, `libindi-dev` | same version |
  | `kstars-bleeding` | 6:3.8.4+202608210609~ubuntu26.04.1 |

  Note `libindi1` carries a `1` from the old soversion while shipping 2.2.4;
  the name says nothing about the SONAMEs. Read from the ELF files themselves:
  `libindiclient.so.2.2.4` → SONAME `libindiclient.so.2`, and likewise for
  `libindidriver`, `libindiAlignmentDriver` and `libindilx200` — **identical to
  ours in both SONAME and upstream version.** Its `shlibs` advertises
  `libindiclient 2 libindi1`.

  It also carries `Conflicts`/`Replaces` on `libindidriver1`,
  `libindialignmentdriver1`, `libindi-plugins` and `libindi0`, so moving to the
  PPA removes those archive packages (and `indi-eqmod` with them). `libindiclient1`
  and `libindilx200-1` survive at 1.9.9, their `.so.1` not colliding.

  The PPA publishes for resolute, questing, plucky, oracular, noble and jammy —
  checked by fetching each `Release` file, so 26.04 is supported.

## Building and testing `indi-stable-3rdparty-libs`

`core/deb-3rdparty-libs/` is the packaging source, same role as `core/deb/` —
copy it to `debian/` inside an unpacked `indi-3rdparty` tree, **not** inside
an unpacked `indi` tree. Mirrors `core/rpm/indi-stable-3rdparty-libs.spec`:
same private prefix, same 8 bundled vendors, same licence-tier exclusions.
Read that spec's header comment for the full rationale; `core/deb-
3rdparty-libs/rules` carries only the Debian-specific mechanics.

```bash
sudo apt-get install -y devscripts debhelper dpkg-dev
tar xf indi-3rdparty-v2.2.4.1.tar.gz && cd indi-3rdparty-2.2.4.1
rm -rf debian                                       # SEE core/deb's own note -- load-bearing here too
cp -r ~/src/packaging/core/deb-3rdparty-libs debian
sudo dpkg -i indi-stable-core-libs_*.deb indi-stable-core-dev_*.deb   # Build-Depends
sudo apt-get build-dep -y .
dpkg-buildpackage -us -uc -b 2>&1 | tee /tmp/indi-stable-3rdparty-libs-deb.log
lintian --profile debian ../indi-stable-3rdparty-libs_*.changes
```

**The `indi-3rdparty` tarball ships its OWN `debian/` directory too**, same
trap `core/deb`'s own note describes for the `indi` tarball — confirmed hit
on the very first attempt here, 2026-08-26: `cp -r` without `rm -rf debian`
first landed the packaging source as `debian/deb-3rdparty-libs/`, a
subdirectory inside upstream's own (much larger, ~60-driver) `debian/`, with
upstream's `rules` silently left in charge. `ls debian` after the copy
should show `control`, `rules` and `indi-stable-3rdparty-libs-*` files and
nothing named `indi-apogee`/`indi-asi`/etc.

**Built, installed, verified and removed cleanly on the first real
`dpkg-buildpackage`**, 2026-08-26 — no build-time defects at all, unlike this
same package's RPM equivalent
(`core/rpm/indi-stable-3rdparty-libs.spec`), which took five real iterations
to reach a clean `mock` build. Two things made the difference, both decided BEFORE
building rather than found empirically:

- **Every `-dev` package `Depends:` on its runtime sibling by NAME
  (`= ${binary:Version}`), never `${shlibs:Depends}`** — matching
  `core/deb/control`'s own already-established `indi-stable-core-dev`
  pattern. This is what let the Debian side sidestep, by construction, the
  exact bug the RPM side's `-devel` subpackages hit empirically (an
  auto-generated `Requires` on the package's own unversioned `.so` symlink,
  unsatisfiable once `Provides` are stripped from everything under the
  private prefix) — Debian's dev-package convention never generates that
  Requires in the first place.
- **No `shlibs.local` and no `override_dh_shlibdeps` needed at all**, unlike
  `core/deb/rules`. Checked directly against every bundled vendor's
  `CMakeLists.txt` (the same reading `core/rpm`'s own spec comment
  documents): none of these libraries link against `libindi` or against each
  other, only against ordinary system libraries that already publish their
  own `shlibs`. `override_dh_makeshlibs:` (empty) is still needed, for the
  same "do not advertise a private library system-wide" reason as core.
  `DESIGN.md`'s prediction that this project's later Debian work would need
  a `shlibs.local` ("The Debian half of the metadata layer") turned out to
  be about `indi-stable-3rdparty-drivers`, not this package — drivers link
  against BOTH core's `libindi*` and these vendor libraries, neither of
  which ships a `shlibs` file, and that is genuinely unavoidable there.

**`lintian --profile debian` needed three overrides beyond `core/deb`'s own
two**, all tied to vendor-supplied prebuilt binary blobs rather than
anything this packaging compiled:

- `embedded-library tinyxml` and `hardening-no-relro` on
  `indi-stable-3rdparty-libs-asi` — properties of ZWO's own prebuilt
  `libASICamera2.so`/`libCAARotator.so`/`libEAFFocuser.so`. There is no
  source tree to relink against a system `tinyxml` or rebuild with hardening
  flags; ZWO ships only the `.bin`.
- `national-encoding` on `indi-stable-3rdparty-libs-sbig-dev` — a stray
  non-UTF-8 byte in SBIG's own `sbigudrv.h` comments, upstream's to fix.
- **The `embedded-library` override needed a trailing `*` wildcard**
  (`embedded-library tinyxml *`) where `hardening-no-relro` and
  `national-encoding` did not — lintian's override matching for that
  specific tag requires the bracketed per-file context to be wildcarded
  explicitly rather than defaulting to "any file"; a `mismatched-override`
  warning on the first attempt is what caught the omission.

**Left un-overridden, and not a packaging defect**: `udev-rule-missing-
uaccess` and `appstream-metadata-missing-modalias-provide` (29 + 24
instances) are upstream's OWN udev rule file content, not introduced by
this project's rename/re-home step; `debug-file-with-no-debug-symbols` (6
instances) is expected for prebuilt vendor blobs with no embedded debug
info; `initial-upload-closes-no-bugs` (16 instances) is inherent to this
never going through Debian's own NEW queue, the same as it presumably is
for `core/deb` too. Re-litigate only if any of these starts hiding a real
finding underneath it.

Verified against the built `.deb`s directly, same checklist as "What should
transfer" above: everything under `/opt/indi-stable` except
`/usr/lib/udev/rules.d` and the standard `/usr/share/doc`+lintian-overrides
paths debhelper always adds; nothing under `/usr/bin`; RPATH
(`/opt/indi-stable/lib`) present on the compiled (non-blob) libraries; udev
rules renamed with numeric prefixes preserved; no `shlibs`, `symbols` or
`Provides:` in any control archive. Installed and removed cleanly on
`ubuntuastro` in **configuration B** (PPA active, `libindi1` sharing SONAME
*and* version with ours) — `dpkg -V` clean on both sides throughout,
`/usr/bin/indiserver`'s hash unchanged, and a full `dpkg -r` of all 16
packages left no vendor-named file anywhere under `/opt/indi-stable` and no
`*3rdparty*` udev rule anywhere.

**The upgrade path is scripted too**,
`scripts/test-upgrade-path-3rdparty-deb.sh`, and looks different from
`test-upgrade-path-deb.sh` (core) for the same reason the RPM equivalent
looks different from its own core test: `indi-stable-3rdparty-libs` ships no
maintainer scripts at all (no `postinst`/`prerm`, no alternative), so there
is no `dpkg -D2` script-ordering trace to run and no stranded-admin-record
control to build. What it actually tests, matching
`scripts/test-upgrade-path-3rdparty.sh` (the RPM version of this exact
test): upgrading `-libs` alone while `indi-stable-core` stays installed and
untouched, no orphaned files after the upgrade (planted-file control), and
the upgraded libraries still resolve via `ldd`.

```bash
sudo bash scripts/test-upgrade-path-3rdparty-deb.sh [old-deb-dir] [new-deb-dir] [core-deb-dir]
```

Needs a scratch Debian-revision-bumped build to test against — same
uncommitted-scratch-copy trick as every other upgrade test in this project,
here just a `debian/changelog` version bump (`2.2.4.1-1` → `2.2.4.1-2`)
rather than an RPM `Release:` bump. All checks passed on the first run,
2026-08-26, **except one, caught and fixed the same run**:

- **The first version of this script asserted every vendor library carries
  an RPATH into the private prefix and failed on `libtoupcam.so`.** Reading
  its actual `readelf -d` output showed why that assertion was wrong, not
  the packaging: `libtoupcam.so` links only against `libc`/`libpthread`/
  `libm`/`librt`/`libdl` — ordinary system libraries always resolvable via
  the standard search path — so it genuinely needs no RUNPATH at all, and
  has none. `libapogee.so`, by contrast, does carry one. Confirmed this is
  not new: `core/rpm/indi-stable-3rdparty-libs.spec`'s own `check-rpaths`
  run already showed only 3 of the bundled libraries ever carry RPATH — this
  script's first draft just hadn't been checked against that fact yet. Fixed
  by scoping the RUNPATH assertion to `libapogee.so` specifically and
  keeping `ldd` (which DID pass for `libtoupcam.so` on the first run, and is
  the check that actually applies uniformly) as the check every library gets.

## Building and testing `indi-stable-3rdparty-drivers`

`core/deb-3rdparty-drivers/` is the packaging source, mirroring
`core/rpm/indi-stable-3rdparty-drivers.spec` exactly: same 8 vendor
drivers, same 47-entry `WITH_<X>=OFF` scope list, same `apogee_ccd.cpp`
`CFLAGS` fix, same `toupcam_test`/`omegonprocam_test` `EXCLUDE_FROM_ALL`
patch. Read that spec's header and `%build` comments for the full
rationale; `core/deb-3rdparty-drivers/rules` carries only the
Debian-specific mechanics.

```bash
tar xf indi-3rdparty-v2.2.4.1.tar.gz && cd indi-3rdparty-2.2.4.1
rm -rf debian                                              # ships its own, same trap as -libs's
cp -r ~/src/packaging/core/deb-3rdparty-drivers debian
sudo dpkg -i indi-stable-core*.deb indi-stable-3rdparty-libs-*.deb   # Build-Depends
sudo apt-get build-dep -y .
dpkg-buildpackage -us -uc -b 2>&1 | tee /tmp/indi-stable-3rdparty-drivers-deb.log
lintian --profile debian ../indi-stable-3rdparty-drivers_*.changes
```

**Built, installed, verified and removed cleanly on the first real
`dpkg-buildpackage`**, 2026-08-26 — no build-time defects at all, unlike
this same package's RPM equivalent (`core/rpm/indi-stable-3rdparty-drivers.spec`),
which took six real iterations. Every fix that spec needed (the 47
`WITH_<X>=OFF` scope list, the `toupcam_test`/`omegonprocam_test` patch, the
`apogee_ccd.cpp` `CFLAGS` fix, the `indi-mi` symlink files) was already
known and translated directly into `core/deb-3rdparty-drivers/rules` and
its `.install` files before this package was ever built — the RPM side had
already paid for finding them.

**This IS the package `DESIGN.md`'s "The Debian half of the metadata
layer" predicted would need `debian/shlibs.local`** — unlike `-libs` itself
(which needed none, `DEBIAN.md` above), every driver here links against
BOTH core's `libindi*` and a vendor library from `-libs`, and neither
upstream package ships a `shlibs` file (both deliberately skip
`dh_makeshlibs`). **The real finding was more nuanced than "add
`shlibs.local` and it works"**, though:

- **`shlibs.local` only actually engages for libraries with a real,
  numbered `SONAME`** — core's four `libindi*`, plus
  `libapogee`/`libfli`/`libPlayerOneCamera`/`libPlayerOnePW`/`libinovasdk`/
  `libsbig`. No shlibs-related warnings for any of these; `dpkg-deb -f`
  confirms `${shlibs:Depends}` contributed correctly.
- **It does NOT engage at all for the 17 libraries with no `SONAME` or an
  unversioned one** — `asi`'s five prebuilt ZWO blobs (confirmed with
  `readelf -d`: no `DT_SONAME` entry whatsoever) and `micam`'s/`touptek`'s
  twelve (a bare `libgxccd.so`/`libtoupcam.so`/... with no trailing digits
  at all). `dpkg-shlibdeps` warns `cannot extract name and version from
  library name '<name>.so'` for every one of these and skips them **before**
  it would ever consult `shlibs.local` — a different code path from "parsed
  fine, no shlibs entry found" (the ordinary case `shlibs.local` exists to
  solve), and this build produced no such warning-turned-failure only
  because `core/deb-3rdparty-drivers/control`'s own `Depends:` lines name
  `indi-stable-core-libs` and `indi-stable-3rdparty-libs-<vendor>`
  **literally**, not through `${shlibs:Depends}`. Had that explicit pinning
  ever been dropped in favour of relying on shlibs alone, these 17
  libraries' dependencies would have gone silently unspecified — exactly
  the failure `--ignore-missing-info` causes, arrived at by a different
  route. `core/deb-3rdparty-drivers/shlibs.local`'s own header carries the
  full finding; its entries for these 17 are kept (harmless, and correct if
  a future indi-3rdparty release ever gives them a real SONAME) but are not
  load-bearing today.

Verified against the built `.deb`s, same checklist as `-libs`'s own
section: everything under `/opt/indi-stable` except the standard
`/usr/share/doc`+lintian-overrides paths; nothing under `/usr/bin`; the
driver-catalogue rewrite (absolute paths, not bare names, looping over
every `indi_<vendor>.xml` — same mechanism as `core/deb/rules` and this
package's own RPM `%install`) lands correctly on both the simplest case
(apogee) and the most complex (touptek's 11 brands); `Depends:` correct on
every one of the 8 packages, confirmed by reading `dpkg-deb -f` directly
rather than trusting the build log. `lintian --profile debian` needed no
overrides beyond the standard `dir-or-file-in-opt`/`custom-library-search-path`
pair — unlike `-libs`, none of the vendor-blob-specific findings
(`embedded-library`, `hardening-no-relro`) applied, since those were
properties of the prebuilt blob itself, not anything that propagates to a
binary that merely links against it.

Installed and removed cleanly on `ubuntuastro` in **configuration B**,
alongside `indi-stable-core` and `indi-stable-3rdparty-libs` together: `ldd`
on the installed `indi_apogee_ccd` resolves all four private-prefix
libraries (`libindidriver.so.2`, `libindiAlignmentDriver.so.2`,
`libindiclient.so.2`, `libapogee.so.3`) to `/opt/indi-stable/lib`, and the
binary runs and prints its usage banner rather than dying at dynamic-link
time. Distro core INDI (`libindi1`/`indi-bin`, PPA active, same SONAME and
version as ours) stayed a clean bystander throughout — `dpkg -V` clean,
`/usr/bin/indiserver`'s hash unchanged — and a full `dpkg -r` of all three
source packages' worth of binary packages left `/opt/indi-stable`
completely absent, `ubuntuastro` back at its exact documented Configuration
B package count (`dpkg-query -W`: 1829 — `dpkg -l`'s own `grep '^ii'` count
undercounts by a few packages with non-standard status flags and should not
be used for this comparison; use `dpkg-query -W` instead).

**The upgrade path is scripted too**,
`scripts/test-upgrade-path-drivers-deb.sh`, run together with `-libs`'s own
upgrade for the same reason `scripts/test-upgrade-path-drivers.sh` (RPM)
gives: `-drivers` pins its `Depends`/`Build-Depends` to `-libs`'s exact
version, and the two are always promoted together. No maintainer-script
class of bug to trace (`-drivers` ships none), so what it actually tests,
matching the RPM version: `indi-stable-core` stays untouched, no orphaned
files across 24 binary packages (planted-file control), and the upgraded
driver still resolves via `ldd` **and runs**, printing its usage banner —
the check `-libs`'s own Debian upgrade test could not offer, since that
package ships no executables at all.

```bash
sudo bash scripts/test-upgrade-path-drivers-deb.sh \
    [old-libs-dir] [new-libs-dir] [old-drivers-dir] [new-drivers-dir] [core-dir]
```

Needs a scratch Debian-revision-bumped build of BOTH packages, same trick as
every upgrade test in this project — here, `-drivers`'s own scratch
`debian/changelog` bump (`2.2.4.1-1` → `2.2.4.1-2`) had to be built against
`-libs`'s matching `2.2.4.1-2` scratch build's `-dev` packages, AND every
literal version pin in `-drivers`'s own `control` file (`Build-Depends` and
`Depends`, 16 lines) had to be bumped to match — a `sed` across the whole
file, not just the changelog, unlike a normal release where only the
changelog needs touching. All checks passed on the first run, 2026-08-26 —
unlike `-libs`'s own Debian upgrade test, no script bugs found this time
either. `ubuntuastro` re-verified back at exact baseline afterward.

## Testing 3rdparty coexistence — `scripts/test-3rdparty-coexist-deb.sh`

Install/coexist/remove for `-libs`/`-drivers` had been verified by hand only
(the two "Building and testing" sections above); this is that pass scripted,
the Debian analogue of `scripts/test-config-b-coexist.sh` (core) applied to
`indi_apogee_ccd` instead of `indi_simulator_ccd`.

```bash
sudo bash scripts/test-3rdparty-coexist-deb.sh [libs-dir] [drivers-dir] [core-dir]
```

**It finds a real collision Fedora cannot** — `FEDORA.md` and `STATUS.md`
both record that Fedora ships no distribution `indi-3rdparty` package at all,
so RPM coexistence could only ever be checked against distro core INDI.
Ubuntu's *archive* is different: `apt-cache show indi-apogee` resolves to a
real package, and its `libapogee3t64` ships `libapogee.so.3` —
**byte-identical SONAME** to `indi-stable-3rdparty-libs-apogee`'s own,
confirmed 2026-08-26 by extracting the actual archive `.deb` and reading its
SONAME with `readelf`, not by trusting the package name
(`LESSONS_LEARNED.md` #11). This is the genuine collision case `DESIGN.md`'s
private-prefix rationale predicts, for real, on the Debian side.

**The archive package is downloaded, never installed.** `apt-get install
--dry-run indi-apogee` on `ubuntuastro` (checked 2026-08-26) shows it would
**remove `indi-bin` and `libindi1`** to satisfy `indi-apogee`'s pin to
`libindidriver1 (>= 1.9.9+dfsg)` — the archive's own `indi-3rdparty` is
incompatible with `ppa:mutlaqja/ppa`'s newer `libindi1`. It is orphaned in
the same shape `README.md` already documents for Fedora's `indi-3rdparty`
packaging, just found from the opposite direction: there, upstream abandoned
the RPM packaging; here, the archive's packaging is stranded behind the
version the PPA moved past. Installing it would destroy configuration B's own
precondition, so STEP 2 uses `apt-get download` plus `dpkg-deb -x` into a
scratch directory instead — the real artifact's bytes, without ever touching
`dpkg`/`apt` state. It is never recorded in the baseline snapshot and needs
no teardown.

**The forced-`LD_LIBRARY_PATH` control (STEP 6) is stronger than core's own
version for the same reason.** `test-config-b-coexist.sh`'s control forces
`LD_LIBRARY_PATH` at the distribution's own live libdir, which already holds
a real colliding library because distro core INDI is actually installed in
configuration B. No 3rdparty vendor library is ever actually installed
system-wide on this box — the archive's `indi-apogee` cannot coexist with the
PPA, so it is never live — so this script's control instead forces
`LD_LIBRARY_PATH` at the scratch directory holding the extracted archive
`libapogee.so.3` from STEP 2. It worked identically: `DT_RUNPATH` loses to
`LD_LIBRARY_PATH`, exactly as `DESIGN.md` already documents as an explicit
opt-out rather than a defect.

All checks passed on the first run, 2026-08-26, no script bugs found:
distro core INDI (`libindi1`/`indi-bin`) stayed a clean bystander
(`dpkg -V` clean, `/usr/bin/indiserver`'s hash unchanged) with 24 3rdparty
packages installed on top of it; none of those 24 ship anything under
`/usr/bin` or `/usr/include`; `indi_apogee_ccd`, run normally, maps
`libapogee.so.3` from `/opt/indi-stable/lib` and nowhere else; forced with
`LD_LIBRARY_PATH` at the real archive artifact, it maps that one instead,
proving the RUNPATH-vs-`LD_LIBRARY_PATH` precedence mechanism has teeth
against a genuine SONAME-colliding artifact rather than an assumed one.
`ubuntuastro` re-verified back at its exact Configuration B baseline
afterward (`dpkg-query -W`: 1829 packages, `/opt/indi-stable` gone).

## Building and testing `indi-stable-pyindi-client`

`pyindi-client/deb/` is the packaging source -- a new top-level directory,
not under `core/`, since `pyindi-client` is a genuinely separate upstream
project (`indilib/pyindi-client`), not part of `indilib/indi` or
`indilib/indi-3rdparty`. See `DESIGN.md`, "`pyindi-client` -- packaging
decisions", 2026-08-26, for the two decisions made before writing any of
this: building from the untagged `2.2.0` PyPI release rather than the last
real git tag (`v2.1.2`, which needs a static `libindiclient.a` this
project's `core/` does not build), and installing the built module to the
ordinary system Python location rather than `/opt/indi-stable`.

```bash
sudo apt-get install -y devscripts dh-python swig pkg-config
pip download --no-deps -d /tmp/pyindi pyindi-client   # or fetch the sdist directly
tar xzf pyindi_client-2.2.0.tar.gz && cd pyindi_client-2.2.0
cp -r ~/src/packaging/pyindi-client/deb debian
sudo dpkg -i indi-stable-core*.deb   # Build-Depends
dpkg-buildpackage -us -uc -b 2>&1 | tee /tmp/indi-stable-pyindi-client-deb.log
lintian --profile debian ../indi-stable-pyindi-client_*.changes
```

**Built, installed and verified cleanly on the second real
`dpkg-buildpackage`**, 2026-08-26 -- one real defect found and fixed, not
zero, unlike `-libs`/`-drivers`' clean first attempts:

- **`dh_auto_clean` failed outright on the first attempt**: `This feature
  was removed in compat 12` for the auto-detected `python_distutils`
  buildsystem. `override_dh_auto_configure`/`build`/`install` replace three
  of the four `dh_auto_*` steps, but say nothing about `clean`, so it still
  ran through debhelper's own buildsystem auto-detection -- which, given a
  bare `setup.py`, picks the now-removed legacy path regardless of what the
  other three overrides do. Fixed by pinning `--buildsystem=pybuild`
  explicitly at the top of `debian/rules`; all four `override_dh_auto_*`
  targets still take precedence over pybuild's own recipes, so nothing else
  changed.
- **The install step needs `setup.py build`, not `setup.py build_ext`
  alone** -- caught by hand before the first real `dpkg-buildpackage`, not
  by a failed build: `build_ext` only compiles the extension; `build_py`,
  which copies `PyIndi.py`/`__init__.py` into the build tree, is a separate
  step `build_ext` alone skips. The resulting directory has no
  `__init__.py`, so Python treats `PyIndi` as an implicit PEP 420 namespace
  package -- `import PyIndi` **succeeds** (`PyIndi.__file__` is `None`) and
  `PyIndi.BaseClient()` fails with `AttributeError`, a check that looks like
  it passed until read carefully (`LESSONS_LEARNED.md` #1's shape, found
  before it ever reached a defect report).

**The real, load-bearing collision this fixes**: configuration B has
`libindi-dev` installed, whose own **unversioned** `libindiclient.so`
symlink sits in the ordinary system libdir (`/usr/lib/x86_64-linux-gnu`) at
the exact same SONAME as ours (`libindiclient.so.2`) -- confirmed 2026-08-26
by building unpatched once and reading the result: `readelf -d` on the
resulting extension showed `NEEDED libindiclient.so.2` correctly (SONAMEs,
unlike unversioned link-time symlinks, are baked in regardless of which
`-L` path won), but the **link-time** choice of *which* `libindiclient.so`
satisfies `-lindiclient` is exactly what upstream's own default
`library_dirs` ordering (`/usr/lib`, `/usr/lib64`, `/lib`, `/lib64`, ours not
included at all) would have gotten wrong. `debian/rules` replaces
`library_dirs` with `["/opt/indi-stable/lib"]` alone -- not appended, not
reordered -- so there is no ordering left to get wrong, plus the same
`-Wl,-rpath,/opt/indi-stable/lib` every other component in this project
relies on for the runtime half of the guarantee.

**`dh_python3` needs its own correction, unrelated to coexistence.** The
first successful build produced `Depends: ..., python3-bottle,
python3-dbus, python3-requests` -- read from `pyproject.toml`'s `[project]
dependencies`, which upstream declares for `examples/pyindi-stellarium.py`
and `examples/pyindi-synscan.py`, neither of which this package ships
(`packages=["PyIndi"]` only). `dh_python3` derives `${python3:Depends}` from
the *installed* `.egg-info/requires.txt`, not from source, so
`override_dh_auto_install` removes the installed `.egg-info` directory
outright after `setup.py install` -- confirmed by rebuilding and reading
`dpkg-deb -f ... Depends`, which dropped all three the same run.

Verified against the built `.deb` directly: everything lands under
`/usr/lib/python3/dist-packages/PyIndi/` and the standard
`/usr/share/doc`+lintian-overrides paths, nothing under `/opt/indi-stable`
at all (this package does not use the private prefix for its own files, see
`DESIGN.md`); `Depends:` reads `indi-stable-core-libs, libc6, libgcc-s1,
libstdc++6, python3 (<< 3.15), python3 (>= 3.14~), python3:any` and nothing
else, confirmed via `dpkg-deb -f`; `lintian --profile debian` needs exactly
the one override every RPATH-carrying component in this project needs
(`custom-library-search-path`) plus the same unoverridden
`initial-upload-closes-no-bugs` every package here carries, 0 errors.

**Installed and imported for real on `ubuntuastro` in configuration B**,
alongside `indi-stable-core` (`libindi1`/`indi-bin`, PPA active, same
SONAME and version as ours): `python3 -c 'import PyIndi;
PyIndi.BaseClient()'` succeeds from a plain shell with no `PYTHONPATH`
needed, `PyIndi.__file__` correctly resolves under
`/usr/lib/python3/dist-packages/`, and `ldd` on the installed
`_PyIndi*.so` resolves `libindiclient.so.2` to `/opt/indi-stable/lib`, not
the distribution's copy at the identical SONAME. Distro core INDI stayed a
clean bystander throughout (`dpkg -V libindi1 indi-bin` clean). Removed
cleanly; `ubuntuastro` re-verified back at its post-toolchain baseline
afterward (`swig`/`pkg-config`/`dh-python`/`devscripts`/`lintian` now part
of the box's persistent build toolchain, the same way `devscripts` already
was for `core/`'s own build -- not torn down between sessions, same as
`mock` on `fedoraastro`).

Coexistence and upgrade survival are scripted, 2026-08-27:

```bash
sudo bash scripts/test-pyindi-client-coexist-upgrade-deb.sh [pyindi-dir] [core-dir]
```

`pyindi-client` has no maintainer scripts and no alternative to trace, so
this checks something narrower than core's or 3rdparty's own upgrade tests:
with configuration B's `libindi1` installed (identical `libindiclient.so.2`
SONAME), does `import PyIndi` resolve into the private prefix on a fresh
install, and does it keep resolving correctly -- to the genuinely upgraded
file, not a stale copy -- after `indi-stable-core`/`-libs` alone are
upgraded underneath an already-installed, untouched pyindi-client. Reuses
the existing `2.2.4.2-1`/`2.2.4.2-2` core builds in `~/build` (the same pair
core's own upgrade test uses); no new build needed. All checks passed on the
first run -- full detail in `STATUS.md`.
