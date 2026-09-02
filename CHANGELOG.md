# Changelog

This project follows Semantic Versioning.

## [Unreleased]

### Added

- Define the `0.1.x` architecture, model/API, rendering, live-output, quality,
  and generated-output contracts in the implementation plan and specifications.
- Keep compiler binaries and caches under `build/`, including test builds.
- Add a documentation task that writes generated API output to `build/docs/`.
- Add build-policy regression coverage for artifact placement, ignored and
  packaged directories, dependency constraints, and documentation output.
- Require Nim 2.2.10 or newer, TerminalStyle 0.1.1 or newer, and TerminalScreen
  0.1.1 or newer.
