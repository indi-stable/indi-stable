# Fedora — building and verifying the RPM

Procedure and platform specifics. What is *left* to do is in `STATUS.md`; why
the design is what it is, in `DESIGN.md`; generic gotchas, in
`LESSONS_LEARNED.md`.

## What is already verified

Stated as conclusions. The evidence is in the cited commits rather than repeated
here.

| | |
|---|---|
| Builds clean from tag `v2.2.4.2` | gcc 16.2.1, 660/660 targets, six subpackages (`0e7a076`) |
| All 25 `BuildRequires` resolve | from a bare `mock` chroot, 277 packages, no errors (`0e7a076`) |
| Installs without disturbing the distro | `/usr/bin/indiserver` byte-identical, `rpm -V libindi` and `rpm -V kstars` both 0 (`0e7a076`) |
| Both INDIs run simultaneously | each driver maps its own libraries despite shared SONAMEs — but only with distinct `-u` sockets; see `DESIGN.md` (`913d760`, `0e7a076`, re-verified 2026-08-25) |
| Package metadata does not shadow | `dnf` still pulls in `libindi-libs` for stellarium with ours installed (`913d760`) |
| Upgrades keep the alternative | the `%postun` `$1 -eq 0` branch behaves (`0e7a076`) |
| Uninstalls clean | including the `/var/lib/alternatives` admin record (`4f52f10`) |
| RPATH coverage is total | 209 ELF files shipped, 209 carry it (`ff6b91f`) |
| `-devel` coexists with `libindi-devel` | headers, `.pc` and `pkg-config` resolution all stay the distribution's; 127 distro files byte-identical across the cycle |
| Ekos runs on the distribution's INDI with ours installed | all 5 processes KStars spawned resolve to `/usr`, including the dlopen'd MathPlugin (2026-08-25) |
| A consumer built against `-devel` compiles, links **and runs** | in a `mock` chroot holding both INDIs; rpath, `ldd` and both `#include` spellings all land in our tree, and the pre-fix defect reproduces as the control (2026-08-25) |
| Our drivers carry `DT_RUNPATH`, not `DT_RPATH` | same as Ubuntu; `LD_LIBRARY_PATH` therefore overrides it — see `DESIGN.md` (2026-08-25) |
| The driver catalogue is fully rewritten to absolute paths | `scripts/test-catalogue-rewrite.sh` against the RPM payload: 288 entries, 0 shipped drivers left bare, all three controls fire (2026-08-25) |

## Platform gotchas

Fedora- and `dnf`-specific. Cross-platform ones are in `LESSONS_LEARNED.md`.

- **The `mock` group exists but is empty on a fresh Fedora.** This is the first
  thing that will stop a `mock` build. `sudo usermod -a -G mock $USER`, then
  **`sg mock -c '<command>'` picks the group up without a re-login** — verified.
- **`dnf5` defaults to `keepcache=0`**, so a removed package is re-downloaded on
  reinstall. Use `dnf remove --no-autoremove` to keep large data subpackages
  (`stellarium-data` is 613 MiB) when resetting between runs.
- **`indiserver -v` is a verbosity flag, not `--version`**, and with no driver
  argument it prints usage and exits 2.
- **Fedora's `%cmake` passes `CMAKE_INSTALL_LIBDIR` absolute**, which INDI turns
  into `PKGCONFIG_INSTALL_PREFIX`; the spec overrides it to a relative `lib`.
  See `DESIGN.md`.
- **`check-rpaths` rejects `/opt` from a hardcoded allowlist**, not because
  anything is wrong. `QA_RPATHS=$(( 0x0002 ))` downgrades only that class. See
  `DESIGN.md` for why not `%global __brp_check_rpaths %{nil}`.

## Building

From a bare OS:

```bash
sudo dnf install -y rpm-build rpmdevtools mock
rpmdev-setuptree
cd ~/src/packaging          # the repo clone -- NOT ~/src/indi-stable

# Fetch the upstream tarball named in the spec's Source0
spectool -g -R core/rpm/indi-stable-core.spec
```

Then either path below. **Prefer `mock` unless you are actively editing the
spec** — it is both the stronger dependency test and the only one that leaves
the host clean, and at under four minutes it is no longer the slow option.

### `mock` — clean-room, leaves the host untouched

