# Lessons learned

Gotchas that cost real time, written as rules rather than stories. **Everything
here is generic** — it would still be true on a project that had nothing to do
with INDI. Facts about INDI, RPM or `dpkg` live in `DESIGN.md`; per-platform
procedure lives in `FEDORA.md` / `DEBIAN.md`.

Two conventions:

- **Ordered by how likely each is to bite again**, not by when it was found.
- **Enforcement beats remembering.** Where a rule is already made structurally
  impossible to break, the entry says so and stays short — the enforcement is
  the real artifact. Full entries are reserved for what only judgment catches.

The standing rule the rest of this file serves, inherited from ACS:

> **Passing checks are not evidence the real path works, only that the checked
> paths are correct.** Every first-run in this line of work has surfaced exactly
> one thing nobody had exercised.

---

## 1. A check that passes by finding nothing must be shown able to find something

The single highest-value rule here. Five checklist steps in this project have
passed while testing nothing, and the packaging was fine every time — the
*checks* were wrong.

The worst case looked like this: a step ran `rpm -q --provides libindi-libs` on
a machine where that package was not installed. It printed an error to stderr,
nothing to stdout, the `comm` against it was trivially empty, and the step
reported success. It was written to protect the one machine configuration where
it could not work.

**Rule:** when a step passes by producing no output, add a positive control —
the same pipeline pointed at something that *must* produce output. If the
control is silent, the check is broken, not the subject.

*Enforced:* the harnesses in `scripts/` carry controls and print them as
`CONTROL:` lines. Evidence: `0888951`, `0e7a076`.

## 2. Read the artifact, not the log

A grep for `WARNING: 0002` found nothing, because the emitted text is
`WARNING 0002:` — the colon falls after the number. The check reported **zero**
RPATH warnings, which reads not as "fine" but as "the entire design has
collapsed," and sent an investigation the wrong way.

What settled it was reading the ELF headers of every shipped binary directly.
The log was a description of the artifact; the artifact was available.

**Rule:** when a log-derived count drives a conclusion, confirm it against the
thing itself at least once. A count that matches a file total (209 warnings,
209 ELF files) is trustworthy in a way a bare number never is.

The same rule covers greps written against imagined output. A step meant to
observe `dpkg`'s maintainer-script order searched the trace for phrases like
`old pre-removal`, which `dpkg` never emits, found nothing, and reported that
the trace was empty — while the trace sat in the log saying
`fork/exec /var/lib/dpkg/info/indi-stable-core.prerm ( upgrade 2.2.4.2-2 )`,
which was better evidence than the thing being looked for. **Run the tool once
and read what it actually prints before writing the pattern.**

*Not enforceable — judgment.* Evidence: `ff6b91f`.

## 3. Globs are wider than you think

Two instances, both cost a false alarm:

- `indi-stable-core-2*.rpm` also matches `…-2.2.4.2-1.fc44.**src**.rpm`.
  Harmless where source and binary packages live in separate directories,
  which is why it went unnoticed — and immediately wrong against a build tool
  that puts them in one directory.
- `indi-stable-core-libs-*.rpm` also matches the **debuginfo** subpackage,
  whose `Provides` legitimately contain the very soname the check greps for.

**Rule:** anchor globs on the distinguishing suffix (`*.x86_64.rpm`), not on a
prefix. Prefixes are shared by design; suffixes are what differ.

*Enforced:* all four scripts in `scripts/` are anchored. Evidence: `cc2b9fc`.

## 4. Under `sudo`, `~` is `/root`

A test script used `~/rpmbuild/...`. Run under `sudo` it resolved to
`/root/rpmbuild/...`, which does not exist. The install failed, **the exit
status was never checked**, and every subsequent step measured a machine that
had never been prepared. The run looked healthy end to end and proved nothing —
it was an observation of the distribution behaving normally.

**Rule:** absolute paths, never `~` or `$HOME`, in anything invoked through
`sudo`. Derive the real user's home from `getent passwd "${SUDO_USER:-$(id -un)}"`.

