# Development

This document describes how the drill repository is laid out, how to build and
test its images locally, and how a ConClear maintainer runs a release drill
against a candidate. The drill is the only external validation ConClear's
release procedure relies on; nothing here depends on another product.


## Table of contents<a id="toc"></a>

- [Prerequisites](#prerequisites)
- [Project structure](#project-structure)
- [Development standards](#development-standards)
  - [Markdown formatting and linting](#markdown-linting)
  - [Commit messages and scopes](#commit-scopes)
- [Building and testing locally](#building-testing)
- [Running a drill](#drill)
  - [Workspace and evidence](#drill-workspace)
  - [Registry resources](#drill-registry)
  - [Stages](#drill-stages)
  - [Negative cases](#negative-cases)
  - [Lifecycle fixture](#lifecycle-fixture)
  - [After the drill](#drill-cleanup)
- [Releases of the drill itself](#releases)


## Prerequisites<a id="prerequisites"></a>

- **Git**, rootless **Podman**, **Buildah**, **Skopeo**, **Trivy**, **Hadolint**
  and **Cosign** in the versions ConClear's
  [installation instructions](https://github.com/foundata/conclear#installation)
  list. The drill runs ConClear's tool checks first, so a wrong version shows
  up before anything is built.
- **[`uv`](https://docs.astral.sh/uv/)** to install the candidate wheel into a
  private environment, and `jq`.
- **arm64 emulation** (`qemu-user-static` with `binfmt_misc`) when the host is
  x86_64; every image declares both platforms and the drill qualifies both.
  The handler needs the `C` flag, otherwise set-user-ID binaries such as
  `sudo` run without their privileges under emulation and the escalation
  tests of the `service` image fail. Fedora registers `qemu-aarch64` with `F`
  only; override it once:

  ```sh
  sudo cp /usr/lib/binfmt.d/qemu-aarch64-static.conf /etc/binfmt.d/
  sudo sed -i 's/:F$/:FC/' /etc/binfmt.d/qemu-aarch64-static.conf
  sudo systemctl restart systemd-binfmt
  grep flags /proc/sys/fs/binfmt_misc/qemu-aarch64
  ```

- For the `systemd` image on SELinux hosts:
  `sudo setsebool -P container_manage_cgroup on`.


## Project structure<a id="project-structure"></a>

```text
Containerfile            service image (health command, sudo policy, example data)
Containerfile.systemd    systemd image with the drill unit
Containerfile.oneshot    one-shot image
Containerfile.helper     test-only helper that prepares test material
conclear.toml            all four images, tests, hooks, exceptions, version sources
scripts/, systemd/       entrypoints, health check, drill unit
hooks/                   repository hooks ConClear runs after the runtime tests
fixtures/                read-only test fixture mounted into the images
examples/                Dockerfile shipped as data to trigger a scanner exception
negative/<case>/         one deliberate defect per directory, see below
lifecycle/               single-image configuration for ConClear's lifecycle test
drill/                   the drill scripts and shared library
```


## Development standards<a id="development-standards"></a>

- **Scope**: The images exist to be observed by ConClear. Add a package,
  process or file only when a ConClear check or stage needs it, and say which
  one in a comment.
- **Base image**: Referenced by digest and updated through `conclear pins
  propose` and `conclear pins apply`, never by editing a digest by hand. The
  install layer also upgrades the base packages, because Debian publishes
  security updates more often than it rebuilds the slim image and a fixable
  vulnerability in the base rejects every qualification.
- **Set-ID bits**: Stripped in the same layer that installs packages. The
  `service` image keeps `sudo`, the `systemd` image keeps `su`; both are
  declared in `conclear.toml`, and the negative cases cover both failure modes.
- **Self-contained**: Every image builds from a clean checkout with the
  documented ConClear commands and no extra arguments or files.
- **Encoding, line ending**: UTF-8 with `LF` line endings, no BOM.


### Markdown formatting and linting<a id="markdown-linting"></a>

Documentation follows foundata's
[Markdown style guide](https://github.com/foundata/guidelines/blob/master/markdown-style-guide.md).
Use the `rumdl` invocation from its
[Linting and automatic formatting](https://github.com/foundata/guidelines/blob/master/markdown-style-guide.md#linting-and-automatic-formatting)
section; this repository has no local `rumdl` configuration.


### Commit messages and scopes<a id="commit-scopes"></a>

Commit messages follow the foundata guideline
([`guidelines/git-commits.md`](https://github.com/foundata/guidelines/blob/master/git-commits.md)):
`<scope>: <description>`, imperative, lowercase description, body only for
context the diff cannot preserve. Scopes in use:

|      Scope       | Area |
| ---------------- | ---- |
| `containerfile`  | The image builds: packages, scripts, units, workarounds |
| `conclear`       | `conclear.toml`, pinned digests, declarations, `lifecycle/` |
| `drill`          | `drill/` scripts, `negative/` cases, evidence schema |
| `repository`     | `README.md`, `DEVELOPMENT.md`, `.gitignore` and other repository-wide concerns |
| `licensing`      | `LICENSES/`, `REUSE.toml`, copyright and SPDX metadata |
| `style/markdown` | Pure formatting runs of the Markdown formatter |
| `release`        | Release preparation of the drill itself |


## Building and testing locally<a id="building-testing"></a>

The images are built and tested through ConClear only, so that what you test
is what a drill tests. From a committed revision:

```sh
conclear check --image service
conclear pins check --image service
run="$(conclear build --revision HEAD --image service --platform linux/amd64 --version 0.1.0 --format json | jq -r .data.runId)"
conclear test "${run}" --platform linux/amd64
conclear cleanup "${run}" --retire
```

`test` prints the observed footprint next to the declared limits; the limits in
`conclear.toml` are provisional until a drill has reported them. A full local
qualification without a registry:

```sh
conclear qualify --revision HEAD --image service --platform linux/amd64 --version 0.1.0
```

`qualify` compares `--version` with `CHANGELOG.md` and with a `v<version>` tag
at the revision, so a local qualification of `main` needs a matching heading and
tag; the drill scripts create both on a throwaway commit.


## Running a drill<a id="drill"></a>

A drill proves one ConClear candidate wheel. The scripts never touch this
checkout: they clone it into the workspace and add one drill-only commit that
points the images at the disposable repositories, adds the changelog heading for
the drill version and tags it.

```sh
wheel=/path/to/conclear-1.0.0-py3-none-any.whl
workspace="${HOME}/.local/share/conclear-drill/$(date -u +%Y%m%dT%H%M%SZ)"
drill/prepare.sh --wheel "${wheel}" --workspace "${workspace}"
drill/run.sh --workspace "${workspace}"
drill/verify.sh --workspace "${workspace}"
```

All scripts accept `--registry <namespace>` (default `quay.io/conclear-drill`)
and `--profile <name>` (default `drill`). `run.sh --local-only` runs the stages
that need no registry (identity, static checks, local qualification, negative
cases) and stops; that is the check to run before a registry exists or after a
change to the images.


### Workspace and evidence<a id="drill-workspace"></a>

```text
<workspace>/
  manifest.json      evidence index: candidate, registry resources, results, observations
  wheel-env/         environment installed from the candidate wheel only
  project/           throwaway clone with the drill-only commit and tag
  negative/<case>/   throwaway clones of the negative cases
  consumer/          XDG config, state and cache homes the drill CLI uses
  artifacts/ logs/   one JSON result and one stderr file per command
  archives/          release archives the drill wrote
  drill-version      counter; each prepare releases the next 0.1.N
```

Every stage records `passed` or `failed` with details in `manifest.json`.
Archive the index with the candidate's other release evidence; the workspace
itself may be deleted after `verify.sh` retired the runs.


### Registry resources<a id="drill-registry"></a>

The drill needs, once:

- A registry organisation (default `quay.io/conclear-drill`) with the
  repositories `drill-service`, `drill-systemd` and `drill-oneshot`.
- A robot account with admin permission on those repositories and an OAuth
  application token with repository administration scope, both stored as
  ConClear expects in a release profile named `drill` under
  `<workspace>/consumer/config/conclear/`, together with a disposable Cosign key
  pair (`drill-cosign.key`, `drill-cosign.pub`), its passphrase file and the
  robot's auth file (`drill-auth.json`).

Nothing in that organisation is meant to be consumed. `prepare.sh` does not
empty the repositories; run `conclear cleanup` on leftover runs and delete stray
tags with the registry API before a drill when a previous run was interrupted.


### Stages<a id="drill-stages"></a>

`run.sh` executes, in dependency order, and stops at the first failed stage:

1. Installed identity, `check` and `pins check` for every image.
2. Local qualification of `service`, `systemd` and `oneshot` on their declared
   platforms without a profile: build, runtime tests, footprint, set-ID
   inventory, sudo tests, hooks, scans, SBOM. Needs no registry. `systemd`
   declares amd64 only, see the comment in `conclear.toml`.
3. Part A: `release` of `service`.
4. Part B: the composable path on `systemd`: `qualify` and `transport export`
   per platform, then `assemble`, `provenance`, `publish`, `attest`, `verify`
   and `promote` as separate invocations.
5. Part C: `release` of `oneshot`, then every negative case.

`verify.sh` then reads every promoted index with `skopeo`, verifies signatures
and the SBOM and provenance attestations with `cosign` and the drill public key,
runs `archive verify` on every archive and one authoritative `rescan`, and
finally retires every run of the drill.


### Negative cases<a id="negative-cases"></a>

Each directory under `negative/` replaces its files in a fresh clone of the
drill commit and must be rejected by exactly the check named in its `expect`
file; `image` selects a different image than `service`.

|        Case         | Expected | Defect |
| ------------------- | -------- | ------ |
| `undeclared-pin`    | `CC0203` | The pinned base image has no `[[images.pins]]` declaration |
| `failing-health`    | `CC0403` | The health command always fails |
| `undeclared-setid`  | `CC0406` | Inherited set-ID helpers are not stripped |
| `stale-setid`       | `CC0406` | `su` is declared but its bit was stripped (`systemd` image) |
| `expired-exception` | `CC0503` | The configuration exception expired |
| `version-mismatch`  | `CC0005` | The changelog names another version than the release |

The `run-from-layout` hook of the positive path leaves a rootless container
store in its scratch directory on purpose; ConClear's removal of that store
through the container user namespace is part of every drill.


### Lifecycle fixture<a id="lifecycle-fixture"></a>

ConClear's repeat-release network test needs a fixture with exactly one release
image. `drill/lifecycle-fixture.sh --workspace <dir> --version <x.y.z>` clones
this repository, installs `lifecycle/conclear.toml`, adds the changelog heading
and tag for the version and prints the fixture path for the test's scenario
file.


### After the drill<a id="drill-cleanup"></a>

- Keep `manifest.json`, `artifacts/` and `archives/` with the candidate's
  release evidence.
- `verify.sh` retires every run; check `consumer/state/conclear/runs/` is empty.
- Delete the drill tags from the disposable repositories when they are no
  longer needed; they are never consumed.


## Releases of the drill itself<a id="releases"></a>

The drill repository is versioned like every foundata project: a Keep a
Changelog `CHANGELOG.md` and `v<version>` tags on `main`. Drill runs release
`0.1.N` from throwaway commits and never tag `main`; bump the version on `main`
only when the drill's own behaviour changes in a way worth naming.
