# Changelog

This project follows Semantic Versioning.

## [Unreleased]

### Added

- Add Phase 2 semantic status themes built from `TerminalStyle`, with cyan,
  green, red, yellow, and subdued default roles and no global presentation
  state.
- Add cell-equivalent Unicode and printable-ASCII marker and progress-bar
  presets, plus the explicit `RenderOptions` foundation for per-call character,
  color, width, metadata, pulse, and theme choices.
- Export themes and render options from the façade, document their API, cover
  exact presets and TerminalStyle's color-disable path with focused tests, and
  add a finite customization example.
- Add pure determinate and indeterminate progress models with checked monotonic
  updates, atomic completion, frozen elapsed time, lifetime rates, and ETA.
- Add insertion-ordered multi-progress collections with stable non-reused task
  IDs, delegated task mutation, unknown-ID errors, and detached snapshots.
- Add the ordered step-tracker state machine with explicit start/advance,
  mutable details, failure, cancellation, and frozen monotonic timing.
- Export the complete Phase 1 model API from the side-effect-free façade and
  cover it with deterministic focused tests that perform no terminal I/O.
- Add finite progress, indeterminate, multi-progress, and step-tracker examples
  plus hand-written model guides and README usage examples.
- Add the pure `terminal_status/spinners` API with validated custom styles,
  Unicode/ASCII frame sets, and normative dots, line, arc, and pulse presets.
- Add monotonic time-derived frame selection, mutable validated labels, and
  idempotent success, failure, and cancellation transitions with frozen
  elapsed time and frames.
- Export spinners from the side-effect-free façade and cover preset values,
  validation, copying, exact timing boundaries, ASCII fallback, and state
  transitions with deterministic tests.
- Add a finite spinner example, a hand-written spinner API guide, and a
  reproducible README animation with its source asciicast.
- Add finite shared-type and validation examples, with runnable links and
  expanded usage snippets in the README and shared-contract guide.
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
- Add a documentation task that writes façade and focused-module API output
  plus its generated index to `build/docs/`.
- Add build-policy regression coverage for artifact placement, ignored and
  packaged directories, dependency constraints, and documentation output.
- Require Nim 2.2.10 or newer, TerminalStyle 0.1.1 or newer, and TerminalScreen
  0.1.1 or newer.

### Removed

- Remove the generated `add` procedure, placeholder submodule, and scaffold
  test now that Phase 1 implementation has begun.
