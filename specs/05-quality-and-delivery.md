# Quality, documentation, and delivery specification

This document scopes the implementation work to be performed after the current
planning/configuration change. The current change MUST NOT create the library
implementation, tests, examples, README rewrite, or generated API docs.

## Required test organization

Use focused modules whose names start with `test_` so Nimble discovers them
predictably:

```text
tests/
  config.nims
  fixtures.nim
  test_types.nim
  test_spinners.nim
  test_progress.nim
  test_multi_progress.nim
  test_steps.nim
  test_rendering.nim
  test_live_output.nim
  test_imports.nim
  test_suite_integration.nim
  test_build_policy.nim
```

The implementation model MAY combine tiny test files, but it must retain every
coverage category and keep terminal I/O tests isolated from the developer's
real terminal.

Use `std/unittest`. Tests MUST be deterministic, cross-platform where the
public behavior is cross-platform, and runnable without `--threads:on`.

## Time fixtures

Create test helpers that derive explicit `MonoTime` values from a common base,
for example a base value plus `initDuration(milliseconds = ...)`. Use exact
timestamps for initialization, mutation, and rendering.

Correctness tests MUST NOT call `sleep`, spin on the clock, depend on CPU speed,
or assert a range from real elapsed time. A finite manual demo MAY sleep because
it demonstrates animation rather than verifies behavior.

## Model test matrix

### Shared types

- every `StatusState.isTerminal` result;
- decimal TaskId formatting, equality, and hashing;
- error inheritance is catchable as `StatusError` where specified;
- invalid values raise exceptions rather than assertions/defects.

### Spinner styles and spinners

- reject empty frames, empty frame sets, multiline/control-bearing frames,
  zero-width frames, inconsistent widths, non-ASCII fallback frames, fallback
  count mismatch, and non-positive intervals;
- getters return copies of frame sequences;
- built-in frames, fallback frames, widths, and intervals match the spec;
- frame index at boundary values: 0, interval-1, interval, a full cycle, and a
  negative defensive delta;
- ASCII and Unicode selection;
- label validation/setter;
- running to success/failure/cancel;
- same transition idempotency and different terminal-transition rejection;
- elapsed/frame freeze at the first finish timestamp.

### Determinate progress

- reject zero/negative total and meaningless labels/units;
- initial mode/state/count/fraction/timestamps;
- zero and positive advance; monotonic set; exact automatic completion;
- reject negative advance, overflow, beyond-total advance, decrease, and
  beyond-total set without partial mutation;
- explicit complete, fail, and cancel;
- reject numeric mutations after terminal state;
- allow final label/unit changes;
- zero elapsed or zero completion produces no rate/ETA;
- exact average rates and ETA with injected timestamps;
- ETA disappears in terminal state and elapsed freezes;
- no NaN/infinity for extreme legal values.

### Indeterminate progress

- initial mode/state and absent total/fraction/rate/ETA;
- reject numeric mutations;
- complete/fail/cancel and timestamp idempotency;
- label/unit mutation behavior.

### Multi-progress

- empty state and rendering;
- IDs begin at one, remain increasing, and are not reused after removal;
- insertion order in both query methods;
- snapshots do not mutate source storage;
- every delegated per-task operation and error path;
- unknown-ID calls never mutate the collection;
- determinate and indeterminate tasks may coexist;
- new tasks may be added after all prior tasks terminate;
- overflow behavior can be tested through an internal test seam if direct
  iteration to `uint64.high` is impossible.

### Step tracker

- reject empty steps and meaningless labels/title;
- initial pending states and absent current index;
- start/idempotent start;
- advance through every step and succeed on last;
- fail current with/without detail; later steps stay pending;
- cancel before start and during work;
- repeat-same/different terminal transitions;
- detail mutation requirements before/after terminal states;
- invalid indexes;
- snapshot copy behavior and elapsed-time freeze.

## Renderer test matrix

Golden assertions MUST compare exact plain strings for representative cases and
structural invariants for combinatorial cases.

### Exact forms

- every semantic marker in Unicode and ASCII modes;
- every built-in spinner at known time offsets;
- spinner terminal rows;
- determinate 0%, a fractional value, 99%, and 100%;
- count with and without unit;
- rate and ETA presence/absence;
- elapsed/rate/duration boundary formatting at 0s, 59s, 60s, 3599s, and 3600s;
- indeterminate pulse at start, far edge, return edge, and a one-cell bar;
- succeeded/failed/cancelled indeterminate rows;
- multi-progress insertion order and lack of final newline;
- step title, empty title, empty/non-empty detail, all states, and running pulse.

### Width and Unicode

- `width == 0` is unbounded;
- every positive width from 1 through at least 80 satisfies the per-line
  display-width bound for every component;
- long ASCII, CJK, combining-mark, emoji, flag, and ZWJ labels;
- suffix selection (`…` versus `...`) and very narrow suffix behavior;
- metadata removal order, bar shrinking/removal, percent removal, and label
  truncation match `03-rendering.md`;
- wide glyphs are never split and no renderer pads to maximum width.

### ANSI and hostile controls

- safe nested SGR and OSC-8 survive with color enabled and close correctly;
- disabling color removes theme and caller ANSI;
- cursor movement, erase, terminal-title OSC, clipboard OSC, two-byte escapes,
  carriage returns, tabs, and newlines cannot escape a component row;
