# indi-stable — Packaging Project Plan

Standalone project, independent of ACS. Produces maintained RPM and DEB
packages for INDI core, indi-3rdparty drivers, and pyindi-client, built from
INDI's own **stable tagged releases**.

Positioned as a reliable third-party alternative to the current situation:
Debian/Ubuntu has an upstream-maintained PPA, but RPM/Fedora support is
delegated to a volunteer COPR that has already gone stale and changed hands
once (`xsnrg` → `jimtjames`), and tracks git master rather than releases.

**Not affiliated with or endorsed by the INDI project.** State that plainly
in the README, same posture the existing community COPRs take.

---

## Decisions (settled 2026-08-23)

| | |
|---|---|
| **Name** | `indi-stable` |
| **Hosting** | New GitHub org (independent of ACS and of a personal account) |
| **License** | MIT, for the packaging metadata and CI scripts only |
| **v1 distro scope** | Fedora, RHEL/Rocky/Alma, Ubuntu, Debian |
| **Package identity** | Distinct namespace — never replaces distro packages |
| **Version policy** | INDI's stable tags only, human-gated promotion |

### On the name and the channel-name collision

`indi-stable` names the actual differentiator: **stable releases**, versus
the existing community COPRs that track git master and are named
`*-bleeding`. That contrast is the project's whole pitch, and it lands
immediately for anyone who has met those COPRs.

It does collide with the obvious channel naming, though — "indi-stable's
stable channel" is nonsense, and "indi-stable's testing channel" reads like
a contradiction. **Resolution: the channels are `release` and `candidate`,
not `stable`/`testing`.**

- `indi-stable` → the repo users add. Promoted, gated builds.
- `indi-stable-candidate` → automated builds awaiting the gate. Not
  advertised in the README's install instructions.

"Candidate" is standard release-engineering vocabulary and avoids reusing
the word that is already in the project name.

### On the license

MIT covers **this repo's contents only**: spec files, `debian/` control
files, promotion scripts, CI workflows. It has no bearing on INDI's own
LGPL/GPL licensing, which governs the software being packaged and travels
with those binaries unchanged. Say so explicitly in the README so nobody
reads an MIT badge as a claim about INDI itself.

---

## Why this exists (for the README / DESIGN doc)

- **Debian/Ubuntu:** INDI upstream maintains `ppa:mutlaqja/ppa` directly.
  This project doesn't need to displace that — it rides alongside, and
  matters mainly for Debian proper (which the PPA does not serve, since
  Launchpad PPAs are an Ubuntu mechanism) and for version coherence with
  the RPM side.
- **Fedora/RPM:** no upstream-maintained channel at all. Fedora's own
  official `indi-3rdparty-drivers` package exists and is reasonably current
  (2.1.2 as of the Fedora 41 cycle), but driver coverage is incomplete —
  qhyccd, for instance, never made it into the official package. The only
  alternative is a volunteer bleeding-edge COPR with a documented history of
  going dark.
- **The gap filled:** version-coherent, deliberately-promoted **stable
  release** packages, on RPM and DEB alike, that do not go stale because
  promotion is automated rather than depending on someone remembering.

---

## Scope for v1

**Components built:**
- `indi-stable-core` — from `indilib/indi` tags
- `indi-stable-3rdparty-<driver>` — from `indilib/indi-3rdparty` tags,
  per-driver subpackages (same granularity Fedora's official package
  already uses, so users install only what they need)
- `indi-stable-pyindi-client` — built against this project's own core,
  version-matched. This is the component that started the entire
  investigation (SWIG bindings will not compile against mismatched
  headers), so it belongs in scope rather than left to users to
  pip-compile.

**Build/hosting infrastructure — two systems, not four:**

| Target | Built by | Format |
|---|---|---|
| Fedora (current + N-1) | COPR | RPM |
| RHEL / Rocky / Alma | COPR (EPEL + Alma/Rocky chroots) | RPM |
| Ubuntu (current LTS + interim) | OBS | DEB |
| Debian (stable) | OBS | DEB |

This is the finding that makes a four-distro v1 tractable rather than
reckless:

- **COPR builds many chroots from one spec in one project**, and has added
  dedicated AlmaLinux/RockyLinux/EuroLinux chroots alongside EPEL. Adding
  the RHEL family is ticking chroot boxes, not standing up a second system.
- **Launchpad PPAs are Ubuntu-only**, so Debian would have needed a second
  mechanism anyway. **OBS builds Debian and Ubuntu both** (and is explicitly
  built for cross-distro packaging — ~140k packages across 21 base
  distributions), so putting *both* DEB targets on OBS is fewer moving parts
  than Launchpad-for-Ubuntu plus something-else-for-Debian.

Net: **one spec file, one `debian/` directory, two build services.**

**Why not put everything on OBS** (it can build RPM too): Fedora users
already know `dnf copr enable`, indilib.org's own download page already
sends Fedora users to COPR, and this project is trying to be the
*discoverable, expected* answer for exactly those people. Using the idiom
they already know beats consolidating onto one system they don't.

**Not in scope:** a bleeding/master-tracking channel. Already served by the
existing community COPR; duplicating it adds surface for no benefit.

---

## Versioning policy

**"Stable" means INDI's own stable tagged releases** — core and 3rdparty
tracked as independent version axes, since the two repos already release on
separate cadences (ACS's own pins are deliberately unequal for this exact
reason). Never git master.

- A scheduled GitHub Actions job diffs the latest upstream tag against the
  last one built, per component. Polling is the only option — there is no
  webhook subscription to another org's release tags.
- A new tag builds automatically into `indi-stable-candidate`.
- Promotion to `indi-stable` — the repo the README tells people to add —
  requires passing this project's **own self-contained gate**:
  - clean build on every target
  - clean install into a fresh container
  - smoke test: `indiserver` starts, a representative driver loads
- **The gate must never be ACS-specific.** If "promoted" meant "passed ACS's
  sim harness," this project would be logically coupled to ACS while only
  pretending to be independent. ACS consumes the `indi-stable` channel like
  any other downstream user, pins a version, and runs its own additional
  validation before adopting a bump — with no special access or veto.
- No manual click-to-build in the normal path. Automation is precisely what
  prevents a repeat of the existing COPR's stale-maintainer failure. A human
  is involved only when the gate fails.

