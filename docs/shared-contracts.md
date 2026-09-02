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

## State and time

`transitionToTerminal` accepts pending or running states, records the supplied
monotonic timestamp, and treats repetition of the same terminal transition as
an idempotent no-op. Attempting to replace one terminal result with another
raises `StatusStateError`.

`clampedDuration` and `elapsedDuration` defensively clamp backwards timestamps
to zero. Supplying a finish time freezes elapsed time at that first terminal
timestamp. Tests pass explicit `MonoTime` values and never sleep.

## Ownership

`ProgressTaskSnapshot` and `StepSnapshot` are detached values. Collection
models use `copyValues` when returning sequences so callers receive fresh
sequence storage and cannot reorder or replace internal entries.
