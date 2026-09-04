# indi-stable — packaging project instructions

Maintained RPM and DEB packages for the INDI Library, built from INDI's own
**stable release tags**. Sole maintainer: Will. Unofficial — not affiliated
with or endorsed by the INDI project, and the README must keep saying so.

**This is not ACS.** ACS (`~/src/ACS`) is Will's astrophotography control
app and is a separate repository. It will eventually be *a consumer* of
these packages, but it has no special access here and no veto over this
project's release gate. Do not couple them.

## Before doing anything

**Read `STATUS.md` first, every session.** It is the only file that says what is
left to do. Everything else is stable reference.

| Question | File |
|---|---|
| What is left? | **`STATUS.md`** — the living doc |
| How do I build and verify this on Fedora? | `FEDORA.md` |
| ...on Debian/Ubuntu? | `DEBIAN.md` |
| Why is it done this way? | `DESIGN.md` |
| What has bitten us before? | `LESSONS_LEARNED.md` |

**Each fact lives in exactly one file; the others link to it.** Do not restate a
claim across documents — a claim quoted between documents instead of re-checked
is how this line of work already produced one correction that had propagated
into eight files. `STATUS.md` in particular carries no rationale, only state.

**`bash scripts/check-docs.sh` catches the mechanical half of this** — paths
that no longer exist, one path given two different sha256s, cross-references
and `LESSONS_LEARNED.md #N` numbers that no longer resolve. It needs no root
and touches nothing. It cannot see stale *prose* ("the Debian packaging has not
been built yet" was true when written), so it is a floor, not a substitute for
reading.

**It runs automatically on commit**, via `.githooks/pre-commit`, against the
*staged* tree rather than the working tree. Each clone needs this once, or the
hook is silently inert:

```bash
git config core.hooksPath .githooks
```

Bypass a specific commit with `git commit --no-verify`. If a doc change is
being rejected for something the checker gets wrong, fix the checker — an
exception added to its allowlist must be pinned to the measured values, not to
a path, or it switches the check off exactly where a defect was once found.

`STATUS.md` is *living*: when work completes, **delete the item** rather than
annotating it as done. Git holds the record, and the commit that finished the
work is where the evidence belongs.

## The one rule everything else serves

**Coexistence. Installing these packages must never remove, overwrite, or
shadow a distribution INDI.** Plenty of people run KStars/Ekos or Stellarium
against their distro's INDI, and `kstars` depends on `indi-bin`. A package
that conflicts with `indi-bin` uninstalls Ekos.

Concretely, and all of it load-bearing:

- **Everything installs under `/opt/indi-stable`** — the same path on every
  distro, deliberately (see DESIGN.md for why `/opt` and not `%{_libdir}`).
- **No packaged file may land under `/usr/bin`.** `indiserver` is offered
  through `alternatives(8)`, which links to a *path* — the real binary stays
  in the private prefix. If you find yourself moving a binary into
  `/usr/bin` under a suffixed name, that is the mistake the first spec draft
  made; it is unnecessary.
- **SONAME versioning is NOT sufficient here** and assuming it is will
  reintroduce the bug. It is what lets a 1.9.9 distro build coexist with a
  2.x one, but this project ships stable releases exactly as the distro
  does, so our `libindiclient.so.2` and theirs routinely share a SONAME.
  The private prefix plus RPATH is what actually separates them.
  A box where the SONAMEs *do* differ — a stock Debian or Ubuntu, still on
  1.9.9 — therefore cannot test this at all, and must not be mistaken for one
  that passed. See `DEBIAN.md`.
- **Headers must never go to `/usr/include/libindi`.** They are not
  SONAME-versioned and `/usr/include` wins the compiler search order, so a
  distro `-devel` package would silently win.
- **RPATH into the private libdir is intentional.** Do not "fix" a linter
  that complains about it — that is the coexistence guarantee itself.

## Upstream facts that constrain the packaging

`UDEVRULES_INSTALL_DIR` being the one non-derived install path; the relative
`CMAKE_INSTALL_LIBDIR`; the tarball's stripped leading `v`; `FIX_WARNINGS=OFF`;
the `check-rpaths` allowlist. All five are in **`DESIGN.md`, "Upstream
build-system facts"**, with the source references. Each is the reason a specific
spec line looks the way it does — read them before changing one.

## Verification discipline

This project inherits a hard-won standing rule from ACS: **passing checks
are not evidence the real path works, only that the checked paths are
correct.** Every first-run in this line of work so far has surfaced exactly
one thing nobody had exercised.

- **`LESSONS_LEARNED.md` is the accumulated form of this rule.** Read it before
  writing a check. The highest-value entries are #1 (a check that passes by
  finding nothing must be shown able to find something) and #2 (read the
  artifact, not the log).