```bash
# One-time: the mock group exists but is EMPTY on a fresh Fedora.
sudo usermod -a -G mock $USER

rpmbuild -bs core/rpm/indi-stable-core.spec

# Match the chroot to the host release -- confirm, do not assume:
#   rpm -E %fedora   against the cfg's releasever
# An older chroot is a DIFFERENT test and would not catch the compiler drift
# this project exists to absorb.
sg mock -c 'mock -r fedora-44-x86_64 --resultdir=/home/'$USER'/mock-result \
    /home/'$USER'/rpmbuild/SRPMS/indi-stable-core-2.2.4.2-1.fc44.src.rpm'
```

Measured 2026-08-24: **3m53s** cold on 8 vCPU; a second build with a warm chroot
took 3m07s.

**`--resultdir` puts the `.src.rpm` beside the binaries**, so anchor any glob
pointed at it to `*.x86_64.rpm` — see `LESSONS_LEARNED.md` #3.

### `rpmbuild` — faster edit/retry while changing the spec

```bash
sudo dnf builddep -y core/rpm/indi-stable-core.spec
rpmbuild -ba core/rpm/indi-stable-core.spec 2>&1 | tee /tmp/indi-stable-build.log
```

**This installs ~122 packages including a toolchain onto the host.** Do not run
it on a machine you also intend to use as a coexistence test subject: every
later "the distribution package is untouched" claim would then be made on a box
you altered to get there.

## Known remaining build risks

The `BuildRequires` risk that used to head this list is **retired** — all 25
resolved from a bare chroot (`0e7a076`).

1. **`INDI_BUILD_DRIVERS=ON` builds all ~199 bundled drivers.** A wide surface
   for compiler drift. `FIX_WARNINGS=OFF` should absorb the `-Werror` class, but
   a hard error will still stop the build. If one driver blocks everything, that
   is what `patches/` is for.
2. **udev rules.** If the `auxiliary` and `video` driver categories did not
   build, the files will not exist and the `%files` glob fails the build for a
   missing file — a legitimate outcome to notice, not to paper over.

## Checklist once it builds

**Anchor these globs to `*.x86_64.rpm` before pointing them at a `mock`
resultdir.** They are written for `~/rpmbuild/RPMS/x86_64`, which holds only
binary RPMs; a resultdir holds the `.src.rpm` too and item 1 will report the
spec and the tarball as escapees. The checked-in scripts are already anchored.