*Enforced:* every script in `scripts/` derives paths this way. Evidence: `8e0dfcb`.

## 5. Assert the setup happened before measuring it

The same incident as #4, but a distinct rule, because absolute paths alone would
not have caught it — anything can fail.

**Rule:** after a setup step, assert its effect and abort if absent. A test that
cannot distinguish "passed" from "never ran" is worse than no test, because it
produces confident output either way.

*Enforced:* the harnesses call `die()` on a failed precondition rather than
continuing. Evidence: `8e0dfcb`, `5d4f0b2`.

## 6. Restore by measuring what changed, not by naming it

The mirror of #5, and it bit on the very first run of the harness that carries
#5 correctly. The test installed the distribution's `-devel` package and ours,
then cleaned up with a removal list written in advance — the four package names
that had been reasoned about beforehand. The depsolver had pulled in **six**:
`libindi-devel` also brought `libindi-qt`, and ours brought `erfa`. Both
survived the cleanup, and the script printed *"box restored to the baseline"*
while two packages that had never been there sat installed.

Nothing failed. Every check passed, the exit status was 0, and the damage was
to a machine whose value is precisely that its state is known.

**Rule:** a teardown must remove what the run *observed itself* adding, not what
the author predicted it would add. Record the state before, diff it after, act
on the difference — then assert the difference is empty. A prediction cannot
keep up with a dependency solver, a later distro release, or a package that
grows a new `Requires`.

The corollary is the assertion, not just the removal: a cleanup that removes
things but never re-compares is a cleanup you are trusting rather than checking.

*Enforced:* `scripts/test-devel-coexist.sh` records `rpm -qa` at STEP 0, removes
the `comm -13` difference, and fails unless the final set matches the baseline
exactly.

## 7. A pipeline reports the last command's exit status

`somecmd -v 2>&1 | head -3` hid that `somecmd` exited **2**, because the
pipeline's status is `head`'s. `head -3` also truncated away the lines the step
existed to display, and `-v` turned out to be a *verbosity* flag rather than
`--version` — three compounding bugs in one line, in a check that had never
worked.

**Rule:** do not pipe a command into `head` when you care whether it succeeded.
Grep for what you actually want, and check the status of the thing you ran —
`set -o pipefail`, or `${PIPESTATUS[0]}`.

## 8. `readlink -f` prints paths for files that do not exist

`readlink -f /usr/bin/indiserver` printed `/usr/bin/indiserver` — which reads as
"resolves to itself" — for a file that was not there at all. `-f` resolves as
far as it can and does not require the final component to exist.

**Rule:** use `readlink -e` when the question is "does this resolve to a real
file". Keep `-f` only where a missing target is an acceptable answer.

*Evidence:* `913d760`.

## 9. `pkill -f` matches the calling shell's own argv

`pkill -f "indiserver -p 7626"` killed the test harness, because the shell
running the `pkill` had that exact string in its own command line. Exit 144,
log destroyed before it could be read. `pgrep -af` has the same hazard and will
appear to show a stray process that is really just the grep itself.

**Rule:** capture PIDs (`SRV=$!`) and kill those. If a pattern is unavoidable,
run it from a script file, where the pattern cannot appear in the caller's argv.

*Enforced:* `scripts/test-runtime-maps.sh` exists partly so the pattern lives in
a file. Evidence: `943eafa`.

## 10. Verify a tool's behaviour by running it, not by recalling it