- The checks have been wrong more often than the packaging: five checklist
  steps have passed while testing nothing, and two have cried wolf. The
  packaging itself has been right every time since the metadata fix.
- When a build or install step runs for real, **paste the output and read it
  together** rather than reporting "it worked".
- Verify claims about external tools by running them, not by recalling how
  they behave.

## Repository layout

```
STATUS.md          what is left, and machine state -- READ FIRST, and the only
                   file that should change often
FEDORA.md          Fedora build procedure, checklist, verification
DEBIAN.md          the same for Debian/Ubuntu
DESIGN.md          the full rationale; the living plan doc
LESSONS_LEARNED.md generic gotchas that cost real time; enforcement-first
core/rpm/          indi-stable-core.spec, plus indi-stable-3rdparty-libs.spec
                   and indi-stable-3rdparty-drivers.spec -- one file per
                   source package, all RPM/Fedora
core/deb/          indi-stable-core's packaging source; copy to debian/ in an
                   unpacked tree to build
core/deb-3rdparty-libs/  same role, for indi-stable-3rdparty-libs
core/deb-3rdparty-drivers/  same role, for indi-stable-3rdparty-drivers
scripts/           test harnesses (see FEDORA.md and DEBIAN.md -- the RPM and DEB
                   sets are separate, and the `-deb` suffix marks the Debian
                   ones), plus check-docs.sh for doc staleness; tag
                   polling/promotion not started
pyindi-client/     the Python binding, built against this project's core.
                   pyindi-client/deb/ and pyindi-client/rpm/ -- its Debian and
                   RPM packaging source, respectively
patches/           per-version fixes, applied by %autosetup -p1 / quilt (empty --
                   the current tag needs none)
```

## Conventions

- **Channels are `release` and `candidate`**, never "stable"/"testing" —
  "indi-stable's stable channel" is nonsense and "indi-stable's testing
  channel" reads as a contradiction.
- **Commits:** `component: short description`, then a body explaining *why*
  and what was actually verified versus assumed. Each commit stands alone.
  Multi-file changes land as separate logical commits, not one lump.
- **The MIT license covers this repo's contents only** — spec files,
  `debian/` metadata, scripts. INDI itself stays under its own LGPL/GPL, and
  the README and `debian/copyright` must keep saying so.
- **No CI until both packagings have built by hand at least once.**
  Automating a build that has never succeeded means debugging the packaging
  and the automation simultaneously, through the slower feedback loop.

## Current state

**Deliberately not recorded here — see `STATUS.md`.** State duplicated into an
always-loaded instruction file is state that goes stale without anyone noticing;
this section previously carried a `BuildRequires` risk that had been retired and
a machine description two sessions out of date.

The two things stable enough to belong in this file:

- **Work happens on the `development` branch.** Will merges to `main` himself,
  and a global settings deny rule blocks pushing there anyway.
- **Both `core/` packagings are built and verified end to end**, each against a
  distribution INDI sharing its SONAME. That is the shape of the project. The
  specifics — what is left — are in `STATUS.md`.
