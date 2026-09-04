# indi-stable

Maintained RPM and DEB packages for the [INDI Library](https://indilib.org),
built from INDI's own **stable release tags**.

> **Status: packages are built and released automatically, but there is no
> `dnf`/`apt` repository to add yet.** Every component — core, the per-vendor
> `3rdparty` drivers, and `pyindi-client` — is built on both Fedora and
> Debian/Ubuntu, gated by an automated install-and-run check, and published
> as [GitHub Releases](../../releases) whenever a new upstream version
> passes. Install by downloading the `.rpm`/`.deb` for your distro from the
> latest release of the component you want and installing it directly
> (`dnf install ./<file>.rpm` / `apt install ./<file>.deb`) — see
> "Installing" below for the exact files. A COPR/OBS repository, so this
> becomes a one-line `dnf copr enable`, is a planned addition, not the
> current mechanism; the "Planned scope" section below describes that
> future state.

> **Unofficial.** This is a third-party packaging effort. It is not
> affiliated with, endorsed by, or supported by the INDI project. Please do
> not report problems with these packages to INDI upstream — open an issue
> here instead.

## Why this exists

INDI's own packaging effort is Debian/Ubuntu-first. Upstream maintains a PPA
directly, and it works well.

RPM-based distributions have no equivalent. What exists is:

- Fedora's own `indi-3rdparty-drivers` package, maintained by Fedora
  packagers rather than INDI upstream — but orphaned before Fedora 44 branched
  (last live in F43), so a current Fedora installer gets nothing from Fedora's
  own repos for third-party INDI drivers at all. Even while it was maintained,
  coverage was narrow by Fedora's own binary-blob policy rather than by
  neglect: it built only the two vendor SDKs shipping real source,
  `libapogee` and `libfli`. The qhyccd driver, for instance — the one that
  started the investigation behind this project — was never in it, because
  QHY's SDK is a binary blob like most of the rest.
- A volunteer COPR that tracks git *master* rather than releases, and which
  has gone dormant and changed maintainers at least once.

So a Fedora user who wants a driver outside the official package's coverage
ends up building INDI from source and working through compile errors — which
is exactly the experience that prompted this project.

`indi-stable` aims to be the boring, dependable option for those users:
stable releases, packaged consistently, on RPM and DEB alike, updated
automatically so it does not quietly go stale.

## Design principles

**Coexistence, not replacement.** Installing these packages never removes,
overwrites, or shadows a distribution INDI. Someone running KStars/Ekos or
Stellarium against their distro's INDI can install this without their setup
changing underneath them. Every file lands in a private prefix
(`/opt/indi-stable`), and `indiserver` is offered through `alternatives(8)`
under the namespaced name `indiserver-stable` rather than claiming
`/usr/bin/indiserver` outright — on Fedora that path is an ordinary file
`libindi` owns, not a symlink, so `alternatives` cannot register over it
(see DESIGN.md for the finding and the namespaced-link resolution).

This is stricter than it may look. SONAME versioning alone does *not* give
coexistence here: because this project ships stable releases just as the
distribution does, our `libindiclient.so.2` and theirs routinely share a
SONAME. A private prefix is what actually keeps them apart.

**Stable tags, gated promotion.** Builds track upstream release tags
automatically, but land in a `candidate` channel first and are promoted to
the `release` channel only after passing an automated gate (clean build,
clean install into a fresh container, `indiserver` starts and a driver
loads). Automation is deliberate — a packaging effort going stale because a
human stopped triggering builds is the failure this project exists to avoid.

**Portable build logic.** Spec files, `debian/` metadata and the promotion
scripts live here, in git. COPR and OBS are compute and hosting that this
repository drives, not where the packaging is defined.

## Planned scope

| Target | Built via | Format |
|---|---|---|
| Fedora | COPR | RPM |
| RHEL / Rocky / AlmaLinux | COPR | RPM |
| Ubuntu | OBS | DEB |
| Debian | OBS | DEB |

Components: `indi-stable-core`, per-driver `indi-stable-3rdparty-*`, and
`indi-stable-pyindi-client`.

**Why a pyindi-client build at all?** `pyindi-client`'s Python extension is a
SWIG-generated C++ binding, compiled from source on `pip install` against
whatever `libindi`/`libindi-dev` headers happen to be on the machine at that
moment. A version mismatch there does not always fail loudly — it can
produce an importable module whose generated wrapper calls a symbol the
compiled extension never exports, which then surfaces only as a silent
connection timeout deep inside libindi's own C++ callback thread, not as a
build error. This is not hypothetical: a real, recorded incident had two
accounts on one machine run the identical `pip install` against identical,
unchanged headers and get different results, one broken (`DESIGN.md`,
"Evidence, 2026-09-03"). Shipping this binding pre-built and version-matched
against `indi-stable-core` removes that whole failure class, rather than
asking every user to get a local compile right on their own — it is in fact
the component whose build problems started this project in the first place.

## Installing

No `dnf`/`apt` repository exists yet (see "Planned scope" above), so
installing means downloading the right file from a component's
[latest release](../../releases) and installing it directly. Each release
carries both distros' files together; grab the ones for yours.

For `indi-stable-core`, the release tagged `indi-stable-core-<version>`
carries `indi-stable-core-<version>.fc44.x86_64.rpm` and
`indi-stable-core_<version>_amd64.deb` (plus `-libs`/`-devel`/`-dev`
counterparts — install the base package and `-libs` together; `-devel`/`-dev`
are only needed for building against this project, e.g. `pyindi-client`
itself does):

```
# Fedora / RHEL / Rocky / Alma
sudo dnf install ./indi-stable-core-libs-<version>.fc44.x86_64.rpm \
                 ./indi-stable-core-<version>.fc44.x86_64.rpm

# Debian / Ubuntu
sudo apt install ./indi-stable-core-libs_<version>_amd64.deb \
                  ./indi-stable-core_<version>_amd64.deb
```

`indi-stable-3rdparty-<version>` and `indi-stable-pyindi-client-<version>`
follow the same shape — the release tagged with the component's own name
carries every `.rpm`/`.deb` that release built. A release tag ending in
`-N` (`N` > 1) is a **repackage**: the same upstream version rebuilt at a
new packaging revision, not a new upstream release — pick the highest `-N`
for a given version.

To run this build's `indiserver` on a machine that also has a distribution
INDI, use the namespaced alternative rather than the plain `indiserver` name
(RHEL family: `alternatives`; Debian family: `update-alternatives`):

```
sudo alternatives --config indiserver-stable
```

This registers a new command, `indiserver-stable`, rather than repointing
the system's own `indiserver` — the two coexist in `PATH` rather than one
replacing the other.

### Selecting this build's *drivers*

`indiserver-stable` gets you this build's **server**. To get this build's
**drivers**, point a driver-listing tool at this build's catalogue:

| Tool | Setting |
|---|---|
| KStars / Ekos | "INDI drivers XML directory" → `/opt/indi-stable/share/indi` |
| INDI Web Manager | `--xmldir /opt/indi-stable/share/indi` |

Our catalogue names each driver by **absolute path**, so selecting one launches
the binary in `/opt/indi-stable/bin` against the libraries in
`/opt/indi-stable/lib`. Nothing is added to `PATH` and nothing system-wide
changes — the setting belongs to that one application, and pointing it back at
`/usr/share/indi` restores the distribution's drivers exactly.

**Leave the setting alone and none of this build is used at all.** That is the
default and it is the case that matters most: verified on a live Ekos session
with these packages installed, every process the session spawned — server,
drivers, libraries, and a `dlopen`'d plugin — resolved to `/usr`.

Two entries in the catalogue stay bare on purpose
(`indi_simulator_spectrograph`, `indi_pegasus_uch`): no build ships them, and
inventing a path would turn a driver that is merely absent into one that fails
with a wrong path.

Note the driver **list** looks identical either way — both catalogues carry the
same driver names, and only the hidden binary path differs — so you cannot tell
which install is in use by reading the list. Check the running processes if you
need to know.


To actually run this build's drivers, give `indiserver-stable` an **absolute
path**:

```
indiserver-stable /opt/indi-stable/bin/indi_simulator_ccd
```

That resolves correctly — the driver maps this build's libraries out of the
private prefix, verified from a live process's `/proc/<pid>/maps`. It is the
same thing the catalogue setting above does for you, one driver at a time.

## Building

**Both packagings build and are verified end to end**, each against a
distribution INDI sharing its library SONAMEs — the RPM on Fedora 44, the DEB
on Ubuntu 26.04 with `ppa:mutlaqja/ppa`. [FEDORA.md](FEDORA.md) and
[DEBIAN.md](DEBIAN.md) carry the by-hand build procedures, the checklists for
verifying the coexistence guarantees, and what has been confirmed on each. The
coexistence checks are scripted for both distributions in `scripts/`.

Nothing is published yet — there is no repository to add, and these packages
must be built from source for now.

## Repository layout

```
STATUS.md          what is left to do
FEDORA.md          Fedora build procedure and verification checklist
DEBIAN.md          the same for Debian/Ubuntu
DESIGN.md          the full rationale for every decision here
LESSONS_LEARNED.md gotchas worth not rediscovering
core/              spec + debian metadata for INDI core and 3rdparty
                   (per-driver packaging; RPM and Debian both built)
scripts/           coexistence test harnesses
pyindi-client/     the Python binding, built against this project's core.
                   Debian and RPM sides both built, released, and gated by CI.
patches/           per-version fixes applied at build time (none needed yet)
```

## License

The packaging metadata and scripts in this repository are MIT (see
[LICENSE](LICENSE)). INDI itself remains under its own LGPL/GPL terms, which
govern the software these packages build and distribute.