```bash
R=~/rpmbuild/RPMS/x86_64          # or your mock resultdir

# 1. Nothing escapes the private prefix except the udev rules.
#    /usr/lib/.build-id is RPM's own debuginfo bookkeeping and is expected;
#    filter it out or it buries the answer in ~300 lines of hashes.
rpm -qlp $R/indi-stable-core-2*.rpm \
  | grep -v '^/opt/indi-stable' | grep -v '^/usr/lib/\.build-id'
#    expect: the two udev rules, plus %doc and %license. Nothing else.

# 2. No file under /usr/bin at all -- this is what guarantees no conflict
#    with indi-bin, which kstars depends on.
rpm -qlp $R/indi-stable-*.rpm | grep '^/usr/bin' && echo "PROBLEM"

# 3. pkgconfig landed inside the prefix
rpm -qlp $R/indi-stable-core-devel-*.rpm | grep pkgconfig

# 4. udev rules renamed
rpm -qlp $R/indi-stable-core-2*.rpm | grep udev

# 5. RPATH is really set (the coexistence guarantee).
#    Check a DRIVER, not just indiserver: indiserver links NO libindi library
#    at all (only libev/libnova/libc), so testing it alone proves nothing about
#    library separation. The drivers and the MathPlugins are what matter.
rpm2cpio $R/indi-stable-core-2*.rpm      | cpio -idm --quiet
rpm2cpio $R/indi-stable-core-libs-2*.rpm | cpio -idm --quiet
readelf -d opt/indi-stable/bin/indi_simulator_ccd | grep -E 'RPATH|RUNPATH'
readelf -d opt/indi-stable/lib/indi/MathPlugins/libindi_SVD_MathPlugin.so \
                                                  | grep -E 'RPATH|RUNPATH'
#    Stronger: every shipped ELF file should carry it, not just a sample.
#    209 of 209 as of 2.2.4.2.

# 6. It runs, and reports the version we think it does.
#    NOT `-v | head -3` -- see the platform gotchas above and
#    LESSONS_LEARNED.md #7.
./opt/indi-stable/bin/indiserver --version 2>&1 | grep -E 'INDI Library|Code'
#    expect: INDI Library: 2.2.4  (from tag v2.2.4.2 -- the fourth tag
#    component is not part of the CMake version. This is correct, not a
#    mismatch, and it CANNOT distinguish our build from the distro's.)

# 7. METADATA coexistence -- we must not advertise the distro's SONAMEs.
#    This is the layer with no files in it, so items 1-6 cannot see it.
#
#    NOTE THE `-2*` GLOBS: `indi-stable-core-libs-*.rpm` also matches the
#    DEBUGINFO subpackage, whose Provides legitimately end in `.debug()(64bit)`.
#    A loose grep flags those and the step cries wolf.

#    Provides must contain NO libindi* soname at all:
rpm -qp --provides $R/indi-stable-core-libs-2*.rpm \
  | grep -E 'libindi.*\.so' && echo "PROBLEM: shadowing libindi-libs" \
                            || echo "OK - no soname provides"

#    Requires must have DROPPED the private libindi* sonames but KEPT the
#    real external ones. Both halves matter -- see DESIGN.md.
rpm -qp --requires $R/indi-stable-core-2*.rpm \
  | grep -E 'libindi.*\.so' && echo "PROBLEM" || echo "OK - filtered"
rpm -qp --requires $R/indi-stable-core-2*.rpm \
  | grep -E 'libcfitsio|libnova' || echo "PROBLEM: real deps filtered too"

#    The decisive check: our Provides must not intersect the distro's.
#    USE `dnf repoquery`, NOT `rpm -q` -- rpm asks about the INSTALLED package,
#    so on a clean-slate machine it prints nothing, the comm is trivially empty,
#    and the step PASSES WITHOUT TESTING ANYTHING. That is precisely the machine
#    this check matters most on. repoquery needs nothing installed.
comm -12 <(dnf repoquery --provides libindi-libs | grep '\.so' | sort -u) \
         <(rpm -qp --provides $R/indi-stable-core-libs-2*.rpm \
             | grep '\.so' | sort -u)
#    ^ must print NOTHING.

#    CONFIRM THE CHECK COULD HAVE FAILED -- positive control, the same pipeline
#    against itself. MUST print the distro's six sonames:
comm -12 <(dnf repoquery --provides libindi-libs | grep '\.so' | sort -u) \
         <(dnf repoquery --provides libindi-libs | grep '\.so' | sort -u)

#    Belt and braces -- the single question that actually matters:
rpm -qp --provides $R/indi-stable-core-libs-2*.rpm \
  | grep -x 'libindiclient.so.2()(64bit)' \
  && echo "PROBLEM: can satisfy stellarium/phd2" || echo "OK - cannot"
```

## Verifying on a machine that already has the distro INDI

This is the real test of the whole design. Most of it is automated — prefer the
harnesses, which carry their own preconditions and positive controls:

```bash
sudo bash scripts/test-snapshot-a-depsolve.sh [rpm-dir]    # metadata layer -- see the warning below
sudo bash scripts/test-snapshot-b-coexist.sh [rpm-dir]     # structural, needs libindi + kstars
sudo bash scripts/test-upgrade-path.sh <old-dir> <new-dir> # the %postun branch
sudo bash scripts/test-devel-coexist.sh [rpm-dir]         # headers and .pc, see below
bash      scripts/test-devel-compile-mock.sh [rpm-dir]     # compiles a consumer; NOT as root
bash      scripts/test-catalogue-rewrite.sh [xml] [bindir] # no root needed
bash      scripts/test-runtime-maps.sh [server] [driver] [port]   # no root needed
```

**Pass `[rpm-dir]` on `fedoraastro`.** It defaults to `~/rpmbuild/RPMS/x86_64`,
which is empty there — the builds go through `mock` and land in
`~/mock-result-pcfix` (`STATUS.md`, machine state). Without it the harnesses
abort at their first step rather than measuring an unprepared box.

**`test-snapshot-a-depsolve.sh` is the one harness that does NOT restore the
box, and that is deliberate** — it exists to leave the machine in Snapshot A.
It removes `libindi-libs`, which takes `libindi` and `kstars` with it, and then
installs `stellarium` and ~700 MiB of its dependencies. Every other harness here
diffs against a baseline it took itself and puts the box back.

So before running it, record the baseline and prove the restore is possible,
rather than trusting that it is:

```bash
rpm -qa | LC_ALL=C sort > /tmp/baseline.txt      # LC_ALL=C: comm compares bytes
dnf download libindi libindi-libs kstars         # insurance, before anything is removed
```

