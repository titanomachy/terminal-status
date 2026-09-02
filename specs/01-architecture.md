# Architecture and boundaries

## Goals

TerminalStatus MUST provide:

- animated spinner models for work with unknown duration;
- determinate progress bars with counts, average rate, elapsed time, and ETA;
- indeterminate progress bars with a time-derived moving pulse;
- stable, insertion-ordered multi-progress task collections;
- ordered step-trackers with pending/running/terminal rows;
- pure, terminal-cell-aware string renderers;
- an exception-safe live region for ANSI terminals;
- useful redirected-output behavior with no animation-frame flood by default;
- Unicode defaults and an ASCII-only presentation option.

## Non-goals for `0.1.x`

The implementation MUST NOT include:

- a background animation thread;
- an asyncdispatch, Chronos, or other runtime adapter;
- execution of commands, processes, futures, or callbacks as “tasks”;
- raw keyboard input, cancellation key handling, or resize events;
- alternate-screen ownership;
- persistence, logging backends, telemetry, or network behavior;
- nested progress trees, arbitrary columns, tables, panels, or charts;
- global themes, global current displays, or import-time terminal detection.

Applications update the models while doing work and explicitly call the live
display's `update` operation. Spinner and indeterminate frames are selected by
monotonic timestamps, so a caller does not need to mutate them on every tick.

## Dependency direction

```text
terminal_status/types       std + terminal_style (text validation)
        ^
        +-- spinners        std/monotimes + terminal_style + types
        +-- progress        std/monotimes + options + types
        +-- steps           std/monotimes + types
        +-- themes          terminal_style + types
        +-- rendering       all models + themes + terminal_style
        +-- live            terminal_screen + terminal_style

terminal_status (façade) imports and exports the public modules above
```

Rules:

1. Component model modules MUST be usable without opening/querying a terminal.
2. Model modules MUST NOT import `rendering` or `live`.
3. TerminalStyle use inside model validation MUST remain pure and MUST NOT
   apply presentation styles; it is used only to validate visible text and
   spinner cell widths.
4. `rendering` MUST be pure: no stream writes, environment reads, terminal
   queries, sleeps, or mutation of a supplied model.
5. `live` MUST accept rendered string frames and MUST NOT import component model
   modules. This keeps the writer independently testable.
6. TerminalStyle is the only source of ANSI parsing, style values, display-cell
   measurement, and ANSI-aware truncation.
7. TerminalScreen is the only source of terminal capability detection and
   reusable cursor commands. TerminalStatus MAY define the private erase-line
   sequence `CSI 2 K`, because TerminalScreen `0.1.1` has no erase helper, but
   it MUST NOT publish a competing general cursor API.
8. No dependency may point from TerminalStyle or TerminalScreen back to
   TerminalStatus.

## Files and modules

The implementation SHOULD use exactly this layout unless a compiler limitation
requires a documented adjustment:

```text
src/
  terminal_status.nim
  terminal_status/
    types.nim
    spinners.nim
    progress.nim
    steps.nim
    themes.nim
    rendering.nim
    live.nim
```

The façade MUST import and export every public module. Importing either the
façade or a focused module MUST NOT print, flush, query a terminal, hide a
cursor, read environment variables, start a timer loop/thread, or mutate global
state.

Built-in presets SHOULD be returned by procedures rather than stored in
mutable exported global sequences. Compile-time immutable scalar constants are
allowed.

## Ownership and mutability

- Model values own their labels, preset frames, steps, and progress tasks.
- Internal sequences and counters MUST be private.
- Query procedures MAY return scalar values, strings by value, or snapshot
  objects by value. They MUST NOT expose a mutable alias into internal storage.
- `LiveDisplay` borrows its `File`; it MUST never close that file.
- A `LiveDisplay` has single-thread ownership. Concurrent calls are outside the
  contract and MUST be documented rather than hidden behind a global lock.
- No API stores a pointer/reference to a component model supplied by a caller.

## Time model

All correctness-sensitive time uses `std/monotimes.MonoTime`:

- public mutators that record time accept a final `now = getMonoTime()`
  parameter;
- pure renderers accept `now = getMonoTime()` and use that one value for the
  entire frame;
- elapsed durations clamp negative deltas to zero as defensive behavior;
- wall-clock `DateTime` and time zones MUST NOT affect animation, rate, or ETA;
- tests pass explicit `MonoTime` values and MUST NOT sleep to assert timing.

If Nim's exact default-argument syntax prevents direct `getMonoTime()` defaults,
provide a zero-argument convenience overload that calls the explicit-time
overload. Public semantics and test seams must remain the same.

## State and error policy

Invalid user values raise `ValueError`. Invalid component transitions raise
`StatusStateError`. An unknown multi-progress task ID raises
`UnknownTaskError`. No exported API uses `assert`/`doAssert` for runtime input
validation.

Terminal states are `statusSucceeded`, `statusFailed`, and `statusCancelled`.
Repeating the same terminal transition is an idempotent no-op. Trying to change
one terminal state to another raises `StatusStateError`. Mutating label/detail
text after termination is allowed so a caller can provide a final message;
mutating progress amounts, task order, or step position after termination is
not allowed.

## Text and terminal safety

User labels/details MAY contain normal Unicode, SGR styling, and OSC-8
hyperlinks. The renderer MUST:

- collapse CR, LF, CRLF, and tab boundaries to ordinary spaces;
- remove C0/C1 controls other than those comprising safe ANSI tokens;
- retain only SGR (`CSI ... m`) and well-formed OSC-8 hyperlink tokens;
- drop cursor movement, erase, title-setting, clipboard, and other terminal
  control sequences;
- measure and truncate the result in terminal cells;
- close active SGR and OSC-8 state after slicing/truncation.

Frames passed directly to `LiveDisplay` receive a stricter validation described
in `04-live-output.md`; the live layer must never interpret a carriage return in
frame content as a redraw instruction supplied by the caller.

## Graceful degradation

- Color is controlled by renderer options, independently of live ANSI cursor
  support.
- Unicode versus ASCII glyphs is controlled by renderer options.
- Live auto mode uses ANSI redraw only for an ANSI-capable terminal; otherwise
  it switches to plain mode.
- Plain mode strips all ANSI before writing.
- Terminal size lookup failure is not fatal. The live layer does not resize
  already-rendered frames; callers can pass an explicit width to renderers.

## Cross-package composition

TerminalStatus composes at a string boundary:

- TerminalLayout and TerminalTable can embed a finite rendered status string.
- TerminalWidgets may own models and call render/update from its event loop.
- TerminalPrompt may temporarily clear/close a live display before reading
  input, then create another display afterward.
- Applications that already own a TerminalScreen session may use
  `LiveDisplay` only when they also ensure exclusive ownership of its output
  rows. TerminalStatus itself never opens a raw-mode session.
