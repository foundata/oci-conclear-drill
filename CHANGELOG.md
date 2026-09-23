# Changelog

All notable, user-facing changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Drill runs release throwaway versions such as `0.1.7` from a drill-only commit
that adds the matching heading; those headings never land on `main`.


## [Unreleased]

### Added

- The `java` image: one Maven artifact and no Java runtime, so ConClear's Java
  database check (`CC0507`) has a subject in every drill. While upstream's Java
  database has expired, its qualification, release and rescan must reject first
  and pass with `--accept-stale-java-database` second. Needs the repository
  `drill-java` in the drill registry.


## [0.1.0] - 2026-09-15

### Added

- All functionality and files.

[unreleased]: https://github.com/foundata/oci-conclear-drill/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/foundata/oci-conclear-drill/releases/tag/v0.1.0