`-v` as verbosity rather than version (#7); `readlink -f`'s tolerance of missing
files (#8); `dnf5`'s `keepcache=0` default; a linter's allowlist being hardcoded
rather than configurable. Every one of these was "obviously" something else
until it was run.

**Rule:** when a claim about an external tool is load-bearing, run the tool and
read the output. Where the tool is open source and the behaviour is surprising,
read its source — the `check-rpaths` allowlist question was settled in a few
minutes that way, and the answer changed the fix.

## 11. Do not use a version string as a discriminator

Two entirely different builds both reported `INDI Library: 2.2.4`, because the
upstream tag's fourth component is not part of the project version. A check
asking "which build actually answered?" could not tell them apart.

**Rule:** discriminate on identity, not on self-reported labels — a resolved
path, a `sha256sum`, the owning package. Ask the question that has a
file-system answer.

**The same trap in build artifacts: a higher version is not newer content.**
The `indi-stable-core_2.2.4.2-2` DEBs on the Debian build box carried a *bumped
revision of packaging that predated* the `libindi.pc` fixes — built earlier
than the `-1` set beside them, and numbered higher. Used as the "new" side of
an upgrade test they would have looked like a perfectly good upgrade while
quietly exercising a build nobody meant to test, and the harness would have
passed. Check the payload for the change you care about, not the version and
not the file date.

*Enforced:* `scripts/test-upgrade-path-deb.sh` and
`scripts/test-devel-compile-deb.sh` both read `libindi.pc` out of the `.deb`
and abort if the fix is not in it. Evidence: `4f52f10`.

## 12. A protection on one implementation is not evidence it exists on the other

Two packagings implemented the same guarantee by different mechanisms. Notes for
one read as though the guarantee were covered generally, and the other lacked it
for two builds.

**Rule:** when parallel implementations share a requirement, verify each
separately and say which one you checked. "The project does X" is not a claim
any single artifact can support.

**Read it the other way too: a RATIONALE does not transfer either.** The Fedora
`-dev` compile test runs inside a `mock` chroot, and the obvious port was
"`sbuild` or `pbuilder` takes the place of `mock`". But `mock` is not there to
supply a compiler — it is there because the Fedora VM's value is that it *has*
no compiler, and installing one would spend the snapshot. The Debian box builds
on the host and already carries the toolchain, so a chroot there would
reproduce a condition the box already satisfies. The workaround was portable;
the reason for it was not. Before porting a mechanism, port the *question* it
answered and check that the new machine still asks it.

## 13. Prefer the test that cannot be satisfied accidentally

A machine that already carried the dependency under test could never expose a
bug about that dependency being wrongly satisfied. The laptop passed for two
builds; a clean-slate VM failed immediately.

**Rule:** when choosing where to test, prefer the environment that has the least
pre-existing state. If a check matters most on a configuration you do not have,
that configuration is the one to build.

## 14. An error message names a cause and a consequence, not two blockers

Placed last deliberately, against the ordering convention: this bites exactly
once per machine and is then fixed permanently by a config change. It earns its
place because when it bites, it silently shapes how every later session is
planned.

`sudo` from a non-interactive session failed with:

```
sudo: a terminal is required to read the password; either use the -S option ...
```

That was written down as "sudo needs a real TTY and cannot be run from a Claude
Code session", and for several sessions every root step was treated as needing a
human at a terminal — harnesses were written to be handed over rather than run.

The message names its own cause and nobody read that far. Asking the tool
directly settles it in one command:

```
$ sudo -n -l
sudo: a password is required
```

`requiretty` was never set. The terminal was wanted *only* to prompt for the
password, so removing the password removes the need for the terminal.

**Rule:** when a failure message contains "to", "because", or a semicolon, the
clause after it is usually the actual condition. Test that condition on its own
(`sudo -n true`) rather than inferring the blocker from the sentence's first
half. This is #10 with a specific shape — the difference is that here the tool
told the truth up front and it was misread, rather than behaving surprisingly.

**The fix, on any machine where an agent session needs root:**

```bash
sudo visudo -f /etc/sudoers.d/<user>-claude     # visudo -f, never an editor
```
```
<user> ALL=(ALL) NOPASSWD: ALL
```

`visudo -f` syntax-checks before saving and sets the 0440 mode; a malformed
sudoers file locks out `sudo` entirely and needs console recovery. Confirm with
`sudo -n true; echo $?`.

Scope it by choosing the machine, not by narrowing the sudoers rule. `NOPASSWD:
ALL` means anything running as that user is root — right for a disposable VM
with a snapshot, wrong for a workstation. Restricting the rule to a script path
is theatre when the agent writes the script.

## 15. A stand-in check only covers what it can actually observe

`FEDORA.md` states plainly that the decisive `-devel` check "cannot be *it
compiles*" on that VM, because the box deliberately has no compiler, and
substitutes **`pkg-config` resolution** plus `rpm -qf` on the header. That
substitution is why two real defects in the same two lines of `libindi.pc`
survived a `-devel` cycle that was recorded as passing:

- `Libs:` carried no `-Wl,-rpath`, so a consumer linked and then died at
  startup with `libindiclient.so.2: cannot open shared object file`.
- `Cflags:` had lost `-I${includedir}`, so `#include <libindi/x.h>` silently
  resolved to the *distribution's* headers while linking our library.

Neither is visible to the stand-in. `pkg-config --variable=prefix libindi`
answers `/opt/indi-stable` in both the broken and the fixed case; so does
`--cflags`, whose output *is* the defect and looks perfectly reasonable. And
`rpm -qf` on "the header the compiler would find" was asked about the header
the *checker* expected, not the one the preprocessor actually opened —
`g++ -E -H` names that file and disagreed.

The substitution was not lazy. It was forced by a genuine property of the
machine, documented, and reasoned about. It was still blind to the thing it
stood in for.

**Rule:** when you replace a check with a cheaper stand-in, write down *what
the stand-in cannot see*, next to the stand-in. If the answer is "the actual
failure mode", the stand-in is not a weaker version of the check — it is a
different check that happens to pass. Ask what output the broken case would
produce, and confirm the stand-in's output differs from it.

This is #1 aimed one level up. #1 asks whether a check can detect *anything*;
this asks whether it can detect *the specific defect it exists for*.

*Evidence:* the defects `50c11d7` and `787da86` fix, both found on Debian by
compiling and running a consumer, after Fedora's stand-in had passed over them.

*Resolved 2026-08-25.* The tension was real but not a dilemma: the compiler does
not have to be on the box. A `mock` chroot has one already, and installing both
INDIs into it puts the real check within reach of a host that stays gcc-less —
`scripts/test-devel-compile-mock.sh`, about ten seconds warm. **When a check is
blocked by a property of the machine, look for a place to run it that is not the
machine**, before accepting a stand-in that cannot see the failure mode.

## 16. The failure mode of an omission depends on what else is installed

The missing `-Wl,-rpath` of #15 was recorded as "a consumer links and then dies
at startup with `libindiclient.so.2: cannot open shared object file`". That is
exactly what it does — on a box with no other copy of that SONAME. On a box that
*has* one, the same omission produces no error at all: the loader finds the
other copy, and the program runs against the wrong library while having compiled
against the right headers.

So the defect was loudest on the machine where it mattered least, and silent on
the machine the whole project exists to serve. A single observation of it
established the wrong mental model — a startup crash you would notice — and that
description then went into a commit message, a spec comment and this file before
anyone had seen it behave the other way.

**Rule:** an omission does not have one failure mode, it has one per
configuration. Before writing down "it fails with X", ask what the box you
measured on supplied that another box would not, and either name that condition
or measure the other configuration too. The dangerous case is rarely the one
that crashes.

*Evidence:* the same pre-fix `libindi.pc`, built in a Fedora `mock` chroot
carrying the distribution's `libindi-libs`: `ldd` resolves to
`/lib64/libindiclient.so.2` and the consumer exits 0. `36bfa2e` records the
measurement, `fef5fcc` corrects the spec comment that predicted the crash.

## 17. One unknown name in a batch: `apt` voids the batch, `dnf` voids the name

Both were measured, and they are **opposites** — which is the point of the
entry, because either one alone would teach the wrong general rule.

`apt-get remove a b c`, where `c` is neither installed nor in any repository,
exits with `E: Unable to locate package c` and removes **nothing** — not `a`,
not `b`. A teardown that named a package which had never been installed
therefore left the other two in place, and every check after it was measuring a
box that had not been cleaned. Nothing failed; the removal simply did not
happen.

What caught it was the measured diff of #6, which noticed two packages present
that the baseline did not have. The named list was wrong and the measurement
was right, which is #6 arriving somewhere its author had not expected.

`dnf5` does the reverse — checked on the Fedora build box, 2026-08-26, dnf5 5.4.3.0.
It prints `No packages to remove for argument: <name>` as a *warning*, resolves
and offers the rest of the transaction unchanged, and when the unknown name is
the only argument it prints `Nothing to do` and exits **0**. There is no
`--skip-unavailable` knob on `remove`; tolerating it is simply the behaviour.

So the two managers fail in mirror image. `apt` is loud and destroys the batch;
`dnf` is quiet and skips the name while reporting success. **Neither can be
caught by checking the exit status**, which is the part worth carrying: `apt`
returns non-zero having done nothing, `dnf` returns zero having done less than
asked.

**Rule:** build a batch's argument list from what you have *observed* to be
there, not from what you expect, and then **assert the effect** rather than the
status. A tool that refuses the whole transaction over one bad argument and a
tool that quietly drops the argument look identical from the outside — and both
look identical to success.

*Enforced:* the DEB harnesses derive the removal list from `dpkg-query` and
filter on installed state before naming anything.
`scripts/test-upgrade-path.sh` was the suspected instance on the RPM side and
turns out to be sound: it names `indi-stable-core-devel` unconditionally, which
`dnf` tolerates, and it follows the removal with `rpm -q … && die` — asserting
the effect, not the status. That is the shape to copy.

## 18. Two tools that both say "sorted" need not agree on what sorted means

GNU `comm` compares lines byte by byte. `sort` under a UTF-8 locale collates by
dictionary rules that ignore punctuation. So the ordinary-looking `sort` piped
into `comm` is wrong *by default*, and it fails in the worst available way: a
warning on stderr — `comm: file 1 is not in sorted order` — and a confidently
**wrong answer** on stdout. A teardown check reported two packages as left
behind that had in fact already been removed.

**Rule:** `LC_ALL=C` on every side of a sorted-set comparison, and read stderr.
More generally, when two tools are chained on a shared assumption about
ordering, encoding or escaping, the assumption belongs to *both* of them and
neither will announce a mismatch.

*Enforced:* every package snapshot in `scripts/` sorts with `LC_ALL=C`, and the
comparison itself now carries a positive control that plants a known difference
and requires it to be reported.

## 19. A path database answers about strings, not about files

`dpkg -S /usr/lib/udev/rules.d/99-indi_auxiliary.rules` reports
`no path found matching pattern` — for a file that is very much owned.
`indi-bin` records it as `/lib/udev/rules.d/99-indi_auxiliary.rules`, and on a
merged-`/usr` system `/lib` is a symlink to `usr/lib`, so both names are the
same inode (checked: `64770:1061708` either way). Query the recorded spelling
and the owner appears immediately.

The dangerous reading is the plausible one. "No package owns this file" is
exactly what a coexistence check wants to hear, and it would have been recorded
as a stray left behind by our own packages.

**Rule:** when an ownership or membership query comes back empty, confirm the
*key* before believing the answer — try the aliased spelling, and `stat` both
names and compare `device:inode` if it matters. A negative result from a lookup
is a statement about the lookup at least as much as about the thing.

## 20. A shared directory needs every occupant to claim it, not just one

Installing and removing `indi-stable-core` and `indi-stable-3rdparty-libs`
together for the first time (2026-08-26) left `/opt/indi-stable` and two of
its subdirectories behind as empty directories after a full `dnf remove` of
every package involved — despite `indi-stable-core-libs` (and, after a first
attempted fix, most of the 3rdparty vendor subpackages) explicitly declaring
`%dir` ownership of them.

The mechanism: when N independent packages all place files under one
directory but only some of them declare `%dir` ownership of it, RPM only
attempts `rmdir` on that directory when it erases an *owning* package, and
only succeeds if the directory happens to be empty at that exact moment in
the transaction's erasure order. Erasure order among packages with no
`Requires` relationship between them is not something the packager controls.
The first fix (adding `%dir` to the two directories most subpackages wrote
into) closed most of it, but one subtree (`share/indi/`, jointly written by
core's main package and one vendor subpackage, `sbig`) still leaked — because
the *other* writer into that same subtree still didn't own it, and core's
main package can never be the last package standing regardless (it `Requires`
core-libs, which forces it to erase first).

**Rule:** when several independently-erasable packages place files anywhere
under a shared directory, *every one of them* must declare `%dir` ownership
of that directory, not just the package that happens to "primarily" own it.
Coverage is binary, not majority-rules — one non-owning writer is enough to
make cleanup order-dependent. Verify by actually installing every package
that touches the shared tree together and removing them together in one
transaction; installing/removing subsets separately (which is how each
source package here had been tested until this session) cannot surface this
at all, because a single package's own removal is always trivially last for
its own directories.

## 21. Installing a `.src.rpm` file installs its `BuildRequires` as `Requires`

A `dnf install <resultdir>/indi-stable-3rdparty-libs-*.rpm` glob matched the
`.src.rpm` sitting in the same mock resultdir alongside the real binary RPMs.
`dnf`/`rpm` will happily "install" a source RPM as if it were an ordinary
package, and when it does, the spec's `BuildRequires` lines become that
package's `Requires` — so the transaction silently pulled in `gcc`, `gcc-c++`,
`cmake`, `make`, `ninja-build`, and about 35 more packages onto a Fedora VM
whose entire test value depends on it never having a toolchain installed
(STATUS.md, machine state). `dnf history undo` reversed the transaction
cleanly.

FEDORA.md already warns to anchor result-dir globs to `*.x86_64.rpm` for a
different reason (a resultdir holds the `.src.rpm` beside the binaries, and an
unanchored glob reports it as an "escaped" file in the coexistence checklist);
this is the same anchoring mistake, just caught by a different symptom.

**Rule:** never pass an unfiltered `*.rpm` glob from a resultdir to `dnf
install`/`rpm -i`. Anchor to `*.x86_64.rpm`, or explicitly exclude
`*.src.rpm`, every time — the failure mode when you don't isn't always an
obvious error; here `dnf` resolved it and reported success.

## 22. An unversioned SONAME makes the `.so` symlink a RUNTIME file

Packaging convention says the unversioned `libfoo.so` symlink belongs in
`-devel`/`-dev`: it is the link-time entry point, while the loader follows the
versioned SONAME (`libfoo.so.3`) at run time. That convention has an unstated
premise — that the SONAME *is* versioned.

Several prebuilt vendor blobs in `indi-3rdparty` violate that premise.
`libtoupcam.so.60`'s SONAME is `libtoupcam.so`. `libgxccd.so.0`'s is
`libgxccd.so`. The ZWO/ASI blobs carry no `SONAME` entry at all. When the
SONAME is the unversioned name, every binary linked against it records
`libtoupcam.so` in `DT_NEEDED`, so the loader needs that symlink at **run**
time — and shipping it in `-devel` leaves the driver unable to start on an
ordinary runtime-only install.

Concretely, and this went undetected through two coexistence passes and four
upgrade-path harnesses: 45 of 56 driver binaries could not load. `touptek`
33/33, `asi` 6/6, `micam` 6/6 — while `apogee`, `fli`, `playerone`, `sbig`,
`inovasdk` and `fishcamp`, whose blobs *do* carry versioned SONAMEs, were
completely fine.

It survived that long for a reason worth naming separately: every harness in
this project used `indi_apogee_ccd` as "a representative driver", and apogee
is one of the vendors the defect could not touch. The sample was not
representative of the thing that was broken. See also #1 — a check that only
ever exercises the working case passes for the same reason it is useless.

**Rule:** before deciding where a `.so` symlink goes, read the SONAME —
`readelf -d libfoo.so.N | grep SONAME`. If the SONAME is unversioned, or
absent, the symlink is a runtime file and belongs in the runtime package.
And when a package spans multiple independent vendors, test one binary from
**each** of them: a per-vendor fault is invisible to a single representative,
however carefully that representative was chosen.
