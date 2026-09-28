# AGENTS.md - Rules for AI coding assistants working in this repository

PortareOS is a personal fork of ROCKNIX for one device, the Retroid Pocket
Nova (SM8550). It has diverged from upstream deliberately and does not merge
from it; upstream package updates come in selectively, through
`tools/import-upstream-packages`. Rules inherited from upstream that assume a
shared multi-device tree do not apply here.

---

## 1. Verify by running, not by reading

Most of what breaks here is invisible to inspection and obvious the moment
something is executed.

* **DO** build, run or execute what you changed. Compile the package, run the
  script, apply the patch, execute the checker against real input.
* **DO** test a check by making it fail on purpose, then confirming it passes
  after the fix. A check nobody has seen fail is not known to work.
* **DO NOT** trust a regex to prove its own correctness. `\bROCKNIX\b` does not
  match `-DROCKNIX` or `ROCKNIX_BACKUP`, because `D` and `_` are word
  characters. If the same pattern does the edit and the verification, it will
  report success on what it just missed.
* **DO** clean up after verifying. Running `py_compile` to check a script left
  a `__pycache__` directory that broke the install.

## 2. Reading a build failure

* **DO** read the tail of `output.log` first. The thread log named in the
  build summary is usually the job that was terminated as collateral, not the
  one that failed.
* **DO NOT** guess at a cause when the log is available. Get the log.

## 3. Renaming and interfaces

Several strings that look like branding are contracts with something outside
this tree.

* **DO NOT** rename: `SCREENSCRAPER_SOFTNAME`, which ScreenScraper registers
  per distribution; the device name a driver reports, which retroarch and ES
  match their input configs against; upstream `PKG_URL` and `PKG_SITE` values;
  `DISTRO_MIRROR`; copyright, SPDX and patch authorship lines.
* **DO** check what a renamed value is derived from elsewhere. A `PKG_URL`
  interpolating `${PKG_NAME}`, a `PKG_SOURCE_NAME` defaulting from it, a
  hardcoded `TARGET` in an upstream Makefile, and a `-D` build flag naming an
  upstream CMake option all follow a package name silently when it changes.
* **DO** run `.github/scripts/check-package-deps.py` after touching packages.

## 4. Directory structure and package policy

* **DO** put new work in `projects/PortareOS/packages` (project-wide) or
  `projects/PortareOS/devices/SM8550/packages` (device-specific).
* **DO** remove dead upstream packages from the top-level `packages/` tree.
  Reducing the maintenance surface of the fork is the point; upstream's rule
  against touching that tree does not apply to a fork that owns it.
* **DO** isolate device-specific runtime behaviour in quirk files.
* **DO** take upstream package updates with `tools/import-upstream-packages`,
  not by rebasing or cherry-picking. It maps their paths onto ours, skips
  packages we have removed, and imports content verbatim so the ROCKNIX
  copyright headers and `PKG_URL`/`PKG_SITE` lines survive. Conflicts are
  where we renamed something they also changed, and want a human.

## 5. Kernel

* **DO** prefer quirks and config over patches.
* **DO NOT** write kernel modules without upstream references or an existing
  example to follow.
* **DO** assert any kernel option the build depends on in
  `distributions/PortareOS/kernel_options`. Kconfig drops a symbol whose
  dependencies are unmet without printing anything, so an option can vanish
  from a config refresh and look like a routine diff.

## 6. Commits and pull requests

* **DO** keep commit messages short. Say what changed and why in a few lines.
* **DO NOT** write conversational narrative or repetitive summaries in pull
  request descriptions.
* **DO NOT** add obvious or redundant inline comments. Comment the surprising
  thing, not the visible one.
* **DO** group changes sharing one purpose into a single pull request rather
  than splitting them.
* **DO** open pull requests with `gh pr create`. This repository is a GitHub
  fork of `ROCKNIX/distribution`, so the web UI offers ROCKNIX as the base
  and it has to be changed by hand every time; `gh repo set-default
  portare-ch/portareos` is set, and `gh` then targets this repository.
* **DO NOT** remove the `upstream` remote to stop that. It is where
  `tools/import-upstream-packages` reads from (`--to` defaults to
  `upstream/next`), and it is not what picks the base repository. Leaving
  the fork network on GitHub is what would, and it is permanent and takes
  the issues and pull requests with it - the numbers this tree cites for
  why things are the way they are, #211 and #217 among them. It was
  considered and declined.