Afterwards, restore by diffing rather than by naming (`LESSONS_LEARNED.md` #6),
then assert the difference is empty:

```bash
rpm -qa | LC_ALL=C sort > /tmp/now.txt
sudo dnf remove -y --no-autoremove $(comm -13 /tmp/baseline.txt /tmp/now.txt | sed 's/-[^-]*-[^-]*$//')
sudo dnf install -y $(comm -23 /tmp/baseline.txt /tmp/now.txt | sed 's/-[^-]*-[^-]*$//')
rpm -qa | LC_ALL=C sort | diff /tmp/baseline.txt -   # must print nothing
```

Done that way on 2026-08-26 the box came back byte-identical at 2153 packages.
The removal list that run produced was **18** packages against the 2 the
transaction log made obvious — `stellarium` drags in Qt6 modules, `assimp`,
`NLopt` and a 613 MiB data package — which is why the list is measured and not
written out.

By hand, the parts that matter:

```bash
# Use an ABSOLUTE path -- under sudo, ~ is /root.
sudo dnf install /home/$USER/mock-result/indi-stable-*.x86_64.rpm
rpm -V libindi                             # distro package must be untouched
readlink -e /usr/bin/indiserver            # -e NOT -f; see LESSONS_LEARNED.md #8
readlink -e /usr/bin/indiserver-stable     # -> /opt/indi-stable/bin/indiserver
alternatives --display indiserver-stable
kstars &                                   # must still start and see its own drivers
```

**Which build actually answered?** Not the version string — both report
`INDI Library: 2.2.4`. Use identity:

```bash
sha256sum /usr/bin/indiserver /opt/indi-stable/bin/indiserver
```

**At runtime, not just structurally** — the check that settles the design. Read
what the *live process* mapped, which `ldd` can only predict:

```bash
# -u is NOT optional if anything else is already serving: indiserver binds the
# abstract socket @/tmp/indiserver regardless of -p, so a second server without
# its own -u dies with "Local server: bind: Address already in use".
/usr/bin/indiserver-stable -u /tmp/indiserver-stable -p 7625 \
    /opt/indi-stable/bin/indi_simulator_ccd &
SRV=$!; sleep 4
grep -m1 libindidriver /proc/$(pgrep -P $SRV | head -1)/maps
kill $SRV
# expect: /opt/indi-stable/lib/libindidriver.so.2.2.4
# repeat with /usr/bin/indiserver + /usr/bin/indi_simulator_ccd on 7626
# expect: /usr/lib64/libindidriver.so.2.2.4
```

**Do not use `pkill -f` to clean these up** — `LESSONS_LEARNED.md` #9.

Note `alternatives --display indiserver-stable` is a valid check *for the
namespaced name*. For the plain `indiserver` name it would report the admin
record rather than the link on disk, and nothing has ever registered under that
name here. If `--display` and `readlink -e` disagree for `indiserver-stable`,
that is a new finding, not the old one.

### Ekos — `scripts/observe-ekos-live.sh`, not a screenshot

Start KStars, open Ekos, start a simulator profile, leave it running, then run
the harness. It needs no root.

The GUI cannot answer the question on its own. Both catalogues carry the same
290 `name=` labels, and Ekos lists the label rather than the binary path — which
since the absolute-path rewrite is the only field that differs between them. So
the driver list reads identically whichever install is in use, and an eyeball
check would look like it was working while reading the one field that cannot
distinguish the two. The harness asks the version of the question that has a
filesystem answer: for every live `indiserver`/`indi_*` process, the resolved
`exe`, its owning package, and the `libindi` libraries actually mapped.

**There are two correct outcomes and the harness reports which it saw**, rather
than assuming one. With Ekos at its default `/usr/share/indi` everything must
resolve to `/usr` — ours installed but not asked for. With Ekos pointed at
`/opt/indi-stable/share/indi` the drivers must resolve to `/opt` — the opt-in
working. See `DESIGN.md`, "Resolution — absolute paths in our `drivers.xml`".

A pass in the first case means Ekos still **works** alongside ours, which is the
coexistence rule's whole point since `kstars` depends on `indi-bin`.

The result on 2026-08-25, with `indi-stable-core` and `-libs` installed: five
processes, all `/usr/bin/*`, all owned by `libindi-2.2.4.1`, all mapping
`/usr/lib64/libindi*`. `rpm -V` stayed clean on `libindi`, `libindi-libs` and
`kstars` throughout, and `/usr/bin/indiserver` still hashed `cb0244f8...`.

**Re-run 2026-08-26 with the same result, and with the positive control the
first run lacked.** That run also read the `dlopen`'d
`/usr/lib64/indi/MathPlugins/libindi_Nearest_MathPlugin.so`, a third resolution
mechanism which stays in `/usr` too. The control starts our own `indiserver`
alongside Ekos's — with its own `-u` — and the same scanner reports
`/opt/indi-stable` immediately, so "nothing touched `/opt`" is an observation
rather than a scanner that could not have seen it.

Worth noting what the telescope simulator added: it `dlopen`ed
`/usr/lib64/indi/MathPlugins/libindi_Nearest_MathPlugin.so`, owned by
`libindi-libs`. That is a **third** resolution mechanism — not SONAME/RPATH, not
the header/`.pc` search order, but a runtime path lookup — and it also stayed on
the distribution's side. Our own driver dlopens the equivalent out of
`/opt/indi-stable/lib/indi/MathPlugins/`; the two do not meet.

### The `-devel` subpackage — a different mechanism, so a separate test

`scripts/test-devel-coexist.sh` covers this; run it rather than the steps by
hand. It is separate from the coexistence harnesses because headers and `.pc`
files are separated by **search order**, not by SONAME or RPATH — none of the
mechanisms items 1-7 exercise apply. Both packages ship a module named exactly
`libindi`:

| | |
|---|---|
| ours | `/opt/indi-stable/lib/pkgconfig/libindi.pc`, headers in `/opt/indi-stable/include/libindi` |
| distro | `/usr/lib64/pkgconfig/libindi.pc`, headers in `/usr/include/libindi` |

`/usr/include` wins the compiler's search order and `/usr/lib64/pkgconfig` wins
`pkg-config`'s, so a single leaked header or `.pc` file would silently take
precedence. That is why headers must never go to `/usr/include/libindi`
(CLAUDE.md).

The harness installs the distribution's `libindi-devel` first, then ours *in one
transaction* — rpm's file-conflict detection runs across a whole transaction, so
that is the strongest form of the question — and on success removes everything
the run added, then asserts the whole installed package set matches the
baseline it recorded at STEP 0.

**It does not spend the VM snapshot.** No compiler and no build dependencies
are dragged in, and STEP 9 asserts `gcc` is still absent rather than trusting
it — that absence is what makes any untouched-distro result on that box mean
anything (see `STATUS.md`).

What the two transactions actually add, measured rather than predicted, is
**five** packages: `libindi-devel` brings `libindi-static` *and* `libindi-qt`
(which provides `libindiclientqt.so.2`), and ours brings `erfa`. That last one
is a real difference between the two builds and not a mistake — our
`indi-stable-core-libs` requires `liberfa.so.1` and the distribution's
`libindi-libs` does not. STEP 10 removes whatever it observes the run added, so
a sixth dependency appearing in a later Fedora will still be cleaned up.

Note the decisive check cannot be "it compiles" *in this harness*, precisely
because there is no compiler on that VM — but it does not have to happen on the
box at all. `scripts/test-devel-compile-mock.sh` runs it in a `mock` chroot that
has a compiler already, leaving the host gcc-less (`LESSONS_LEARNED.md` #15). The stand-in is `pkg-config` resolution — run both
as root and as the invoking user, since a leaked `profile.d` snippet would only
show up for one of them — plus `rpm -qf` on the header the compiler would
actually find.

> **That stand-in is insufficient, and it is what let two real defects
> through.** `LESSONS_LEARNED.md` #15 has the full account. In short: `Libs:`
> was missing `-Wl,-rpath` and `Cflags:` was missing `-I${includedir}`.
> `pkg-config --variable=prefix` and `--cflags` answer identically in the broken
> and fixed cases — the broken `--cflags` output *is* the defect, and it looks
> reasonable. Run the compile test below as well; neither harness subsumes the
> other.

### The driver catalogue — no install needed

`scripts/test-catalogue-rewrite.sh` is package-manager-agnostic and takes the
catalogue and bindir as arguments, so on Fedora it can read an **extracted RPM
payload** and needs neither root nor an install:

```bash
mkdir /tmp/x && cd /tmp/x
rpm2cpio ~/mock-result-pcfix/indi-stable-core-2*.x86_64.rpm | cpio -idm
cd ~/src/packaging
bash scripts/test-catalogue-rewrite.sh \
     /tmp/x/opt/indi-stable/share/indi/drivers.xml /tmp/x/opt/indi-stable/bin
```

The payload is what the package installs, so this answers the same question as
reading the installed tree, on a box that stays at baseline.

### The compile test — `scripts/test-devel-compile-mock.sh`

The half `test-devel-coexist.sh` cannot do, and the answer to the tension it
documents: the decisive `-devel` check is *it compiles, links and runs*, and
this box deliberately has no compiler. **A `mock` chroot has one already**, so
the compile costs the host nothing.

```bash
bash scripts/test-devel-compile-mock.sh [resultdir]   # default ~/mock-result-pcfix
```

Run as the build user, not root — `mock` refuses to run as root. The driver
initialises the chroot, installs the distribution's `libindi`, `libindi-libs`
and `libindi-devel` together with all three of ours *in one transaction*, copies
`scripts/inchroot-devel-compile.sh` in and runs it there. About ten seconds
against a warm chroot.

`libindi-libs` is named explicitly because `libindi-devel` does not require the
drivers package: a chroot given only `-devel` has no distribution
`libindiclient.so.2` at all, and the control below would have nothing to find.

It measures, on the *installed* files rather than the `%install` log:

| | |
|---|---|
| the `Libs:`/`Cflags:` lines of our `libindi.pc` | both fixes present |
| a consumer built with `PKG_CONFIG_PATH=` ours | compiles, links, **runs**, `RUNPATH [/opt/indi-stable/lib]`, `ldd` → our `libindiclient.so.2` |
| `<indiversion.h>` and `<libindi/indiversion.h>` | our tree with `PKG_CONFIG_PATH` set, the distribution's with none — `g++ -E -H` names the file actually opened |
| a shipped driver's dynamic tag | `DT_RUNPATH`, and `ldd` → our `libindidriver.so.2` |

`DATA_INSTALL_DIR` is the discriminator, never the version string: ours says
`/opt/indi-stable/share/indi/` and the distribution's `/usr/share/indi/`, while
both report `2.2.4` (`LESSONS_LEARNED.md` #11).

Every one of those passes by finding what it expects, so each has a **control**
built by undoing the two edits in a scratch copy of our own `.pc`. Both defects
then reproduce in the same chroot from the same source file — the qualified
include reaches `/usr/include`, and the un-rpath'd consumer loads the
distribution's library. If a control ever stops firing, the passes above stop
meaning anything.

**STEP 8 asserts the host was not spent**: `gcc` still absent, package count
unchanged, `/opt/indi-stable` still gone. STEP 9 cleans the chroot but leaves
`mock`'s package caches, so the next build still starts warm.

## Testing `indi-stable-3rdparty-libs`

Build it the same way as core (`rpmbuild -bs` then `mock`), except its
`BuildRequires: indi-stable-core-devel` has no repo to resolve from — install
core's already-built RPMs straight into the chroot first:

```bash
sg mock -c 'mock -r fedora-44-x86_64 --init'
sg mock -c 'mock -r fedora-44-x86_64 --install \
    ~/mock-result-pcfix/indi-stable-core-2*.x86_64.rpm \
    ~/mock-result-pcfix/indi-stable-core-libs-2*.x86_64.rpm \
    ~/mock-result-pcfix/indi-stable-core-devel-2*.x86_64.rpm'
rpmbuild -bs core/rpm/indi-stable-3rdparty-libs.spec
sg mock -c 'mock -r fedora-44-x86_64 --no-clean \
    --resultdir=~/mock-result-3rdparty \
    ~/rpmbuild/SRPMS/indi-stable-3rdparty-libs-*.src.rpm'
```

`--no-clean` is load-bearing: a plain `mock <srpm>` wipes the chroot first,
which would also remove the core RPMs `--install` just placed there.

Install/coexist/remove has been verified by hand against distro core INDI
(`libindi`/`libindi-libs`/`kstars`) — Fedora ships no distribution
`indi-3rdparty` package at all to coexist against (`DESIGN.md`), so that half
of "coexistence" isn't testable here. **Anchor the install command to
`*.x86_64.rpm`, excluding `-debuginfo`/`-debugsource`/`.src.rpm`** — installing
the `.src.rpm` alongside the real RPMs installs its `BuildRequires` as
`Requires` (`LESSONS_LEARNED.md` #21):

```bash
sudo dnf install -y \
  ~/mock-result-pcfix/indi-stable-core-2*.x86_64.rpm \
  ~/mock-result-pcfix/indi-stable-core-libs-2*.x86_64.rpm \
  ~/mock-result-pcfix/indi-stable-core-devel-2*.x86_64.rpm \
  $(ls ~/mock-result-3rdparty/*.rpm | grep -v -e debuginfo -e debugsource -e '\.src\.rpm')
```

The upgrade path is scripted, unlike the ad hoc install/coexist/remove pass
above:

```bash
sudo bash scripts/test-upgrade-path-3rdparty.sh <old-dir> <new-dir> [core-dir]
```

It looks different from core's own `test-upgrade-path.sh` because
`indi-stable-3rdparty-libs` has no scriptlets at all — no `%postun`, no
alternatives — so core's ordering bug class does not apply. What it tests
instead: upgrading 3rdparty-libs alone while `indi-stable-core` stays
installed and untouched (the two are independent source packages sharing
`/opt/indi-stable` — see `LESSONS_LEARNED.md` #20), no orphaned files left
behind by the file replacement (with a planted-file control proving that
check can actually find something), and the upgraded libraries still resolve
their RPATH and run. Needs a genuinely different NVR for `<new-dir>`; same
"bump `Release` in a scratch copy of the spec, never commit it" trick as
core's own upgrade test (`STATUS.md`, machine state).

## Testing `indi-stable-3rdparty-drivers`

Scoped to the same 8 vendors `-libs` bundles — see that spec's own file
header and `STATUS.md`, "3rdparty — remaining" for why the other ~50
non-blob drivers upstream ships are deliberately out of scope here.

Same `mock --install` pattern as `-libs`, extended: this SRPM's
`BuildRequires` need core's `-devel` **and** every one of `-libs`'s runtime
and `-devel` RPMs installed into the chroot first, since none of them are in
any repo either:

```bash
sg mock -c 'mock -r fedora-44-x86_64 --init'
CORE=~/mock-result-pcfix
LIBS=~/mock-result-3rdparty
sg mock -c "mock -r fedora-44-x86_64 --install \
    $CORE/indi-stable-core-2*.x86_64.rpm \
    $CORE/indi-stable-core-libs-2*.x86_64.rpm \
    $CORE/indi-stable-core-devel-2*.x86_64.rpm \
    $(ls $LIBS/indi-stable-3rdparty-libs-*-2*.x86_64.rpm | grep -v -e debuginfo -e debugsource | tr '\n' ' ')"
rpmbuild -bs core/rpm/indi-stable-3rdparty-drivers.spec
sg mock -c 'mock -r fedora-44-x86_64 --no-clean \
    --resultdir=~/mock-result-drivers \
    ~/rpmbuild/SRPMS/indi-stable-3rdparty-drivers-*.src.rpm'
```

**Watch for embedded newlines breaking the `--install` command** if you build
the RPM list with `$(ls ... )` inside a variable and interpolate it into an
already-double-quoted `sg -c "..."` string without collapsing newlines to
spaces first (`| tr '\n' ' '`, as above) — an earlier attempt at this omitted
that and `sg` executed each RPM path as its own separate shell command.

Installed and removed alongside core + `-libs` together, verified — see
`STATUS.md` for the coexistence results and the full list of what the six
real build failures found and how each was fixed. Read it before assuming a
clean `%build` on the next upstream tag bump means nothing changed; at least
one of those (the 47-entry `WITH_<X>=OFF` list) is a static list that a
future indi-3rdparty release could silently grow past.

The upgrade path is scripted too, and — unlike `-libs`'s own upgrade test —
run TOGETHER with `-libs`'s upgrade, not standalone, because `-drivers`
pins its `BuildRequires` to `-libs`'s exact `%{version}-%{release}` and the
two are always promoted together (DESIGN.md):

```bash
sudo bash scripts/test-upgrade-path-drivers.sh \
    <old-libs-dir> <new-libs-dir> <old-drivers-dir> <new-drivers-dir> [core-dir]
```

Needs FOUR genuinely-different-NVR directories, not two: a scratch
`Release: 2%{?dist}` build of `-libs` (same trick as its own upgrade test)
AND a matching scratch `Release: 2%{?dist}` build of `-drivers`, the latter
built in a chroot with the `-libs` Release-2 `-devel` RPMs installed —
building it against the repo's `Release: 1` `-libs` `-devel` RPMs would
violate `-drivers`'s own pinned `BuildRequires` and either fail to configure
or (worse) silently link against the wrong `-devel` headers. `STATUS.md`,
machine state, has both scratch builds' locations on `fedoraastro`.

## Testing `indi-stable-pyindi-client`

`pyindi-client/rpm/indi-stable-pyindi-client.spec` translates the
already-verified Debian packaging (`DEBIAN.md`, "Building and testing
`indi-stable-pyindi-client`") — same two decisions from `DESIGN.md`, same
`setup.cfg`/`setup.py` sed patches, same RPATH mechanism. `Source0` fetches
directly from PyPI, not GitHub, so `spectool` needs no tag:

```bash
spectool -g -R pyindi-client/rpm/indi-stable-pyindi-client.spec
```

Same `mock --install` pattern as `-libs`'s own `BuildRequires:
indi-stable-core-devel` — no repo to resolve it from:

```bash
sg mock -c 'mock -r fedora-44-x86_64 --init'
sg mock -c 'mock -r fedora-44-x86_64 --install \
    ~/mock-result-pcfix/indi-stable-core-2*.x86_64.rpm \
    ~/mock-result-pcfix/indi-stable-core-libs-2*.x86_64.rpm \
    ~/mock-result-pcfix/indi-stable-core-devel-2*.x86_64.rpm'
rpmbuild -bs pyindi-client/rpm/indi-stable-pyindi-client.spec
sg mock -c 'mock -r fedora-44-x86_64 --no-clean \
    --resultdir=~/mock-result-pyindi-client \
    ~/rpmbuild/SRPMS/indi-stable-pyindi-client-*.src.rpm'
```

**A failed build inside that last step wipes the `--install`ed core RPMs back
out of the chroot** (`cleanup_on_failure=True`, mock's default) — confirmed
2026-08-27 when a missing `gcc-c++` BuildRequires failed the first attempt.
Re-run the `--install` step before retrying, not just fix the spec and
re-run the build.

Only one binary RPM comes out — no `-devel`/`-libs` split, unlike core and
3rdparty: the package ships one compiled extension and no headers or link-time
artifact anything else builds against. `check-rpaths` fires `WARNING 0002` on
it the same way it does on every other RPATH-carrying binary here (same
downgrade, same reason — see core.spec's own `%install`). Verified installed
alongside core and Fedora's own distro `libindi`/`libindi-libs` (identical
`libindiclient.so.2` SONAME): `import PyIndi; PyIndi.BaseClient()` succeeds
and `ldd` resolves to `/opt/indi-stable/lib`, not the distribution's copy.
Full detail, including the `rpm -qp --provides`/`--requires` verification, is
in `STATUS.md`.

Coexistence and upgrade survival are scripted:

```bash
sudo bash scripts/test-pyindi-client-coexist-upgrade.sh \
    [pyindi-dir] [old-core-dir] [new-core-dir]
```

Defaults match `fedoraastro`'s machine state (`STATUS.md`). This package has
no scriptlets at all, so neither core's ordering-bug test nor 3rdparty's
orphaned-file test applies; what this one actually checks is narrower and
novel: with distro `libindi`/`libindi-libs` installed (identical SONAME),
does `import PyIndi` resolve into the private prefix on a fresh install, and
does it keep resolving correctly — to the genuinely upgraded file, not a
stale copy — after `indi-stable-core`/`-libs` are upgraded underneath an
already-installed, untouched pyindi-client. Needs a real `Release: 2%{?dist}`
scratch build of core built from the CURRENT spec (`STATUS.md`, machine
state has the location) — do not point it at `~/mock-result-rel2`, which
predates the `libindi.pc` fixes.

## Uninstall

Removal is as much of the coexistence guarantee as install: a `%postun` that
removed the wrong alternative, or a `--remove` whose name did not match the
`--install`, would strand a dangling `/usr/bin/indiserver-stable` pointing into
a deleted `/opt`.

```bash
sudo dnf remove -y indi-stable-core indi-stable-core-libs indi-stable-core-devel
rpm -V libindi; echo "exit=$?"                 # still 0
sha256sum /usr/bin/indiserver                  # must equal the pre-install hash
ls -l /usr/bin/indiserver-stable               # gone
ls -l /etc/alternatives/indiserver-stable      # gone
ls -l /var/lib/alternatives/indiserver-stable  # gone -- the ADMIN RECORD too
ls -d /opt/indi-stable                         # gone
ls /usr/lib/udev/rules.d/ | grep indi          # only the distro's 99-indi_auxiliary.rules
```

`/opt/indi-stable` disappearing entirely also confirms the `%dir` ownership
split — the private tree's top-level directories live in `-libs`, so nothing is
left unowned.

The admin record under `/var/lib/alternatives/` is the one to watch: its
survival is exactly what a name mismatch between `--install` and `--remove`
produces, and it is the failure the Debian `prerm` would have hit had its name
not been renamed alongside `postinst`. Check both sides together when touching
either.
