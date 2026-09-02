# Changelog

This project follows Semantic Versioning.

## [Unreleased]

### Added

- Add the side-effect-free `terminal_status/types` API with status/progress
  enums, the model error hierarchy, stable hashable task IDs, and detached
  progress and step snapshots.
- Add shared meaningful-text, numeric, index, spinner-frame, snapshot-copy,
  terminal-transition, and monotonic-duration helpers.
- Add deterministic shared-contract and façade-import tests plus focused
  shared-contract documentation.
- Define the `0.1.x` architecture, model/API, rendering, live-output, quality,
  and generated-output contracts in the implementation plan and specifications.
- Keep compiler binaries and caches under `build/`, including test builds.
- Add a documentation task that writes generated API output to `build/docs/`.
- Add build-policy regression coverage for artifact placement, ignored and
  packaged directories, dependency constraints, and documentation output.
- Require Nim 2.2.10 or newer, TerminalStyle 0.1.1 or newer, and TerminalScreen
  0.1.1 or newer.

### Removed

- Remove the generated `add` procedure, placeholder submodule, and scaffold
  test now that Phase 1 implementation has begun.