Core/3rdparty version pairing stops being two hand-maintained constants (as
in ACS's `setup_indi_core.py`) and becomes a real
`Requires: indi-stable-core >= X, < Y` dependency — enforced by the package
manager rather than by hoping two hardcoded numbers still agree.

---

## Package identity and coexistence

**Distinct namespace; never replaces the distro's packages.** Same reasoning
as ACS's own install-time policy: never silently uninstall or shadow
something the user or another package deliberately installed.

A distinct package *name* alone does not achieve this — the collision risk
is at the **file path** level, and (see below) at the **package metadata**
level as well. Handled per artifact type:

- **Shared libraries.** SONAME versioning is *not* sufficient here.
  It is what gives distro 1.9.9 and a 2.x build free coexistence today
  (`.so.1` vs `.so.2`), but this project ships *stable releases* just as
  Fedora's official package does, so `indi-stable`'s `libindiclient.so.2`
  and Fedora's `libindiclient.so.2` will routinely share a soname — a real
  collision at the standard path. **Install libraries under a private
  namespaced path** (`/opt/indi-stable/`), with `rpath` set on this
  project's binaries and its pyindi-client extension.
- **Headers.** Not sonamed at all. Installing to `/usr/include/libindi`
  would recreate the exact shadowing bug ACS already fixed once
  (`/usr/include` beats `/usr/local/include` in compiler search order).
  Private path: `/usr/include/indi-stable/`.
- **Binaries** (`indiserver`, drivers). Plain filenames in `/usr/bin`, so
  two packages shipping `indiserver` collide regardless of package name.
  Use **`alternatives` (RPM) / `update-alternatives` (Debian)**: install as
  `indiserver.indi-stable`, register as an alternative provider for
  `indiserver`, let the distro's own tooling arbitrate. Standard and
  review-safe — unlike a nonstandard `/usr/local`-style prefix, which both
  distros' packaging guidelines forbid real packages from touching — and
  visible/reversible via `alternatives --config indiserver`.

### A private path is not enough: the metadata layer shadows too — verified 2026-08-24

Found during the second RPM build, on a machine carrying Fedora's own
`libindi`. **The one rule can be broken without touching a single file.**

RPM's automatic dependency generator scans every ELF object in the buildroot,
including the ones in the private prefix, and advertises their SONAMEs as
package-level `Provides`. Unfiltered, `indi-stable-core-libs` provided:

```
libindiclient.so.2()(64bit)          libindidriver.so.2()(64bit)
libindiAlignmentDriver.so.2()(64bit) libindilx200.so.2()(64bit)
```

which is *exactly* the Provides set of Fedora's `libindi-libs` — verified by
diffing the two. So while the files were correctly isolated under
`/opt/indi-stable`, the package was simultaneously telling the depsolver it
was a system-wide provider of the distribution's libraries.

**This is reachable, not theoretical.** On Fedora, `phd2` and `stellarium`
depend on `libindiclient.so.2()(64bit)` and carry **no package-name
dependency** on `libindi`. On a machine with our packages installed but the
distro INDI not yet present, `dnf install stellarium` finds that dependency
already satisfied by us, never installs `libindi-libs`, and stellarium then
fails at runtime — our copy lives in the private prefix, which is not on the
loader path and which stellarium has no RPATH into. `kstars` escapes only
because it *also* requires `libindi` by package name; that is luck, not
design, and it is not a property to rely on for other consumers.

The fix is dependency-generator filtering, and **both halves are required**:

- `%__provides_exclude_from` over the whole prefix — path-based. Nothing in
  the private tree should ever be advertised system-wide.
- `%__requires_exclude` matching `^libindi.*\.so.*$` — string-based. This one
  must *not* be path-based: the same binaries carry legitimate external
  dependencies (`libcfitsio.so.10`, `libnova-0.16.so.0`, `libstdc++`, ...)
  that RPM must still record.

Filtering only the Provides makes things **worse**, and this is the
non-obvious part: our own binaries auto-require those same SONAMEs, so with
Provides suppressed and Requires left alone, nothing in our package set can
satisfy them any more — and installing `indi-stable-core` would pull in the
*distribution's* `libindi-libs` to close the gap. The same bug, inverted.

Inter-subpackage dependencies are unaffected, because the spec's
`Requires: %{name}-libs%{?_isa} = %{version}-%{release}` is a name-and-version
dependency, not a SONAME one.

**The Debian side already had this right, for a different stated reason.**
`debian/rules` skips `dh_makeshlibs` precisely so no `shlibs` file advertises
these libraries system-wide. That was written as a note about shared-library
provider metadata; it is in fact the same defence as the RPM filtering above,
and the two should be understood as one requirement with two spellings. Note
this means the RPM packaging was, until now, *weaker* than the Debian one on
a guarantee both are supposed to enforce — worth remembering when porting: a
protection present on one side is not evidence it exists on the other.

**Generalised lesson.** "Coexistence" has three layers, not one:

| Layer | Mechanism | Failure if missed |
|---|---|---|
| Filesystem | private prefix `/opt/indi-stable` | file conflicts, overwritten binaries |
| Runtime linking | RPATH into the private libdir | wrong library loaded at run time |
| Package metadata | Provides/Requires filtering | depsolver satisfies others with our private libs |

The first two were designed in from the start. The third was missed for two
builds and passed every check that existed, because every check inspected
*files* — and the defect was not in any file.

**Fixed and verified 2026-08-24** on a rebuild with both filters in place:
`indi-stable-core-libs` now provides only its own name, its Provides do not
intersect `libindi-libs`'s at all, nothing in the package set can satisfy
`libindiclient.so.2()(64bit)`, the private SONAME Requires are gone, and
`libcfitsio`/`libcurl`/`libnova`/`libusb` are all correctly retained.

One caveat for whoever runs that check next: the `-debuginfo` subpackage
legitimately provides names like
`libindiclient.so.2.2.4-2.2.4.2-1.fc44.x86_64.debug()(64bit)`. They end in
`.debug()(64bit)`, are a distinct dependency name, and cannot satisfy a
`libindiclient.so.2()(64bit)` requirement — but a loose glob over
`indi-stable-core-libs-*.rpm` sweeps them in and the check will appear to
fail. FEDORA.md's checklist item 7 pins the globs to `-2*` for exactly this reason.

### The Debian half of the metadata layer — verified 2026-08-26

The section above closes with the warning that a protection on one packaging is
not evidence it exists on the other. This is that verification, done on its own
rather than inherited, and the mechanism turns out to be different enough that
the RPM result would not have covered it.

**`dpkg` has no SONAME-level dependencies at all.** Every `Depends:` names a
*package*. There is no equivalent of `libindiclient.so.2()(64bit)` for a
depsolver to satisfy from the wrong place, so the RPM failure mode — `dnf`
quietly choosing our package to satisfy a stranger's soname requirement — has
no counterpart that `apt` could commit at install time. Checked directly: with
`indi-stable-core` installed and the distribution's INDI removed,
`apt-get install indi-bin` pulls `libindi1` back in.

That makes the *apt* half of the test nearly vacuous on its own, which is worth
stating plainly, because a check that cannot fail reads later as a check that
passed. Its value comes from the control beside it: a scratch package declaring
`Provides: libindi1` **does** make `apt` stop wanting `libindi1`, so the
verdict does depend on the metadata, and our packages declaring no `Provides:`
is a real result rather than an inevitable one.

**The layer that can actually shadow on Debian is the consumer's BUILD.** The
package name in a consumer's `Depends:` is chosen at *its* build time by
`dpkg-shlibdeps`, from the `shlibs` file of whichever installed package owns
each library it links. Ours ship none — `dh_makeshlibs` is overridden with an
empty body — and that is confirmed from the `.deb` control archives rather than
from `rules`: `control`, `md5sums` and (for the main package) `postinst` and
`prerm`, with no `shlibs`, no `symbols` and no `Provides:` line anywhere. The
distribution's `libindi1`, run through the identical pipeline, ships a `shlibs`
saying `libindiclient 2 libindi1` — so the check can see one when there is one.

**What `dpkg-shlibdeps` does when it meets our library anyway.** It finds it:
a consumer built through our `libindi.pc` carries `DT_RUNPATH
[/opt/indi-stable/lib]`, and `dpkg-shlibdeps` searches RUNPATH. Having found
the file and no `shlibs` to go with it, it **fails loudly**:

```
dpkg-shlibdeps: error: no dependency information found for
  /opt/indi-stable/lib/libindiclient.so.2 (used by .../consumer-ours)
```

That is the right outcome and the one to preserve. The two answers that would
be defects are a generated dependency on `indi-stable-core-libs` — us
advertising a private library system-wide — and, more insidiously, one on
`libindi1`, which would point a consumer of *our* library at the
*distribution's* package. Neither occurs. A consumer linked the ordinary way
against the distribution's library, run through the same tool, does come back
with `libindi1`, which is what shows the tool was producing output at all.

**The consequence for anything this project later builds against its own
`-dev` package** — `3rdparty/`, `pyindi-client` — is that it will hit that same
error, and the answer is the one `core/deb` already uses: a `shlibs.local`
naming the private libraries, consulted ahead of every other source and never
installed into a binary package. Not `--ignore-missing-info`, which would
suppress the same error for *system* libraries and convert a build failure into
a silently under-specified dependency.

### Driver-manifest discoverability — verified 2026-08-23

Checked against INDI's real source and a live VM carrying two independent
INDI installs, not assumed:

- `DATA_INSTALL_DIR` (the `share/indi/` manifest directory) is baked into
  `config.h` from `CMAKE_INSTALL_PREFIX` at build time
  (`indi/CMakeLists.txt:72`). **A distinct install prefix therefore yields a
  distinct, self-consistent manifest directory automatically** — a free
  consequence of the prefix choice already required for libs and headers.
  Confirmed live: `/usr/share/indi/drivers.xml` (distro) and
  `/usr/local/share/indi/drivers.xml` (source build) coexist today with zero
  conflict.
- Each 3rdparty driver ships its **own distinctly-named** manifest fragment
  (e.g. `indi_eqmod.xml`) beside core's `drivers.xml`
  (`indi-eqmod/CMakeLists.txt:92`) — no shared file needing merge or
  edit-in-place.
- A driver binary finds its own skeleton (`_sk.xml`) under a custom prefix:
  `basedevice.cpp`'s `getSharedFilePath()` checks `$INDISKEL`, then
  `$INDIPREFIX/share/indi/`, then the compiled-in `DATA_INSTALL_DIR` — and
  `indiserver` sets `INDIPREFIX` only for the FIFO `@driver -p` directive
  (`LocalDvrInfo.cpp`), so a normal launch resolves correctly with no extra
  wiring.
- **The gap that `--xmldir` could not close — since closed by the rewrite
  below.** *Corrected 2026-08-24 on the Fedora VM; the earlier text claimed
  this was "already solved upstream: document the setting; no design change
  needed." Resolved 2026-08-25, so this bullet now records the problem that
  motivated the fix rather than an open question. It is kept because the two
  conditions below are properties of what upstream generates, and a future
  release that changed either would change what the fix has to do.*

  Third-party pickers do have the setting — INDI Web Manager takes `--xmldir`,
  KStars/Ekos has a configurable "INDI drivers XML directory" (default
  `/usr/share/indi`). Pointing either at our prefix nevertheless changed
  **nothing**, for two reasons measured on a box carrying both installs:

  1. The two catalogues were **byte-identical** — `/usr/share/indi/drivers.xml`
     and `/opt/indi-stable/share/indi/drivers.xml` shared one sha256
     (`63ec55a3ce7ca53f726172524541a05b1345b40a0fe2507613fb9074705d3117`, still
     the distribution's today), 290 drivers each. (Earlier text said 291:
     `grep -c '<driver'` also counts the `<driversList>` root element.) The
     prefix gave us a separate *file*, but not different *content*.
  2. Every entry named its binary by **bare name** (`<driver name="LX200
     Basic">indi_lx200basic</driver>`), never an absolute path. A bare name is
     resolved by `execvp` through `PATH`, and `/opt/indi-stable/bin` is
     deliberately not on `PATH` (that is the no-`/usr/bin` rule working as
     intended), so `/usr/bin` won every time.

  Verified rather than reasoned about: `indiserver-stable indi_simulator_ccd`
  — the bare name exactly as the catalogue lists it — ran
  `/usr/bin/indi_simulator_ccd` and mapped `/usr/lib64/libindidriver.so.2.2.4`.
  Our server, the distribution's driver, the distribution's libraries.

  **This never weakened the coexistence guarantee**, which is about never
  shadowing the distribution, and which held throughout: the same driver given
  as an *absolute path* mapped `/opt/indi-stable/lib/…` correctly. What it
  broke was the *opt-in* story in the next section. `alternatives` hands
  someone our `indiserver`, but `indiserver` is the one component that links
  none of the INDI libraries — so switching it changed nothing on its own, and
  there was no supported way to reach our *drivers* by name.

  **Both conditions are now gone**, and only on our side: the build rewrites
  every entry whose binary we ship to an absolute path, so our catalogue no
  longer shares the distribution's hash and no longer resolves through `PATH`.
  `indiDriversDir` / `--xmldir` now does what someone pointing it at our prefix
  would expect. The decision, the two entries deliberately left bare, and the
  live-Ekos verification in **both** directions — opted in, and as a bystander
  — are in "Resolution — absolute paths in our `drivers.xml`" below. The
  distribution's catalogue is untouched and still uses bare names, which is why
  condition 2 above remains the correct description of upstream's output.

### One indiserver per machine unless `-u` says otherwise — verified 2026-08-25

Found while building the Ekos observation harness, by reading a log that had
nearly been discarded.

`indiserver` binds an **abstract Unix socket** for local clients in addition to
its TCP port. The name is machine-global and defaults to the same value in both
installs:

```
-u path  : Path for the local connection socket (abstract), default /tmp/indiserver
```

`ss -lx` shows it as `@/tmp/indiserver`. Because the name is fixed and not
derived from `-p`, **a second `indiserver` cannot start while a first one is
running, whatever port it is given.** The second dies immediately:

```
2026-08-25T15:40:59: Local server: bind: Address already in use
2026-08-25T15:40:59: good bye
```

Two consequences, and neither is a packaging defect — this is upstream
behaviour, identical in the distribution's build and ours:

- **Anything that starts a second server while Ekos has a profile running must
  pass its own `-u`.** `scripts/observe-ekos-live.sh` does, which is the only
  reason its positive control can run at all.
- **Opting in is exclusive at runtime, not just at `PATH` level.** Someone
  running our `indiserver` cannot simultaneously run Ekos's, and vice versa.
  That is a constraint on the answer to the opt-in question above, not an
  argument for any particular answer.

With distinct sockets the two genuinely do run at once, which is the first time
that has actually been demonstrated rather than inferred from two sequential
runs. Both servers alive, and each driver mapping its own libraries despite the
SONAMEs being identical:

```
/usr/bin/indi_simulator_ccd            -> /usr/lib64/libindidriver.so.2.2.4
/opt/indi-stable/bin/indi_simulator_ccd -> /opt/indi-stable/lib/libindidriver.so.2.2.4
```

### Resolution — absolute paths in our `drivers.xml` — decided 2026-08-25

**Decision: rewrite the catalogue at build time so every entry whose binary we
ship names it by absolute path.** Implemented in both packagings — `%install`
in `core/rpm/indi-stable-core.spec`, `override_dh_auto_install` in
`core/deb/rules`. Both produce 288 rewritten entries and leave the same two
bare. `scripts/test-catalogue-rewrite.sh` checks either build's output and
demonstrates each assertion still able to fail.

Chosen over the alternative — a `profile.d` snippet or wrapper prepending the
private bindir to `PATH` — because that only ever reaches someone with a shell.
Ekos users have none: KStars spawns `indiserver` itself, so `PATH` activation
would have to widen to the whole session, which is the shadowing this design
exists to prevent. Rewriting the catalogue is per-application, reversible, and
changes no `PATH`.

Verified on a live Ekos session rather than reasoned about, twice — once with a
hand-built catalogue to test the premise before committing to it, then again
with the catalogue the RPM actually ships:

```
/opt/indi-stable/bin/indi_simulator_ccd       -> /opt/indi-stable/lib/libindidriver.so.2.2.4
/opt/indi-stable/bin/indi_simulator_wheel     -> /opt/indi-stable/lib/...
/opt/indi-stable/bin/indi_simulator_focus     -> /opt/indi-stable/lib/...
/opt/indi-stable/bin/indi_simulator_telescope -> /opt/indi-stable/lib/... + our MathPlugin
```

Three things that fell out of the runs and are easy to get wrong:

- **`indiserver` stays the distribution's, and that is fine.** Ekos spawned
  `/usr/bin/indiserver` and it ran our drivers correctly, because `indiserver`
  links no INDI library and only fork/execs drivers over pipes. The
  `alternatives`/`indiserver-stable` mechanism is therefore *orthogonal* to the
  opt-in problem, not a solution to it — worth remembering before anyone
  reaches for it again.
- **The `dlopen` path follows too.** The telescope simulator loaded our
  `MathPlugins/libindi_Nearest_MathPlugin.so` with no extra wiring — a third
  resolution mechanism after SONAME/RPATH and the header/`.pc` search order.
- **Not every driver binary is named `indi_*`.** `shelyak_usis` is not, and the
  first implementation's `indi_*` glob left it bare — silently resolving to the
  distribution's copy. The build now walks every executable in the bindir, and
  the assertion is derived from the catalogue rather than from the same glob,
  so it cannot inherit that blind spot again.

**The bystander case — the other half, and the one that matters to people who
never asked for us.** Everything above is the *opt-in* path: Ekos pointed at
`/opt/indi-stable/share/indi` on purpose. The converse question is what an
existing Ekos user gets by merely installing our package and changing nothing.

First run 2026-08-25 and recorded in `FEDORA.md`; **re-run 2026-08-26 with the
positive control it had been missing**, which is the part that makes it
evidence rather than an observation that could not have come out otherwise.

Measured with `scripts/observe-ekos-live.sh` against a live simulator profile,
with our packages installed, 224 drivers present under `/opt`, and Ekos left at
its built-in default. Every process the session spawned resolved to `/usr`:

```
/usr/bin/indiserver                  owned by libindi-2.2.4.1
/usr/bin/indi_simulator_ccd          -> /usr/lib64/libindidriver.so.2.2.4  (+client, +Alignment)
/usr/bin/indi_simulator_wheel        -> /usr/lib64/...
/usr/bin/indi_simulator_focus        -> /usr/lib64/...
/usr/bin/indi_simulator_telescope    -> /usr/lib64/...
                                     + /usr/lib64/indi/MathPlugins/libindi_Nearest_MathPlugin.so
```

The `dlopen`'d MathPlugin is the row worth noting. It is a third resolution
mechanism, independent of both SONAME/RPATH and the header search order, and it
stayed in `/usr` as well — so all three follow the opt-in setting rather than
leaking across it.

**The measurement was shown able to fail.** The harness starts our own
`indiserver` alongside Ekos's — with its own `-u`, per the section above — and
the same scanner immediately reported `/opt/indi-stable/bin/indiserver` and all
three of our libraries. So "nothing touches `/opt`" is an observation, not a
scanner that could not see `/opt` if it were there.

Note what could **not** have answered this: the Ekos driver list. Both
catalogues carry the same 290 `name=` labels, and the GUI displays the label
rather than the binary path, which is the only field that differs. The visible
list is identical in both configurations.

Two entries stay bare on purpose: `indi_simulator_spectrograph` and
`indi_pegasus_uch` have no binary in *either* build, and inventing paths for
them would turn a merely-absent driver into one that fails with a wrong path.

**What this does not change:** the default. Someone who installs the packages
and touches nothing still gets the distribution's INDI everywhere, because
Ekos's `indiDriversDir` still points at `/usr/share/indi`. Opting in is one
setting, and reverting it is the same setting.

### Consumers of the private prefix need the RPATH too — found 2026-08-25

Our own binaries work because CMake bakes `CMAKE_INSTALL_RPATH` into every one
of them at build time. **Anything built later, by someone else, gets no such
help**, and `libindi.pc` does not supply it:

```
Libs: -L${libdir} -lindiclient
```

`-L` is a *link-time* search path. `/opt/indi-stable/lib` is deliberately absent
from `ld.so.conf` and `ldconfig` (verified: zero entries), which is the
coexistence guarantee working as designed — so the link succeeds and the binary
dies on startup:

```
$ PKG_CONFIG_PATH=/opt/indi-stable/lib/pkgconfig g++ -o t t.cpp \
      $(pkg-config --cflags --libs libindi)
$ ./t
./t: error while loading shared libraries: libindiclient.so.2:
     cannot open shared object file: No such file or directory
```

That command is the one `indi-stable-core-dev`'s package description tells
people to use. The header half of the same test is correct: with no
`PKG_CONFIG_PATH` the compiler resolves `libindi/indiapi.h` to the
distribution's copy and `pkg-config --variable=prefix libindi` answers `/usr`,
so nothing of ours shadows anything. Only the runtime half is broken.

**Fixed 2026-08-25 by appending `-Wl,-rpath,${libdir}` to `Libs:` at build
time**, in `%install` and `override_dh_auto_install` alike. It gives consumers
exactly the mechanism our own binaries already rely on, per-consumer and
opt-in, and changes no global state. The package description then needs no
change, because the command it documents starts working.

**What must NOT be done instead: an `/etc/ld.so.conf.d` entry.** That would put
our libraries on the global search path, which is the shadowing this entire
project exists to prevent — `libindiclient.so.2` would then be resolvable
system-wide by anything, exactly the outcome the private prefix and the skipped
`dh_makeshlibs` are there to avoid.

Verified on the DEB by compiling, linking and *running* a consumer: RUNPATH
`[/opt/indi-stable/lib]`, `ldd` resolving to our `libindiclient.so.2`, and the
binary starting. With no `PKG_CONFIG_PATH` nothing changes — the distribution
still wins and no RUNPATH appears in such a build.

**Confirmed on the RPM 2026-08-25**, rebuilt through `mock` and measured the
same way, in a chroot carrying the distribution's `libindi`, `libindi-libs` and
`libindi-devel` alongside ours: `RUNPATH [/opt/indi-stable/lib]`, `ldd`
resolving to our `libindiclient.so.2`, and the consumer running. Fedora's
toolchain emits **`DT_RUNPATH`** here too, on the consumer and on our own
drivers alike, so the `--enable-new-dtags` reasoning below holds unchanged on
both distributions.

**The pre-fix failure mode is not the same on every box, and the difference
matters.** The DEB run saw the consumer die at startup with
`libindiclient.so.2: cannot open shared object file` (`50c11d7`). Rebuilding
the defect deliberately on Fedora, in a chroot that *does* carry the
distribution's `libindiclient.so.2`, it does not die: it loads
`/lib64/libindiclient.so.2` — the distribution's — while having compiled
against our headers, and exits 0. Same omission, opposite volume. A missing
`-Wl,-rpath` announces itself only where no other copy of the SONAME exists;
on precisely the machines this project is *for*, it is silent.

### The `Cflags:` half of the same file — found and fixed 2026-08-25

Upstream **dropped `-I${includedir}`** from `Cflags` between 1.9.9 and 2.2.4:

| | `Cflags:` |
|---|---|
| distro 1.9.9 | `-I${includedir} -I${includedir}/libindi` |
| ours 2.2.4 | `-I${includedir}/libindi` |

Harmless at `prefix=/usr`, where `/usr/include` is searched implicitly so both
`<indiversion.h>` and `<libindi/indiversion.h>` find the same tree. **In a
private prefix it is not harmless**, because only the second-level directory is
on the search path:

```
#include <indiversion.h>          -> /opt/indi-stable/include/libindi/...  (ours)
#include <libindi/indiversion.h>  -> /usr/include/libindi/...              (DISTRO)
```

Both measured with `g++ -E -H`. The second style silently compiles against
1.9.9 headers and links our 2.2.4 library — a header/library mismatch, arrived
at with no warning, and exactly the "`/usr/include` wins the search order so a
distribution `-devel` silently wins" failure the private include path exists to
prevent.

**Fixed by appending `-I${includedir}` to `Cflags` at build time**, the same way
the RPATH is appended to `Libs:`, restoring what 1.9.9 had. Checked safe rather
than assumed: our `includedir` contains nothing but the `libindi/`
subdirectory, so it exposes no header that could shadow a system one.

After, both spellings open
`/opt/indi-stable/include/libindi/indiversion.h`, both link
`/opt/indi-stable/lib/libindiclient.so.2`, and both binaries run. With no
`PKG_CONFIG_PATH` both still resolve to `/usr/include`, so nothing of ours
leaks into a default build.

**Note what this means for the header rule.** Keeping headers out of
`/usr/include` is necessary but was *not sufficient*: the headers were
installed correctly the whole time and `/usr/include` still won, because our
own `.pc` did not put the parent directory on the search path. The rule in
CLAUDE.md is about where headers are installed; this is the second half of it,
and only a compile shows the difference. Both spellings were measured with
`g++ -E -H`, before and after.

As with the RPATH, this was **confirmed on the RPM 2026-08-25** by rebuilding
and preprocessing both spellings in a chroot holding both trees: with
`PKG_CONFIG_PATH` set to ours both open
`/opt/indi-stable/include/libindi/indiversion.h`, with none set both open
`/usr/include/libindi/indiversion.h`, and against a scratch `.pc` carrying
upstream's unfixed line the qualified spelling reaches `/usr/include` while
linking our library — the defect, reproduced on demand as the control.

### The guarantee tested where it can actually fail — Ubuntu + PPA, 2026-08-25

Every earlier coexistence result came from a box whose distribution INDI had a
*different* SONAME to ours, where the question has no teeth. On
`ppa:mutlaqja/ppa` the distribution ships `libindiclient.so.2.2.4` with SONAME
`libindiclient.so.2` — the same SONAME *and* the same upstream release we
package. Both `libindi.pc` files even report `Version: 2.2.4`, so version alone
cannot tell the two apart. Only the path can.

Two `indiserver`s run at once, each driver mapping a file of the **same name**
from a different tree, read out of `/proc/<pid>/maps`:

```
distro driver -> /usr/lib/x86_64-linux-gnu/libindiclient.so.2.2.4
our    driver -> /opt/indi-stable/lib/libindiclient.so.2.2.4
```

**The measurement was shown able to fail.** `DT_RUNPATH` is overridden by
`LD_LIBRARY_PATH`; forcing it makes our own driver map the distribution's
libraries, which is how we know the passing result is not vacuous:

```
LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu, our driver
  -> /usr/lib/x86_64-linux-gnu/libindiclient.so.2.2.4
```

That is worth stating plainly, because this file has been calling the mechanism
"RPATH": CMake with the default `--enable-new-dtags` emits **`DT_RUNPATH`**, not
`DT_RPATH`, and `LD_LIBRARY_PATH` takes precedence over the former. The
separation is therefore robust against the default environment and against
`ldconfig`, but not against a user who exports `LD_LIBRARY_PATH` — an explicit
act, not an accident, but not a guarantee either.

**The metadata layer holds too, and this is the sharpest result.** With SONAMEs
identical, `dpkg-shlibdeps` on a consumer linking our library *errors*:

```
no dependency information found for /opt/indi-stable/lib/libindiclient.so.2
```

while the same tool on a consumer linking the distribution's library at the very
same SONAME returns `shlibs:Depends=... libindi1 ...`. Our library cannot be
mistaken for `libindi1`. Erroring is the correct outcome rather than a
shortcoming: a third-party packager building against the private prefix is told
so, and supplies their own `shlibs.local` exactly as `core/deb` does.

## Switching to indi-stable (opting in, not just coexisting)

Coexistence-by-default must not mean stuck-side-by-side-forever:

- **Binaries:** `alternatives --config indiserver` — explicit, reversible,
  first-class.
- **Libraries/headers:** resolved per-consumer via rpath/private include
  path, not a global toggle. Whichever `indiserver` is active, and whichever
  Python environment has this pyindi-client, determines what is in use.
- **Full switch-over** for someone wanting a single INDI on the machine:
  ordinary `Conflicts:`/`Replaces:` metadata (`dnf swap`, or apt resolving a
  conflict), but always as an **explicit user action** — never something an
  install does on its own. Worth a documented path, possibly a convenience
  meta-package, rather than expecting people to learn the mechanics.

### The `alternatives` bullet above does NOT work on Fedora — verified 2026-08-23

Found during the first RPM build. **Decided 2026-08-24 — see "Resolution —
namespaced link" below.** Kept because the finding itself still constrains the
packaging: it is the reason the link name is namespaced, and a future
distribution that shipped `/usr/bin/indiserver` as a real symlink would change
what is possible here.

Fedora's `libindi` ships `/usr/bin/indiserver` as an **ordinary file it owns**,
not as an `alternatives`-managed symlink (`rpm -qf /usr/bin/indiserver` →
`libindi-2.2.4.1`; `alternatives --display indiserver` → not registered).
`alternatives` can only manage a link path that is absent or already a symlink.

Tested in a sandbox with `--altdir`/`--admindir` pointed at scratch
directories, never against the real `/usr/bin`:

- `alternatives --install` **refuses** to replace a real file:
  `... exists and it is not a symlink`. **The one rule holds** — the
  distribution's binary is not touched, on install or on uninstall, and
  `rpm -V libindi` stays clean. `--remove` in `%postun` is likewise harmless.
- But it **exits 0**. The failure is silent, `%post` "succeeds", the RPM
  installs cleanly, and `/usr/bin/indiserver` still runs the distro build.
- And afterwards `alternatives --display indiserver` reports *"link currently
  points to"* our binary — which is **false**. It describes the record in the
  admin directory, not the link that was never created.

So the design is **safe but non-functional** on precisely the configuration
this project targets: a machine that already has the distribution's INDI. There
is no way to reach our `indiserver` through `PATH`.

Consequence for verification: `alternatives --display indiserver` is **not** a
valid check and will pass while the feature is broken. The honest check is
`readlink -f /usr/bin/indiserver`, or running it and reading the version.

Options considered:

1. Drop `alternatives` and expose nothing in `PATH` — document
   `/opt/indi-stable/bin` as the way in (profile.d snippet, or let callers use
   the absolute path). Simplest, and gives up least, since the private prefix
   was always the real interface.
2. Keep `alternatives` but use a **namespaced link** (`indiserver-stable`) that
   no distribution owns, so registration always succeeds.
3. Keep `/usr/bin/indiserver` as the link name and accept that it only works on
   machines without distro INDI — the weakest option, since it fails silently
   exactly where it matters and cannot be distinguished from working.

Note Debian may differ: `indi-bin` owns `/usr/bin/indiserver` there, and
whether it is alternatives-managed has **not** been checked. Do not assume the
Fedora finding transfers without running the same test.

### Resolution — namespaced link, not `/usr/bin/indiserver` — decided 2026-08-24

Before picking between the three options above, checked whether this is a
solved problem elsewhere rather than reasoning from first principles. It is:
two projects ship newer versions of daemons the distro also packages, without
breaking the distro's copy, and neither reaches for `alternatives` or
diversion to take over the distro's canonical path.

- **Red Hat Software Collections (SCL)** solves the identical shape of
  problem — multiple toolchain versions coexisting with the base system's.
  Isolation is structural (`/opt/rh/...`, prefixed package names, prefixed
  RPM `Provides`), and activation is **opt-in**: `scl enable` adjusts `PATH`
  / `LD_LIBRARY_PATH` in the calling shell rather than claiming a system
  path. SCL does ship an optional `*-syspaths` variant that drops a wrapper
  into `/usr/bin` — and documents it as breaking the isolation guarantee, an
  explicit opt-out for people who accept that tradeoff, not the default.
- **PGDG** (PostgreSQL's own upstream repo) faces this exact scenario —
  shipping newer versions than the distro — and does not touch `alternatives`
  either. Binaries live in version-specific paths (`/usr/pgsql-16/bin/`);
  "make PGDG win" is handled at the package-manager layer (disabling the
  distro's module stream on Fedora/RHEL, `apt` pinning on Debian), never by
  claiming the distro's file.
- **Debian policy is direct about the other tool this could reach for.** The
  `dpkg-divert` manual warns against diverting a file "vitally important for
  the system's operation" — which `indiserver` is, for anyone whose Ekos
  session depends on the distro build. Ruled out for the same underlying
  reason as fighting `alternatives` on Fedora: both require taking the
  distro's own file away from it, which is the one thing this project exists
  not to do.

**Decision: option 2.** Drop the ambition of owning the plain `indiserver`
name; register a namespaced link instead (working name `indiserver-stable`,
not finalized). No distribution owns that name, so `alternatives --install`
succeeds unconditionally on both Fedora and Debian, `--display` reports the
truth instead of a false positive, and "Switching to indi-stable" becomes
`alternatives --config indiserver-stable` — reversible and honest, the
property the original design wanted from `alternatives` in the first place.

This also reframes what `alternatives` is *for* here: not arbitrating against
the distribution's binary — SCL and PGDG both show that's the wrong fight —
but arbitrating between this project's *own* versions once more than one
stable release is installed at a time, which is a job only this project can
do without touching a file it doesn't own.

Sources:
- [Use Software Collections without Bothering with Alternative Path — Red Hat Developer](https://developers.redhat.com/blog/2017/10/18/use-software-collections-without-bothering-alternative-path)
- [1.6. Enabling a Software Collection — Red Hat Software Collections 3 Packaging Guide](https://docs.redhat.com/en/documentation/red_hat_software_collections/3/html/packaging_guide/sect-enabling_the_software_collection)
- [Repo RPMs — PostgreSQL YUM Repository](https://yum.postgresql.org/repopackages/)
- [PGDG Repo — PIGSTY docs](https://pigsty.io/docs/repo/pgdg/)
- [dpkg-divert(1) — Linux manual page](https://man7.org/linux/man-pages/man1/dpkg-divert.1.html)
- [7. Diversions — overriding a package's version of a file — Debian Policy Manual v4.7.4.1](https://www.debian.org/doc/debian-policy/ap-pkg-diversions.html)

---

### `dpkg` runs the maintainer scripts in the opposite order to RPM — observed 2026-08-26

`DEBIAN.md` said to reason this through for `dpkg` rather than port the RPM
assumption. Better than reasoning: `dpkg -D2` logs every maintainer script it
actually runs, so an upgrade can simply be watched. Upgrading `2.2.4.2-1` to
`2.2.4.2-2` emits exactly two lines for our package:

```
fork/exec /var/lib/dpkg/info/indi-stable-core.prerm ( upgrade 2.2.4.2-2 )
fork/exec /var/lib/dpkg/info/indi-stable-core.postinst ( configure 2.2.4.2-1 )
```

Two things follow, and both differ from RPM.

**The old package's `prerm` runs first, with the argument `upgrade`.** Our
`prerm` matches `remove|deconfigure`, so it does not fire and withdraws
nothing. Note the guard is doing real work here — an unguarded
`update-alternatives --remove` would run at this point.

**The new package's `postinst` runs LAST, with `configure`.** It calls
`update-alternatives --install`, which is idempotent, so the alternative is
*re-registered* by the final script of the transaction.

RPM is the mirror image: the **old** package's `%postun` runs last, after the
new `%post` has already registered the alternative, which is why
`core/rpm/indi-stable-core.spec` needs its `$1 -eq 0` guard and why
`scripts/test-upgrade-path.sh` exists to exercise it. On `dpkg` the last script
to run restores the link rather than tearing it down, so the upgrade path here
is structurally *less* fragile, and the `prerm` case guard is a belt to the
`postinst`'s braces rather than the only thing preventing a dangling command.

**What is fragile on `dpkg` instead** is the thing `DEBIAN.md` already warns
about: the alternative's name and target are written in *two* files,
`postinst` and `prerm`, and nothing checks that they agree. Demonstrated by
building a package whose `prerm` withdraws `indiserver-stable-typo` while its
`postinst` registered `indiserver-stable`: removal completes with no error and
leaves `/var/lib/dpkg/alternatives/indiserver-stable` behind, stranded, with no
package left to own it. That is the defect worth testing for here, and it is
invisible to any check that only looks at the upgrade.

## `indi-3rdparty` is a different shape of build — established 2026-08-26

Read out of the `v2.2.4.1` tree rather than assumed. These come before any
spec is written because several of them decide what a spec can even look like.

- **It is a genuinely independent version axis, now measured.** The newest
  `indi-3rdparty` tag is **`v2.2.4.1`** while core is at `v2.2.4.2`. The
  versioning policy above predicted the two repos release on separate cadences;
  they are in fact out of step *today*, so a packaging that pairs them by equal
  version string is wrong from the first build.
- **The tarball is 297 MB against core's 3.8 MB**, and unpacks to
  `indi-3rdparty-2.2.4.1` — the leading `v` stripped, same as core.
- **It ships its own `debian/` directory too**, holding per-driver packaging.
  The `rm -rf debian` rule from `DEBIAN.md` applies here unchanged, and the
  consequence of forgetting is the same. That directory is also the best
  available prior art for the per-driver split, since upstream already does it.
- **The build is TWO PHASES, and they are mutually exclusive.**
  `option(BUILD_LIBS "Build 3rd Party Libraries, not 3rd Party Drivers" Off)`,
  and the tree is gated `if(BUILD_LIBS)` / `else` / `endif` at CMakeLists.txt
  lines 373 / 471 / 1009. One invocation builds libraries **or** drivers, never
  both. Upstream's own comment says to run the libs pass first. So a spec here
  cannot be core's shape with different sources — it needs two configure+build
  passes, or two source packages.
- **72 `option(WITH_<DRIVER> ...)` switches, all defaulting `On`.** This is the
  granularity lever for `indi-stable-3rdparty-<driver>` subpackages, and it
  means per-driver selection costs nothing to implement.
- **61 driver directories and 27 `lib*` directories, of which 22 ship prebuilt
  binaries** — `.bin` files that are ELF shared objects, one per architecture.
  That is where the 297 MB is.

### Which drivers actually need a bundled blob — 11 of 61

Counted three times, and the first two answers were wrong in ways worth
recording, because both are traps for the next person:

- Matching driver directory names against vendor names is **too loose**:
  `indi-asi-power` is a Raspberry Pi power controller, `indi-astarbox` and
  `indi-atik-efw` link nothing vendor-specific. All three `find_package` only
  INDI, Threads and RT.
- Matching every `Find<X>.cmake` module is **too broad the other way**: `ZMQ`,
  `GPSD`, `GPIOD`, `GPHOTO2`, `FFmpeg`, `Mosquitto`, `LibCamera` and friends
  are ordinary distribution packages, not bundled blobs.

The reliable test is `find_package(<V>)` where `lib<v>/` in this tree ships
binaries. That gives **11 drivers needing a blob and 50 that do not**:

```
indi-asi  indi-astroasis  indi-atik  indi-fli  indi-inovaplx  indi-mi
indi-playerone  indi-qhy  indi-sbig  indi-svbony  indi-toupbase
```

**`indi-toupbase` is the one a literal grep misses**, and it matters most. It
calls `find_package(${BRAND} REQUIRED)` inside a `foreach` over
`TOUPTEK_REBRANDS`, so it needs **eleven** vendor SDKs on its own — Touptek
OEMs the same hardware as Toupcam, Altair, Bresser, Mallincam, Meade, Nncam,
Ogmacam, Omegon, StarShoot, TScam and SVBony. Those eleven are also most of the
297 MB (`libtoupcam` and `libnncam` are 166 MB each).

### The licence tiers, and why the motivating example is the hardest case

The 22 blob vendors do not share one licence:

| | Vendors |
|---|---|
| Explicit redistribution grant | `libasi` (ZWO, verbatim MIT text), `libplayerone`, `libfli` (BSD, **and** ships source), `libapogee` (ships source), `libinovasdk`, `libmicam`, `libsbig` — the last three all read *"redistribution... in binary form... permitted"*, checked directly rather than assumed from the filename |
| Labelled `COPYING.LGPL`, shipped binary-only | the 11 Touptek rebrands: `libtoupcam`, `libnncam`, `libaltaircam`, `libbressercam`, `libmallincam`, `libmeadecam`, `libogmacam`, `libomegonprocam`, `libstarshootg`, `libtscam`, `libsvbonycam` |
| **No licence file at all** | `libastroasis`, `libatik`, `libqhy`, `libsvbony` |
| Real EULA, explicitly forbidding standalone redistribution | `libricohcamerasdk` — but not bundled by any current driver's `find_package`; `indi-pentax` builds it only if already found on the system (`CMakeLists.txt:979`). Not part of this decision, and mentioned only because it shows this ecosystem does contain an explicit "do not redistribute" case, and this project is not currently tripping over it |

**`libqhy` is in the no-licence row, and `README.md` names the qhyccd driver as
the reason this project exists** — "driver coverage is incomplete — the qhyccd
driver, for instance, has never been in it". That is very likely not an
oversight by Fedora's packagers: a distribution cannot ship a binary blob with
no licence file. So the motivating example carries the hardest redistribution
constraint of the whole set — and only 4 of the 22 blob vendors are actually in
that hardest tier; the rest carry a real grant.

Note the constraint is on **redistribution**, not on building. Nothing stops a
user building any of these locally; it is shipping the result under this
project's name that raises the question.

### Resolution — bundle by licence tier, not by popularity — decided 2026-08-26

**Bundle the blobs with an actual grant. Do not bundle the four with no licence
file.** Concretely: `asi`, `fli`, `apogee`, `playerone`, `inovasdk`, `micam`,
`sbig`, and all 11 Touptek-family rebrands ship with their driver, same as
every other 3rdparty component. `astroasis`, `atik`, `qhy` and `svbony` do not
— those four drivers are packaged, but the package does not carry the vendor
SDK, and the build/install documentation says to obtain it from the vendor and
place it before building or running. This is a policy decision, not a legal
opinion, and it is revisited if any of the four vendors publishes an explicit
grant, or if a lawyer's actual reading says otherwise — this project has
neither in hand today.

**Why the missing licence file is a different kind of thing, not just a
weaker version of the others.** Copyright defaults to all-rights-reserved; a
missing grant does not read as permissive, it reads as *nothing granted at
all*. `LGPL, binary-only` and `redistribution in binary form permitted` are
both real grants with terms — exactly what a licence file is for. A vendor
directory with no licence file at all is not on that spectrum; it is a
different category, and treating it as merely "one more unclear case" among
several was the first framing tried here and it undersold the distinction.

**Why "upstream's own repo bundles all of it" does not settle the question.**
It is evidence the practical risk of enforcement may be low, not evidence of
permission — those are different claims, and only the second one matters for
what this project may distribute under its own name. A vendor's tolerance of a
well-known, community-run project is revocable at any time and does not extend
automatically to every redistributor. Nothing here claims INDI's own posture is
wrong for INDI; it claims this project cannot borrow INDI's risk profile by
citing it.

**Why this costs the project's actual primary use case nothing.** Stated by
Will in conversation, 2026-08-26, and since checked directly rather than left
resting on that alone: ACS's own `README.md` (`~/src/ACS`, a separate repo —
`CLAUDE.md`'s "no special access, do not couple them" still holds; this is a
citation for corroboration, not a dependency) says its installer "cannot
install the vendor camera SDKs... both need a licence accepted on a vendor
site," downloads them manually, and installs from what the user already
fetched. So ACS's users already accept each vendor's licence and place the SDK
themselves, for every camera it supports — not merely as a plausible workaround
but as the one thing this specific policy needed to be true. Excluding the four
unlicensed blobs here does not remove camera support from ACS, the consumer
this packaging effort was built for; it removes only the convenience of *this
project* having fetched the SDK on the user's behalf, for exactly the four
vendors that gave no permission to do so. Someone using this project's
3rdparty packages outside ACS and wanting qhy/atik/astroasis/svbony support
gets the driver and a documented manual step, not a silent gap.

**The general shape of this — separate what a distribution has rights to ship
from what it does not, and hand the second kind to the user as a documented
step — is a familiar pattern (Debian's non-free split, RPM Fusion's nonfree
tier, proprietary GPU/firmware handling generally).** Cited here as the shape
this decision follows, not as a researched claim about those projects' current
policies specifically — that was not checked against their actual docs.

**What this means mechanically, to be worked out when the spec is written, not
decided now:** the four affected drivers still get a subpackage; their build
must locate the vendor SDK the way upstream's own `Find<VENDOR>.cmake` expects,
which was written assuming a source-tree-local copy and will need either an
env var or a documented drop-in path; and the resulting binary package
correctly carries no dependency on a vendor library this project never
shipped — that absence is honest, not a bug to paper over.

### Resolution — two source packages, not one and not sixty-one — decided 2026-08-26

**`indi-stable-3rdparty-libs` and `indi-stable-3rdparty-drivers`, one spec (RPM)
or `debian/` tree (DEB) each, sharing one upstream tag and one version, drivers
`BuildRequires`/`Build-Depends` on the specific libs subpackages it needs.**
Not core's shape with a flag flipped, and not one source package per driver.

**Why not one spec doing two internal build passes.** `BUILD_LIBS` gates a real
system install, not merely a second configure step reading the same source
tree. Checked directly rather than assumed: `cmake_modules/FindASI.cmake` is an
ordinary `find_path`/`find_library`, searching normal system paths, and
`libasi/CMakeLists.txt` installs the vendor blob via `add_library(... SHARED
IMPORTED)` — the standard "install a versioned `.so` at a real system
location" pattern, not a source-tree reference `find_package` could resolve
without it. So the drivers configure step genuinely cannot succeed until the
libs step has been built **and installed**, which is exactly what a normal
`BuildRequires` is for and exactly what neither piece of prior art below tries
to do by hand inside one spec.

**Why not one source package per driver, matching upstream's own Debian
packaging exactly.** Read directly: `debian/indi-asi/control`,
`debian/indi-eqmod/control` and 58 others are each independent `Source:`
stanzas with their own `changelog`/`compat`/`rules`, plus one more,
`debian/indi-3rdparty-libs/control`, that the driver packages
`Build-Depends` on by name. That buys upstream independent per-driver release
cadence, which upstream wants and this project does not: `indi-3rdparty`
publishes libs and every driver from **one** git tag, this project promotes
**one** 3rdparty release through **one** gate per the versioning policy above,
and 61 independently-versioned source packages would mean 61 things for that
gate to track for no benefit this project asked for. `README.md`'s own
"per-driver `indi-stable-3rdparty-*`" already reads as binary subpackages of a
shared build, which is what this confirms rather than what it changes.

**The precedent actually worth following is Fedora's own two specs, and it
matches almost exactly.** Fetched directly from Fedora's dist-git rather than
assumed: `indi-3rdparty-libraries.spec` builds `-DBUILD_LIBS=ON` and emits 4
binary packages (`indi-3rdparty-libapogee[-devel]`,
`indi-3rdparty-libfli[-devel]`); `indi-3rdparty-drivers.spec` builds
`-DBUILD_LIBS=OFF` and emits 32, with
`BuildRequires: indi-3rdparty-libapogee-devel = %{version}` and the same for
`libfli` — an ordinary versioned `BuildRequires` between two source packages,
nothing bespoke. Both specs pin the same `%global indi_version`, so the two
are always built and promoted together as one release, which is the version
discipline this project already committed to for 3rdparty as a whole. This is
the shape adopted here, subpackage-per-driver granularity included, because it
is both a working precedent and a closer match to this project's own
conventions than Debian's per-driver split.

**One finding along the way this project should NOT borrow: Fedora bundles
only 2 of the 22 blob vendors, for a different and stricter reason than this
project's own licence-tier decision above.** `NO_PRE_BUILT=ON`, which both
Fedora specs pass, is not a licence check — it flips `WITH_ASICAM`, `WITH_FLI`,
`WITH_TOUPCAM` and 24 other `WITH_*` options to `Off` **all at once**
(`CMakeLists.txt:338-368`), including vendors this project's own decision
bundles because they carry an explicit grant (`asi`, MIT; `fli`, BSD). Fedora's
actual rule is narrower and unconditional — Fedora Packaging Guidelines
prohibit shipping pre-built binary code in the build system at all, regardless
of what licence covers it — and `libapogee`/`libfli` are simply the only two
vendors in the whole tree that ship real, compilable source (confirmed earlier
in this section: 66 and 21 `.c`/`.cpp` files respectively, versus 0 for the
other 20). The overlap with this project's 4 excluded vendors is real but
coincidental: Fedora would exclude `asi` too, on a rule this project has
already decided not to adopt. Citing Fedora here as validation of the
packaging **shape**, not of the licence **policy** — conflating the two would
overstate what was actually checked.

**Also found, and worth README.md fixing separately from this decision:**
`indi-3rdparty-drivers` and `indi-3rdparty-libraries` are both `dead.package`
in Fedora's `rawhide`/`main`, orphaned before an `f44` branch was ever cut —
confirmed three ways (dist-git branches stop at `f43`; the package's build
history on `packages.fedoraproject.org` lists `fc41`/`fc42`/`fc43` and nothing
newer; the live Fedora 44 `Everything` mirror has zero `indi-3rdparty*.rpm`
under any letter directory). `fedoraastro` — this project's own Fedora test
VM — is Fedora 44, and gets nothing from Fedora's own repos for indi-3rdparty
at all, not merely "incomplete coverage" as `README.md` currently says.

### Three more absolute paths found while writing `indi-stable-3rdparty-libs.spec` — 2026-08-26

Found by reading every bundled vendor's `CMakeLists.txt` for `install()`
calls, not assumed absent because core did not have them. All three are
ordinary `CACHE STRING` variables upstream sets, so a `-D` on the same cmake
invocation overrides them without patching — the identical mechanism core
already uses for `UDEVRULES_INSTALL_DIR`.

- **`UDEVRULES_INSTALL_DIR`** — shared by every vendor lib bundled here, same
  variable and same re-homing step in `%install` as core's spec.
- **`FIRMWARE_INSTALL_DIR`** (`libsbig/CMakeLists.txt:22,30`) — upstream's own
  default is `/usr/lib/firmware`, a real file-conflict risk with any other
  package that might install firmware for the same or different hardware
  there. Redirected into `%{indi_prefix}/share/indi/firmware`.
- **`CONF_DIR`** (`libapogee/CMakeLists.txt:17`) — upstream's own Linux
  default is bare `/etc`. Writing a config file into the system `/etc` is
  exactly the kind of thing the private-prefix rule exists to prevent, not a
  style preference. Redirected into `%{indi_prefix}/etc`.

### `libahp-xc` and `libahp-gt` fetch from GitHub at CONFIGURE time — found 2026-08-26

`CMakeLists.txt` ~423-433, gated by `WITH_AHP_XC`/`WITH_AHP_GT`:
`execute_process(COMMAND git clone https://github.com/ahp-electronics/...)`,
run during `cmake` configure, not `%build`'s compile step. No `mock`/`koji`
build permits network access, and this project has done no licence review for
either repository at all — they are not even part of the tarball this project
already downloads and hashes.

Both options already default `Off` in upstream's own `CMakeLists.txt`, so
`indi-stable-3rdparty-libs.spec` does not need to touch them — but that
default not being overridden is load-bearing, not incidental, and the spec
says so explicitly rather than relying on a silent default someone could
"helpfully" flip on later without reading this.

### `WITH_PENTAX` defaults On and would have bundled an EULA-restricted SDK — found 2026-08-26

`indi-pentax` was never in the original blob-driver survey — it does not
`find_package()` a vendor SDK the way the 11 blob drivers do — so it was never
checked against the licence-tier decision. But under `-DBUILD_LIBS=ON`,
`WITH_PENTAX`'s default of `On` unconditionally attempts
`add_subdirectory(libricohcamerasdk)` on non-`aarch64` hosts. That SDK's own
`LICENSE` is a full Ricoh EULA whose §3.1(b) reads *"you shall not... distribute
the Software, in whole or in part, on a stand-alone basis"* — an affirmative
prohibition, stronger than the silence that excluded `astroasis`/`atik`/`qhy`/
`svbony`. `indi-stable-3rdparty-libs.spec` passes `-DWITH_PENTAX=OFF`
explicitly. Caught only by reading every `WITH_*` default in `CMakeLists.txt`
rather than assuming the four already-surveyed vendors were the only ones
needing a flag.

### `libfli`'s bundled `flipro`/`flialgo` — licence coverage genuinely unclear, found 2026-08-26

On Linux, `libfli/CMakeLists.txt` unconditionally (no separate `WITH_*` flag)
also builds `flipro` and `flialgo` from prebuilt `libflipro.bin`/
`libflialgo.bin` — a second, different blob bundled inside the same directory
as the source-shipping `fli` library the licence-tier decision already
approved. `libfli/` carries exactly one licence file, `LICENSE.BSD`, at the
top level, with nothing inside `flipro/` specifically. Whether that top-level
grant was meant to cover a blob added to a subdirectory, or whether the blob
has no licence coverage at all — the same gap that excluded four other
vendors — was not settled tonight. `indi-stable-3rdparty-libs.spec` packages
`libfli.so` and leaves `libflipro.so`/`libflialgo.so` unpackaged pending that
answer; see `STATUS.md`.

### QSI and Fishcamp resolved — decided 2026-08-27

`WITH_QSI` and `WITH_FISHCAMP` sat `OFF` since 2026-08-26 for the weakest
possible reason: neither vendor had actually been read (see the section
above this one wasn't — that was `flipro`/`flialgo`; these two were a
separate, later gap, caught the same day the first real mock build failed
on `WITH_QSI` and silently over-built `WITH_FISHCAMP`). Both were read in
full on 2026-08-27, fetched directly from the pinned tag
(`indilib/indi-3rdparty` `v2.2.4.1`), and resolved in opposite directions.

**QSI: `libqsi/COPYING`, read in full, is not an open-source licence.** It
is Quantum Scientific Imaging's own proprietary notice:

> Quantum Scientific Imaging, Inc. (QSI) does not allow submission or
> posting of the QSI Linux API (QLA) source code to other source code
> distributions by third parties. Do not redistribute the source code
> without prior written permission from QSI.

This is the same shape as `libricohcamerasdk`'s EULA above — an affirmative
prohibition, stronger than the four vendors excluded for mere silence — not
a new category. `libqsi` itself is also unlike every other vendor bundled
here: it ships real, compilable C++ source (66+ files, a full USB/TCP host
IO layer), not a prebuilt blob, so "no licence file" was never the issue;
the issue is the file that exists says not to redistribute it. `WITH_QSI`
stays `OFF`, now for a confirmed reason instead of "never looked at".
(`qsicopyright.txt`, the second file in the same directory, adds nothing
new — a milder restatement of the same "no warranty, all rights reserved"
posture, not a separate grant.)

**Fishcamp: `libfishcamp/COPYING.LIB`, read in full, is genuine
BSD-2-Clause.** The filename suggests LGPL (`COPYING.LIB` is the
traditional GNU name for the old LGPL file); the text is not LGPL at all —
verbatim 2-clause BSD, permissive, redistribution explicitly allowed in
source and binary form. `libfishcamp` builds from real source
(`fishcamp.c`), not a blob, same shape as `fli`. The only non-source
artifacts are two firmware images (`gdr_usb.hex`,
`Guider_mono_rev16_intel.srec`) uploaded to the camera's own microcontroller
at runtime, covered by the same top-level copyright header as the library
source — no separate or contradicting notice found for them, same
reasoning already applied to `sbig`'s own bundled firmware. Moved into the
explicit-grant tier alongside `fli`; `%package fishcamp`/`fishcamp-dev` (RPM)
and `indi-stable-3rdparty-libs-fishcamp[-dev]` (Debian) added to both `-libs`
specs, and the matching `indi-fishcamp` driver (LGPL-2.1-or-later, same
grant as its seven `-drivers` siblings, confirmed by reading
`indi_fishcamp.cpp`'s own header) added to both `-drivers` specs.

**A real defect found integrating fishcamp, on both distros: the shared
firmware directory.** `libsbig` and `libfishcamp` both install into the
identical `FIRMWARE_INSTALL_DIR` (redirected project-wide into
`%{indi_prefix}/share/indi/firmware`), with no per-vendor subdirectory of
their own. The RPM spec's pre-existing `%files sbig` claimed that whole
directory with one recursive glob (`%{indi_prefix}/share/indi/firmware/`)
— harmless while sbig was the only occupant, but adding fishcamp's own
identical glob would have made both subpackages claim the same files and
fail the build with "file listed twice". The Debian side had the
equivalent risk: `indi-stable-3rdparty-libs-sbig.install` matched the whole
directory, and a matching entry in fishcamp's own `.install` would have
shipped the same paths in two independently-installable binary packages —
not a build failure there, but a real `dpkg` conflict the first time
someone tried to install both together. Fixed identically on both distros:
every firmware image named explicitly, one vendor's worth per subpackage,
plus (RPM only, since Debian has no `%dir`-equivalent ownership rule)
`%dir %{indi_prefix}/share/indi/firmware` declared independently by both
`sbig` and `fishcamp`, the same pattern `%files asi`'s own comment already
established for `%{indi_prefix}`/`%{indi_libdir}`.

Both specs rebuilt and verified end to end on both distros, 2026-08-27 —
build, install alongside `indi-stable-core` and the other eight vendors in
one transaction, `indi_fishcamp_ccd` resolving every private-prefix library
via `ldd` and actually running (prints its usage banner), and full removal
restoring both `fedoraastro` and `ubuntuastro` to their exact baselines.
See `STATUS.md` for the full verification detail.

### Build ordering is now three stages, not two

`libapogee` and `libfli` both `find_package(INDI REQUIRED)` to configure,
which fails the whole tree's single cmake invocation if unmet even though
neither actually links `INDI_LIBRARIES` — so `indi-stable-3rdparty-libs` needs
`indi-stable-core-devel` as a `BuildRequires`, and `FindINDI.cmake`'s
documented `-DINDI_ROOT=<path>` is what lets it find core in the private
prefix rather than a standard system location. Combined with the
libs-before-drivers ordering already decided, the real sequence a promotion
pipeline must respect is **core, then 3rdparty-libs, then 3rdparty-drivers** —
not yet reflected in any build automation, since none exists yet.

## `pyindi-client` — packaging decisions, established 2026-08-26

Two decisions made before writing `pyindi-client/deb/`, both checked against
the real upstream repository rather than assumed.

### Built from an untagged PyPI release, not the last git tag — a narrow,
### justified exception to "never git master"

`indilib/pyindi-client`'s newest **git tag** is `v2.1.2`. Its newest **PyPI**
release is `2.2.0`, with **no corresponding git tag at all** — checked via
the GitHub tags API, 2026-08-26. These are not close substitutes: `v2.1.2`'s
`setup.py` links a **static** `libindiclient.a`, hard-searched in a fixed
list of system paths (`isfile(join(lindipath, "libindiclient.a"))`, failing
the build if absent) — an artifact **this project's `core/` never
builds** (upstream INDI's own CMake default is shared libraries only, which
`core/rpm` and `core/deb` both simply inherit, same as every other
component). `2.2.0` replaced that entirely with the `setup.cfg`-driven
dynamic-linking build actually described below — the one shape that can link
against a private-prefix shared `libindiclient.so` at all.

Building from `2.1.2` to stay strictly tag-only would mean teaching
`indi-stable-core` to *additionally* produce `libindiclient.a` — a new
artifact type nothing else in this project ships, changing already-built and
fully-verified core packaging on both distros for the sake of a static-link
approach upstream itself has since abandoned. Decided against.

**What's actually built instead: the exact commit PyPI already published as
`2.2.0`**, not an arbitrary point on a moving branch. Confirmed by diffing
PyPI's sdist against `master` HEAD (`c79c1bfd`, 2026-01-22) directly, not
inferred from the version string alone: `indiclientpython.i` — the actual
SWIG interface, i.e. the substantive binding-generation source — is
byte-for-byte identical. `setup.py`/`setup.cfg` differ only cosmetically (an
autoformatter's line-wrapping, and an `[egg_info]` stanza PyPI's own sdist
build auto-adds), confirmed by reading the diff, not by trusting that a
"formatting-only" claim was safe to assume. `master`'s own `pyproject.toml`
already reads `version = "2.2.0"`, so this is upstream's own released state,
just missing the tag that would normally mark it — not this project tracking
an unstable moving target. Should upstream ever tag `2.2.0` (or move past
it) retroactively, rebuild from the real tag instead; this exception is
scoped to the one release, not a standing policy change.

### The built module installs to standard `dist-packages`, not under
### `/opt/indi-stable`

Unlike every other artifact this project ships, `PyIndi.py` and
`_PyIndi*.so` install to the ordinary system Python location
(`/usr/lib/python3/dist-packages/PyIndi/`), not the private prefix. This is
not an exception to "coexistence, the one rule everything else serves"
(`CLAUDE.md`) — it is what that rule actually requires once the collision
surface is identified correctly for this artifact type. `CLAUDE.md`'s
private-prefix rule exists for artifacts with a **real path- or
metadata-level collision surface**: a binary named `indiserver` that any
`PATH` lookup can find regardless of package name, a header at
`/usr/include/libindi` that the compiler's search order favours over
`/usr/local`, a `.so` whose SONAME another package's `shlibs` can advertise.
A Python package named `PyIndi` has none of these — confirmed 2026-08-26,
`apt-cache search pyindi` and `apt-cache search indi-client` both return
nothing on Ubuntu's archive, so there is no distribution package of any name
this could shadow, and Python's own per-interpreter import resolution is not
a filesystem SONAME collision in the first place.

The one part of this package that *does* carry the real collision risk —
which `libindiclient.so` its compiled `_PyIndi*.so` extension resolves at
runtime — is handled the same way as everywhere else in this project: `-Wl,
-rpath,/opt/indi-stable/lib` baked into the extension at link time, so it
finds `indi-stable-core-libs`'s copy regardless of what else with the same
SONAME is on the box. Forcing the **file location** into `/opt/indi-stable`
as well would have added real friction — every user would need a manual
`PYTHONPATH` addition, or this packaging would need to drop a `.pth` file
into system site-packages anyway (itself a file outside the private prefix,
so it wouldn't even fully avoid the exception) — for no coexistence benefit,
since the private RPATH already does the only load-bearing part.

### Evidence, 2026-09-03: a plain `pip install` of this exact release is not
### reliably reproducible, even with headers held constant

Live incident on ACS's NUC, independent of this project's own build —
stronger support for shipping `indi-stable-pyindi-client` at all than the
mismatched-headers reasoning above, because there was no header drift to
blame here. Two Fedora 44 accounts on one machine, identical system
`libindi`/`libindi-devel` throughout (`dnf history` confirmed neither had
been touched since the machine was built). Account A had a working
`pip install pyindi-client==2.2.0` from initial setup. Account B ran the
identical command against the identical headers and got a build that pip
reported as successful but was internally broken: the SWIG-generated
`PyIndi.py` calls `_PyIndi.BaseDevice___nonzero__`, and the
freshly-compiled `_PyIndi` extension did not export that symbol. Effect:
every `newDevice`/`newProperty` callback raised `AttributeError` inside
libindi's C++ callback thread — invisible unless something is specifically
watching for it, which is exactly how it presented in ACS (a generic
connection timeout, not an obvious build error). Only fix that worked:
copy account A's already-compiled `PyIndi` module over account B's; a
second `pip install` of the same version did not reproduce a working
build. Root cause not pinned down — candidates are SWIG codegen sensitivity
to local build-environment state, or PyPI not serving a byte-identical
sdist across separate downloads under one version string — worth revisiting
once this project's own `pyindi-client/` build exists, by comparing its
output against a plain `pip install` deterministically, same machine, same
headers, repeated. Full incident write-up: ACS's `LESSONS_LEARNED.md`, INDI
section, #11.

## Upstream build-system facts the packaging depends on

Checked against INDI's real sources, not assumed. Each of these is the reason a
specific line in the spec or `debian/rules` looks the way it does; changing the
packaging without knowing them reintroduces a bug that was already fixed.

- **`UDEVRULES_INSTALL_DIR` is the single INDI install path not derived from
  `CMAKE_INSTALL_PREFIX`** — it is an absolute `/lib/udev/rules.d`. Left alone
  it installs `99-indi_auxiliary.rules` and `80-dbk21-camera.rules` under names
  the distribution package already owns: a hard file conflict, and one the
  private prefix does *not* protect against. **Both packagings redirect it and
  rename the files**, preserving the numeric prefix because udev applies rules
  in lexical order. They land in `/usr/lib/udev/rules.d` rather than `/lib`:
  Debian 12+ and Ubuntu 22.04+ are merged-usr where `/lib` is an alias symlink,
  and that path also matches Fedora's `%{_udevrulesdir}`. A grep for other
  absolute `DESTINATION`s found none — this is the only one.
- **`CMAKE_INSTALL_LIBDIR` must be passed RELATIVE (`lib`).** Fedora's `%cmake`
  macro passes it absolute, and INDI derives `PKGCONFIG_INSTALL_PREFIX` straight
  from it (`CMakeLists.txt:83`), so an absolute value drops `libindi.pc` into
  the *system* pkgconfig directory — outside the prefix, colliding with
  `libindi-devel`.
- **The GitHub tarball for tag `vX.Y.Z` unpacks to `indi-X.Y.Z`.** The leading
  `v` is stripped, so `%autosetup` takes `%{version}`, not the tag.
- **`FIX_WARNINGS=OFF` is deliberate, not laziness.** It is upstream's own
  `-Werror` escape hatch (`cmake_modules/CMakeCommon.cmake`). A pinned tag will
  always eventually meet a compiler newer than itself, and gcc 15 already broke
  `drivers/telescope/astrotrac.cpp` exactly this way. Absorbing that class of
  breakage before it reaches users is much of why this layer exists.
- **`check-rpaths` rejects `/opt` from a hardcoded allowlist**, not because
  anything is wrong. Reading `/usr/lib/rpm/check-rpaths-worker`, the classifier
  allows `/lib/*`, `/usr/lib/*`, `/lib64/*`, `/usr/lib64/*`, `/usr/libexec/*`
  and `$ORIGIN`, and everything else falls through to `(*) badness=2` (line
  141). The spec sets `QA_RPATHS=$(( 0x0002 ))` to downgrade **only** that class
  to a warning. Deliberately *not* `%global __brp_check_rpaths %{nil}`, which
  would switch the whole check off and lose `0x0004` (insecure *relative*
  RPATH) and `0x0020` (`..` traversal) — both of which would be real bugs worth
  failing on.

## Build-logic portability (the COPR/OBS dependency question)

The concern — "if COPR has problems or takes a break, we're stuck" — is
real but splits in two:

- **Platform disappearing:** low probability. COPR is Fedora Project
  infrastructure; OBS is SUSE-backed and long-running. Short outages stall
  *new* builds while already-published packages keep serving.
- **This project going stale:** the real, already-observed risk — and
  exactly what happened to the existing INDI COPR. That is a maintainer
  continuity problem, not a platform problem, and it would bite identically
  under self-hosted CI if builds needed a human to trigger them.

So the mitigation is not avoiding COPR/OBS, but **never letting packaging
logic live only inside their dashboards**:

- Spec file, `debian/` control files, and promotion automation live in this
  repo as the single source of truth.
- COPR/OBS are triggered via webhook/API on a promoted tag — compute and
  hosting backends this repo drives, not where the definition lives.
- Because `rpmbuild`/`debbuild` are the same wherever they run, a
  self-hosted fallback (own CI + a static repo) is a config change, not a
  rewrite. **Not built for v1** — just don't paint into a corner.

## Patch mechanism (no fork needed yet)

Build directly from upstream tags; no mirror required. Keep a `patches/`
directory applied per-version for the compiler-drift class of bug ACS
already hit once (`astrotrac.cpp` tripping `-Werror` on gcc 15, against a
tag that predates it). A pinned/tagged build hits exactly these, and a patch
here unblocks a release without waiting on an upstream merge. Revisit
forking only if patches accumulate enough to be worth carrying permanently.

---

## Proposed repo structure

```
indi-stable/
├── README.md              — what this is, explicitly unofficial,
│                            how to add the repo, how to switch
├── DESIGN.md              — this plan, kept live (UBUNTU_PORT.md model)
├── LICENSE                — MIT (packaging metadata only; note INDI's own
│                            licensing is unaffected)
├── core/
│   ├── rpm/indi-stable-core.spec
│   └── deb/               — control, rules, changelog template
├── 3rdparty/
│   ├── rpm/               — per-driver specs, or templated from a list
│   └── deb/
├── pyindi-client/
│   ├── rpm/indi-stable-pyindi-client.spec
│   └── deb/
├── patches/               — per-version, applied at build time
├── scripts/
│   ├── check_upstream_tags.py   — poll indilib/indi + indi-3rdparty
│   ├── promote.py               — candidate -> release once gated
│   └── smoke_test.sh            — clean-container install + driver load
├── versions.json          — last-built tag per component; single source
│                            of truth (SetupState pattern)
└── .github/workflows/
    ├── check-upstream.yml
    ├── build.yml          — new tag -> candidate
    ├── smoke-test.yml     — the gate
    └── promote.yml        — candidate -> release on gate pass
```

---

## Release automation, v1 — decided 2026-08-27

Built once `core/`, `3rdparty/`, and `pyindi-client/` were all fully built,
installed, and coexistence/upgrade-tested by hand on both distros
(`STATUS.md`) — the precondition `CLAUDE.md` sets for CI existing at all.
Diverges from the "Proposed repo structure" above in three ways, each
decided in conversation with Will before writing anything:

- **Scope: `indi-stable-core` only, not all three components.** Standing
  up automation for three independent release trains (core, 3rdparty
  libs+drivers, pyindi-client) at once, each across two distros, multiplies
  the ways a first attempt can fail — the same reasoning `CLAUDE.md`
  already applies to the packaging itself ("Automating a build that has
  never succeeded means debugging the packaging and the automation
  simultaneously"). Extending the pattern to 3rdparty and pyindi-client
  once core's pipeline is proven is mechanical repetition, not new design.
- **No COPR/OBS yet.** Neither account exists. `DESIGN.md`'s own
  "Build-logic portability" section above already treats this as
  deferrable ("a self-hosted fallback... is a config change, not a
  rewrite"), so a gated build becomes a **GitHub Release** instead —
  real, working, automated, and needs no new accounts. COPR/OBS remain a
  pure distribution upgrade for later, not a redesign.
- **GitHub-hosted runners, not self-hosted on `fedoraastro`/`ubuntuastro`.**
  Those VMs cannot stay up permanently to serve a scheduled poll, and a
  self-hosted runner on a private machine executing code from CI triggers
  is a real, different security exposure than GitHub's own thrown-away-
  after-the-job runners. The build steps don't need anything VM-specific
  either: `mock` (RPM side) and the deliberate absence of `pbuilder`/
  `sbuild` (Debian side, `LESSONS_LEARNED.md` #12) both exist to protect a
  *persistent host's* state — moot inside an already-disposable CI
  container, which makes the RPM build actually **simpler** in CI than by
  hand: `rpmbuild -bb` directly, no `mock` chroot wrapping needed.

**Shape: one workflow file, sequential jobs, not four files triggering
each other.** The "Proposed repo structure" above sketches
`check-upstream.yml` pushing a `versions.json` update that `build.yml`
then reacts to — but the default `GITHUB_TOKEN` cannot re-trigger a
workflow from its own push (GitHub's own loop-prevention), so that shape
would silently never fire. `.github/workflows/core-release.yml` instead
chains `check` → `build-fedora`/`build-debian` → `smoke-test-fedora`/
`smoke-test-debian` → `promote` as jobs within one workflow, connected by
`needs:` and job outputs/artifacts. `versions.json` is still the single
source of truth (`core`, `3rdparty`, `pyindi-client` all seeded with their
already-verified current state; only `core`'s fields are touched by v1).

**The gate, concretely** (`scripts/smoke-test-core.sh` /
`-core-deb.sh`, new): install the just-built packages into the CI
container itself (already fresh — nothing to engineer there, unlike the
manual VM harnesses in `scripts/test-*` which assert against a specific
snapshotted baseline these do not have and should not fake), confirm
`indiserver-stable` reports a version, confirm `indi_simulator_ccd
--help` prints a usage banner. That last check went through a real,
caught-by-hand defect: the first version ran the driver with stdin
closed (`</dev/null`) expecting a usage banner the way one vendor driver
had shown earlier the same day — instead every INDI driver just prints
`"<name>: EOF"` and exits on closed stdin with no args at all. `--help`
is what actually and reliably produces the banner; confirmed by running
both scripts for real against already-built core packages on
`fedoraastro` and `ubuntuastro` before ever trusting them in an untested
CI workflow.

**No repo secrets needed.** `permissions: contents: write` on the
workflow is the only elevated access required — the built-in
`GITHUB_TOKEN` covers pushing the promotion commit and creating the
GitHub Release.

**The repo stays private throughout**, including through all testing of
this pipeline — see `STATUS.md`'s "Undecided" section for the sweep/scrub
that is a prerequisite before that ever changes.

## What this does NOT change on the ACS side

ACS's version-detection and coexistence machinery (`indi_version.check()`,
`_verify_indi_drift()`, the removal-cascade guard) **stays**. This project
changes ACS's install path from "compile INDI from source" to "add this
repo and install" — but ACS must still detect what is actually running on a
given machine (indi-stable, the distro's official package, the volunteer
COPR, or nothing) and behave safely in each case.

Note also what a venv does *not* fix, since ACS just moved to one: which
`libindiclient.so` pyindi-client compiles and links against is decided by
header/library search order and rpath, entirely outside Python's view.

---

## Historical: first concrete steps (all now done or superseded)

Kept for the record, not as a live plan — every step below has either
happened or been superseded by a later decision documented above.

1. ~~Create the org and the `indi-stable` repo~~ — done; the org is
   `indi-stable`, no broader name was ever needed.
2. ~~Write the core spec file and get one target building by hand~~ — done,
   `core/rpm/indi-stable-core.spec`, verified on `fedoraastro` (`STATUS.md`).
3. ~~Add the `debian/` equivalent, verify on OBS~~ — done for the `debian/`
   equivalent (`core/deb/`, verified on `ubuntuastro`); OBS itself was never
   used — see "Release automation, v1" above for why COPR/OBS are deferred
   rather than adopted for v1.
4. Build the automation — see "Release automation, v1" above.
