# Shared contracts

`terminal_status/types` is the side-effect-free foundation for every status
component. It provides lifecycle and progress enums, the catchable error
hierarchy, stable `TaskId` values, detached snapshot types, and reusable
validation, transition, copying, and monotonic-duration helpers.

Import either the focused module or the package façade:

```nim
import terminal_status/types
# or: import terminal_status

let taskId = TaskId(42)
doAssert $taskId == "42"
doAssert statusSucceeded.isTerminal
```

Two finite examples cover the core shared surface without terminal I/O or
sleeping:

- [`examples/shared_types.nim`](../examples/shared_types.nim) demonstrates
  lifecycle states, hashable task IDs, detached snapshots, transitions, and
  monotonic elapsed time.
- [`examples/validation.nim`](../examples/validation.nim) demonstrates valid
  text, numeric, index, sequence, and frame inputs as well as catching rejected
  input through `ValueError`.

Run them from the repository root:

```sh
nimble c -r examples/shared_types.nim
nimble c -r examples/validation.nim
```

## Validation

Labels are meaningful when text remains visible after complete ANSI controls
are removed and surrounding Unicode whitespace is stripped. The original
string is never rewritten by validation; renderer normalization is a later,
separate concern. Optional titles and units may be exactly empty, but non-empty
values follow the same visible-text rule.

`validateFrameWidths` checks the common spinner-frame invariants using
TerminalStyle display-cell widths. Numeric and index guards raise `ValueError`
rather than assertions, making invalid caller input catchable in every build
mode.

```nim
import terminal_status/types

requireMeaningfulText("\e[32mReady\e[0m")
requireMeaningfulOrEmptyText("", "unit")
requirePositive(100, "intervalMs")
requireNonNegative(0'i64, "completed")
requireValidIndex(1, 3)
requireSameLength(4, 4, "spinner frame sets")

doAssert validateFrameWidths(["界", "好"]) == 2

try:
  requireMeaningfulText("\e[31m\e[0m")
except ValueError:
  discard # ANSI controls alone contain no visible label.
```

## State and time

`transitionToTerminal` accepts pending or running states, records the supplied
monotonic timestamp, and treats repetition of the same terminal transition as
an idempotent no-op. Attempting to replace one terminal result with another
raises `StatusStateError`.

`clampedDuration` and `elapsedDuration` defensively clamp backwards timestamps
to zero. Supplying a finish time freezes elapsed time at that first terminal
timestamp. Tests pass explicit `MonoTime` values and never sleep.

```nim
import std/[monotimes, options, times]
import terminal_status/types

let started = getMonoTime()
let completedAt = started + initDuration(milliseconds = 250)
var
  state = statusRunning
  finishedAt = none(MonoTime)

transitionToTerminal(state, finishedAt, statusSucceeded, completedAt)
transitionToTerminal(state, finishedAt, statusSucceeded,
  completedAt + initDuration(seconds = 1))

doAssert finishedAt == some(completedAt)
doAssert elapsedDuration(started, finishedAt,
  completedAt + initDuration(seconds = 2)).inMilliseconds == 250
```

## Ownership

`ProgressTaskSnapshot` and `StepSnapshot` are detached values. Collection
models use `copyValues` when returning sequences so callers receive fresh
sequence storage and cannot reorder or replace internal entries.

```nim
import std/[monotimes, options]
import terminal_status/types

let started = getMonoTime()
let original = ProgressTaskSnapshot(
  id: TaskId(42),
  label: "Download packages",
  unit: "packages",
  mode: progressDeterminate,
  state: statusRunning,
  completed: 3,
  total: some(10'i64),
  startedAt: started,
  finishedAt: none(MonoTime)
)

var detached = copyValues([original])
detached[0].label = "Changed snapshot"
doAssert original.label == "Download packages"
```
