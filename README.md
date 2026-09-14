# OCI Images: ConClear Drill

Synthetic container images whose only purpose is to exercise
[ConClear](https://foundata.com/en/projects/conclear/), foundata's release
tool for OCI images. A drill rehearses the complete release procedure against a
disposable registry: every profile ConClear supports, the composable
multi-worker path, interruption and resume, cleanup, independent verification,
and a set of deliberate negative cases that a real project must never carry.

The images are **not for production use**. They exist so that a ConClear
release candidate can be proven without depending on any real product's
release cadence, registry or credentials.



<!-- rumdl-disable MD033 -->
<!-- HTML for consistent rendering across limited platform parsers -->
<div align="center" id="project-readme-header">
<br>
<br>

**⭐ Found this useful? Support open-source and star this project:**

[![GitHub repository](https://img.shields.io/github/stars/foundata/oci-conclear-drill.svg)](https://github.com/foundata/oci-conclear-drill)

<br>
</div>
<!-- rumdl-enable MD033 -->

## Table of contents<a id="toc"></a>

- [Images](#images)
- [What a drill proves](#coverage)
- [Running a drill](#usage)
- [Non-goals / Limitations](#limitations)
- [Development](#development)
- [Contributing](#contributing)
- [Licensing, copyright](#licensing-copyright)
  - [Container configuration, repository](#licensing-copyright-project)
  - [Container images](#licensing-copyright-image)
  - [Trademarks](#trademarks)
- [Author information](#author-information)



## Images<a id="images"></a>

All images build from `docker.io/library/debian:13-slim` for `linux/amd64` and
`linux/arm64`.

|   Image   |  Profile   | Purpose |
| --------- | ---------- | ------- |
| `service` | `service`  | Long-running process with a health command, generated test material, functional sudo tests, hooks and a configuration exception |
| `systemd` | `systemd`  | `systemd` as PID 1 with one required drill unit and one declared set-ID executable |
| `oneshot` | `one-shot` | Processes a mounted fixture and exits |
| `helper`  | test-only  | Preparation step of `service`: derives one secret and one public file; never released |

Released images land in `quay.io/conclear-drill/drill-<image>` and carry
throwaway versions. Nothing in that registry is meant to be consumed.



## What a drill proves<a id="coverage"></a>

The positive path covers, per image and platform: static checks, pin
observation, build, runtime qualification with readiness, health, signal and
shutdown expectations, resource footprint, the set-ID inventory, the sudo
escalation tests, test fixtures with secret and public outputs produced by a
test-image dependency, repository hooks including one that leaves a rootless
container store behind, vulnerability, secret and configuration scans with a
declared exception, SBOM generation, publication, attestation, verification,
promotion, candidate cleanup, archives and rescans. The composable path runs
`qualify` and `transport export` per worker, then `assemble`, `provenance`,
`publish`, `attest`, `verify` and `promote` as separate invocations.

The negative cases under [`negative/`](negative/) each carry exactly one
defect and must be rejected by exactly the expected check. See
[`DEVELOPMENT.md`](DEVELOPMENT.md#negative-cases) for the list.



## Running a drill<a id="usage"></a>

A ConClear maintainer runs a drill against a release candidate wheel as step
7 of ConClear's release procedure. The scripts never touch this checkout: they
clone it into the workspace and add one drill-only commit that points the
images at the disposable repositories, adds the changelog heading for the drill
version and tags it.

```sh
drill/prepare.sh --wheel "${wheel}" --workspace "${workspace}"
drill/run.sh --workspace "${workspace}"
drill/verify.sh --workspace "${workspace}"
```

`run.sh` executes these stages in order and stops at the first failure:

1. Installed identity, `check` and `pins check` for every image.
2. Local qualification of `service`, `systemd` and `oneshot` on both platforms
   without a registry.
3. `release` of `service`.
4. The composable path on `systemd`: `qualify` and `transport export` per
   platform, then `assemble`, `provenance`, `publish`, `attest`, `verify` and
   `promote` as separate invocations.
5. `release` of `oneshot`, then every negative case.

`verify.sh` reads every promoted index, verifies signatures and attestations
with the drill public key, verifies every archive, runs one authoritative
rescan and retires the drill's runs. ConClear's own repeat-release network test
gets its single-image fixture from `drill/lifecycle-fixture.sh`.

Every run leaves one evidence index (`manifest.json`) in the workspace that
names the candidate, the disposable registry resources, every stage result and
every observation. That file belongs with the candidate's release evidence.
[`DEVELOPMENT.md`](DEVELOPMENT.md) describes the workspace, the registry
resources, the negative cases and the cleanup.



## Non-goals / Limitations<a id="limitations"></a>

- The images do nothing useful. Their processes exist to be observed by
  ConClear.
- They are not hardened, minimal or fast; they are deliberately ordinary so
  that ordinary defects show up.
- The registry organisation, its robot account and the signing key are
  disposable and may be emptied or rotated at any time.
- Only Podman is supported as the container runtime.



## Development<a id="development"></a>

[`DEVELOPMENT.md`](DEVELOPMENT.md) describes the repository layout, how to build
and test the images locally, the drill procedure and the negative cases.
[`CHANGELOG.md`](CHANGELOG.md) documents what changed between releases of the
drill itself.


## Contributing<a id="contributing"></a>

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contribution workflow and
[`DEVELOPMENT.md`](DEVELOPMENT.md) for local builds, tests and drills.


## Licensing, copyright<a id="licensing-copyright"></a>

### Container configuration, repository<a id="licensing-copyright-project"></a>

<!--REUSE-IgnoreStart-->
<!-- rumdl-disable-next-line MD034 --><!-- should match SPDX-PackageSupplier -->
Copyright (c) 2026 foundata GmbH (https://foundata.com)

This project is licensed under the GNU General Public License v3.0 or later
(SPDX-License-Identifier: `GPL-3.0-or-later`), see
[`LICENSES/GPL-3.0-or-later.txt`](LICENSES/GPL-3.0-or-later.txt) for the full
text.

The [`REUSE.toml`](REUSE.toml) file provides detailed licensing and copyright
information in a human- and machine-readable format. This includes parts that
may be subject to different licensing or usage terms, such as third-party
components. The repository conforms to the
[REUSE specification](https://reuse.software/spec/). You can use
[`reuse spdx`](https://reuse.readthedocs.io/en/latest/readme.html#cli) to create
a
[SPDX software bill of materials (SBOM)](https://en.wikipedia.org/wiki/Software_Package_Data_Exchange).
<!--REUSE-IgnoreEnd-->

[![REUSE status](https://api.reuse.software/badge/github.com/foundata/oci-conclear-drill)](https://api.reuse.software/info/github.com/foundata/oci-conclear-drill)



### Container images<a id="licensing-copyright-image"></a>

An image built from this repository bundles various software components along
with direct and indirect dependencies, which are subject to their respective
licenses. When using it, **you are responsible for ensuring that your usage
complies with all relevant licenses** for the software contained within the
image.

For further licensing information about the software contained in an image built
from this repository, please refer to the following resources:

- <https://www.debian.org/legal/licenses/>



### Trademarks<a id="trademarks"></a>

- Red Hat® and Quay® are trademarks of Red Hat, Inc., registered in the US and
  other countries
- Debian® is a registered trademark of Software in the Public Interest, Inc.
- Docker® is a trademark of Docker, Inc.
- Linux® is a registered trademark of Linus Torvalds

Their use here is purely descriptive and does not imply any affiliation with or
endorsement by the trademark holders.


## Author information<a id="author-information"></a>

This [project](https://foundata.com/en/projects/) was created and is maintained
by [foundata](https://foundata.com/).