- malformed/incomplete escape input remains visible safe text or replacement
  text but is never executed as terminal control;
- styling does not change visible display width.

### Purity

- repeat rendering with identical model/options/time is byte-identical;
- rendering does not change model state, timestamps, task order, or snapshots;
- façade import produces no output and no terminal side effect.

## Live output tests

Do not exercise the developer terminal. Write to a temporary file or a test
stream abstraction. If Nim's `File` API makes in-memory capture impractical,
use a unique file beneath `build/test-tmp/` and remove it after the test.

Cover byte-exact behavior for:

- new/open/closed state queries and invalid transitions;
- forced ANSI and forced plain mode without capability detection;
- auto mode through an injectable/private capability seam or process-isolated
  redirected-file test;
- first one-row and multi-row writes;
- duplicate suppression;
- same-height replacement;
- new frame taller and shorter than previous frame;
- replacement with an empty frame;
- keep and clear close policies;
- optional hide/show cursor ownership;
- `flushWrites` branches where observable;
- plain final-only, every-change, duplicates, empty final, and clear behavior;
- plain mode strips safe ANSI;
- every invalid frame class is rejected before output/cache mutation;
- double open, update before open, update after close, double close;
- scoped cleanup after a deliberate `CatchableError`;
- borrowed stream remains usable after close;
- simulated write/flush failure where a safe deterministic seam is available.

Expected cursor bytes SHOULD be built with TerminalScreen helpers. Never assert
OS-specific terminal detection results in a unit test without controlling the
stream/environment.

## Suite integration tests

Compile against sibling sources in the suite workspace when available:

- TerminalStyle styles inside labels render with correct widths;
- TerminalScreen capability/cursor functions are used without raw-mode entry;
- a finite progress rendering embeds in a TerminalLayout panel;
- a terminal status string embeds in a TerminalTable cell;
- importing TerminalStatus does not require TerminalLayout/Table/Graph/Prompt/
  Widgets.

The first two are release requirements. Layout/Table composition tests are
development-only sibling checks and MUST NOT add runtime package dependencies.

## Memory managers and platforms

The release check MUST run the full unit suite under the default memory manager
and SHOULD also run ARC and ORC. At minimum, CI covers Linux; the suite SHOULD
also cover macOS and Windows because TerminalScreen is cross-platform.

No test assumes `/dev/tty`, ANSI support in CI, a particular `$TERM`, or POSIX
path separators unless guarded as a platform-specific integration test.

## Examples to implement later

All examples are finite or have a documented finite duration:

```text
examples/
  spinner.nim
  progress_bar.nim
  indeterminate_bar.nim
  multi_progress.nim
  step_tracker.nim
  live_status.nim
  customization.nim
  redirected_output.nim
```

Requirements:

- each component has one smallest-useful example;
- `live_status.nim` shows explicit refresh in a work loop and scoped cleanup;
- `customization.nim` shows ASCII mode and a custom theme/preset;
- `redirected_output.nim` documents final-only output;
- finite examples may use short sleeps for visual pacing but MUST terminate;
- example compilation must put all generated products under `build/`.

## README and hand-written documentation to implement later

Replace the scaffold README only during the implementation/documentation phase.
It must cover:

- product scope and suite position;
- installation and version requirements;
- smallest spinner, determinate progress, multi-progress, and step examples;
- the explicit-refresh/no-background-thread design;
- Unicode/ASCII and color controls;
- rate/ETA semantics;
- ANSI terminal versus redirected-output behavior;
- why output defaults to `stderr`;
- exception-safe cleanup and cursor-ownership caveat;
- module map and TerminalStyle/TerminalScreen dependencies;
- commands for tests, examples, docs, and release checks;
- generated documentation location under `build/docs/`.

Every exported symbol MUST have a Nim doc comment at its definition. Comments
describe invariants, exceptions, side effects, time semantics, ownership, and
whether returned sequences are copies. Avoid comments that only restate a name.

Generate public Nim API docs for the façade/project and focused modules that do
not appear in the project output. Add a hand-written API index only if Nim's
generated index cannot expose the module map clearly. Generated HTML is never
committed and always goes to `build/docs/`.

## Future Nimble task contract

When implementation work begins, add tasks with these names:

- `compilePackage`: compile the façade;
- `test`: run all unit tests;
- `testArc` and `testOrc`: repeat with those memory managers;
- `examples`: compile/check every finite example;
- `suiteIntegration`: development-only sibling package checks;
- `docs`: generate docs under `build/docs/`;
- `releaseCheck`: run Nimble validation, compilation, tests, examples, and docs.

Tasks MUST use the repository configuration in `06-build-policy.md`; any
explicit output path must also be under `build/`. The docs task SHOULD use
`--skipParentCfg:on --outdir:build/docs` if required to avoid Nim's `dochack`
helper conflict while still honoring the destination policy.

## Definition of done for implementation

The library is ready for a `0.1.x` release only when:

- all public behavior in specs 01–04 exists and is tested;
- no placeholder scaffold API/file remains;
- `nimble check` and every release task succeeds;
- imports are side-effect free;
- generated products exist only under `build/`;
- no correctness test sleeps or touches the developer terminal;
- API docs cover every export and generate beneath `build/docs/`;
- README/examples accurately match the implemented public API;
- required dependencies point only to TerminalStyle and TerminalScreen;
- `git status --ignored` reveals no untracked compiler/doc artifacts outside
  `build/`.

