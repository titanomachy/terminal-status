# Component models and public API

This document defines the target public model API. Object internals may differ,
but exported names and behavior MUST remain equivalent. All model operations are
in-memory and MUST perform no terminal I/O.

## Shared types (`terminal_status/types`)

```nim
type
  StatusState* = enum
    statusPending
    statusRunning
    statusSucceeded
    statusFailed
    statusCancelled

  ProgressMode* = enum
    progressDeterminate
    progressIndeterminate

  StatusError* = object of CatchableError
  StatusStateError* = object of StatusError
  UnknownTaskError* = object of StatusError
  TaskIdExhaustedError* = object of StatusError

  TaskId* = distinct uint64
```

Required helpers:

```nim
proc `$`*(id: TaskId): string
proc hash*(id: TaskId): Hash
proc isTerminal*(state: StatusState): bool
```

`$TaskId` returns the unsigned decimal value without a prefix. `TaskId` MUST
support `==` and hashing so it can be used in ordinary collections, even if the
first implementation uses a linear ordered sequence internally.

`isTerminal` returns true only for succeeded, failed, and cancelled.

## Common validation and transition rules

Model constructors and label setters MUST validate a “meaningful label”:

1. remove ANSI controls for validation purposes using TerminalStyle;
2. strip surrounding Unicode/ASCII whitespace supported by Nim;
3. raise `ValueError` if no visible text remains.

The original label is retained; final single-line/control normalization happens
in the renderer. Details and units MAY be empty. A non-empty unit follows the
same meaningful-text check.

For every terminal transition:

- running/pending to the requested terminal state succeeds and records `now`;
- requesting the already-current terminal state is an idempotent no-op and
  MUST preserve the original finish time;
- requesting a different terminal state raises `StatusStateError`;
- a model's elapsed duration freezes at its first terminal transition.

Elapsed time is `max(now - startedAt, zero)` while running, and
`max(finishedAt - startedAt, zero)` when terminal.

## Spinner styles and spinner model (`terminal_status/spinners`)

### Spinner style

```nim
type SpinnerStyle* = object # fields private

proc initSpinnerStyle*(
  frames: openArray[string],
  intervalMs: int,
  asciiFrames: openArray[string] = []
): SpinnerStyle

proc frames*(style: SpinnerStyle): seq[string]
proc asciiFrames*(style: SpinnerStyle): seq[string]
proc intervalMs*(style: SpinnerStyle): int

proc dotsSpinner*(): SpinnerStyle
proc lineSpinner*(): SpinnerStyle
proc arcSpinner*(): SpinnerStyle
proc pulseSpinner*(): SpinnerStyle
```

Constructor rules:

- `frames` MUST be non-empty;
- each frame MUST be non-empty, contain exactly one logical line, contain no
  ANSI/control tokens, and have positive `displayWidth`;
- all `frames` MUST have the same display width;
- if `asciiFrames` is empty, every primary frame MUST contain only printable
  ASCII and the constructor copies `frames` as the fallback;
- otherwise `asciiFrames` MUST contain the same number of entries, pass the
  same validation, contain printable ASCII only, and have a consistent width;
- primary and ASCII frame widths MAY differ;
- returned frame sequences are copies, never mutable aliases.

Built-in values are normative:

| Preset | Unicode frames | ASCII frames | Interval |
| --- | --- | --- | --- |
| dots | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` | `. o O @ * @ O o . +` | 80 ms |
| line | `─ \\ │ /` | `- \\ | /` | 100 ms |
| arc | `◜ ◠ ◝ ◞ ◡ ◟` | `- \\ | /` (repeat as necessary to six entries: `- \\ | / - \\`) | 100 ms |
| pulse | `· • ● •` | `. o O o` | 120 ms |

The table separates frames with spaces for readability; each listed glyph or
character is one frame. The backslash frame is the one-character string `"\\"`.

### Spinner

```nim
type Spinner* = object # fields private

proc initSpinner*(
  label: string,
  style = dotsSpinner(),
  now = getMonoTime()
): Spinner

proc label*(spinner: Spinner): string
proc state*(spinner: Spinner): StatusState
proc style*(spinner: Spinner): SpinnerStyle
proc startedAt*(spinner: Spinner): MonoTime
proc finishedAt*(spinner: Spinner): Option[MonoTime]
proc elapsed*(spinner: Spinner, now = getMonoTime()): Duration

proc setLabel*(spinner: var Spinner, label: string)
proc frameIndex*(spinner: Spinner, now = getMonoTime()): int
proc frame*(spinner: Spinner, asciiOnly = false,
            now = getMonoTime()): string
proc succeed*(spinner: var Spinner, now = getMonoTime())
proc fail*(spinner: var Spinner, now = getMonoTime())
proc cancel*(spinner: var Spinner, now = getMonoTime())
```

`initSpinner` starts in `statusRunning`. `frameIndex` is:

```text
floor(max(elapsedMilliseconds, 0) / intervalMs) mod frameCount
```

Terminal spinners stop animating: `frameIndex` uses `finishedAt` after the first
terminal transition. The renderer replaces the animated frame with a terminal
state marker, but `frame` itself still returns the frozen preset frame so the
procedure remains a query of the spinner preset rather than the theme.

`setLabel` is allowed in any state. Terminal transitions follow the common
rules above.

## Progress model (`terminal_status/progress`)

### Single progress bar

```nim
type ProgressBar* = object # fields private

proc initProgressBar*(
  label: string,
  total: int64,
  unit = "",
  now = getMonoTime()
): ProgressBar

proc initIndeterminateProgressBar*(
  label: string,
  unit = "",
  now = getMonoTime()
): ProgressBar

proc label*(bar: ProgressBar): string
proc unit*(bar: ProgressBar): string
proc mode*(bar: ProgressBar): ProgressMode
proc state*(bar: ProgressBar): StatusState
proc completed*(bar: ProgressBar): int64
proc total*(bar: ProgressBar): Option[int64]
proc startedAt*(bar: ProgressBar): MonoTime
proc finishedAt*(bar: ProgressBar): Option[MonoTime]
proc elapsed*(bar: ProgressBar, now = getMonoTime()): Duration
proc fraction*(bar: ProgressBar): Option[float]
proc ratePerSecond*(bar: ProgressBar,
                    now = getMonoTime()): Option[float]
proc eta*(bar: ProgressBar, now = getMonoTime()): Option[Duration]

proc setLabel*(bar: var ProgressBar, label: string)
proc setUnit*(bar: var ProgressBar, unit: string)
proc advance*(bar: var ProgressBar, amount: int64 = 1,
              now = getMonoTime())
proc setCompleted*(bar: var ProgressBar, value: int64,
                   now = getMonoTime())
proc complete*(bar: var ProgressBar, now = getMonoTime())
proc fail*(bar: var ProgressBar, now = getMonoTime())
proc cancel*(bar: var ProgressBar, now = getMonoTime())
```

Constructor behavior:

- determinate `total` MUST be greater than zero;
- both constructors start in `statusRunning` with `completed == 0`;
- determinate `total()` returns `some(total)`; indeterminate returns `none`;
- `fraction()` returns `some(completed.float / total.float)` for determinate
  progress and `none` for indeterminate progress.

Determinate mutation:

- `amount` MUST be non-negative;
- `advance` MUST detect both integer overflow and completion beyond `total`
  before mutating; either raises `ValueError`;
- `setCompleted` accepts only `completed <= value <= total`; a decrease or an
  excess raises `ValueError`;
- reaching exactly `total` automatically transitions to `statusSucceeded` and
  records the supplied `now`;
- `complete` sets `completed = total` and succeeds atomically;
- mutating completion after any terminal state raises `StatusStateError`, even
  if the supplied amount is zero or the value is unchanged.

Indeterminate mutation:

- `advance` and `setCompleted` raise `StatusStateError` because an
  indeterminate bar has no numeric completion;
- `complete` succeeds without changing `completed` from zero;
- `fail` and `cancel` work for either mode.

Label and unit setters remain available after termination. Units are descriptive
only and do not change calculations.

Metrics:

- `ratePerSecond` is available only for determinate progress when
  `completed > 0` and elapsed nanoseconds are positive;
- it is the lifetime average `completed.float / elapsedSeconds`, not a rolling
  window;
- `eta` is available only for a running determinate bar with a positive rate
  and `completed < total`;
- ETA is `(total - completed).float / rate`, converted to a non-negative
  `Duration` with nearest-millisecond precision;
- terminal or indeterminate progress returns `none` for ETA;
- no rate/ETA calculation may divide by zero or produce NaN/infinity.

### Multi-progress

```nim
type
  ProgressTaskSnapshot* = object
    id*: TaskId
    label*: string
    unit*: string
    mode*: ProgressMode
    state*: StatusState
    completed*: int64
    total*: Option[int64]
    startedAt*: MonoTime
    finishedAt*: Option[MonoTime]

  MultiProgress* = object # fields private

proc initMultiProgress*(): MultiProgress
proc len*(multi: MultiProgress): int
proc isEmpty*(multi: MultiProgress): bool
proc taskIds*(multi: MultiProgress): seq[TaskId]
proc tasks*(multi: MultiProgress): seq[ProgressTaskSnapshot]
proc task*(multi: MultiProgress, id: TaskId): ProgressTaskSnapshot

proc addTask*(multi: var MultiProgress, label: string, total: int64,
              unit = "", now = getMonoTime()): TaskId
proc addIndeterminateTask*(multi: var MultiProgress, label: string,
                           unit = "", now = getMonoTime()): TaskId
proc removeTask*(multi: var MultiProgress, id: TaskId)
proc setLabel*(multi: var MultiProgress, id: TaskId, label: string)
proc setUnit*(multi: var MultiProgress, id: TaskId, unit: string)
proc advance*(multi: var MultiProgress, id: TaskId, amount: int64 = 1,
              now = getMonoTime())
proc setCompleted*(multi: var MultiProgress, id: TaskId, value: int64,
                   now = getMonoTime())
proc complete*(multi: var MultiProgress, id: TaskId,
               now = getMonoTime())
proc fail*(multi: var MultiProgress, id: TaskId,
           now = getMonoTime())
proc cancel*(multi: var MultiProgress, id: TaskId,
             now = getMonoTime())
```

Multi-progress rules:

- task IDs start at `TaskId(1)`, increase by one, and are never reused after
  removal;
- ID exhaustion raises `TaskIdExhaustedError` before inserting a duplicate; it
  must never wrap silently;
- `tasks()` and `taskIds()` preserve insertion order and return copies;
- all ID-targeted operations raise `UnknownTaskError` without mutation when the
  ID is absent;
- per-task validation and transition semantics are exactly those of
  `ProgressBar`;
- removing a task is allowed regardless of that task's state;
- a `MultiProgress` has no terminal aggregate state: callers MAY add tasks
  after every previous task has finished;
- the implementation SHOULD delegate mutations to the single-bar logic rather
  than duplicate transition rules.

The snapshot type is intentionally a value. Rendering code can derive elapsed,
rate, and ETA from its timestamps using shared private helpers; callers cannot
use a snapshot to mutate the collection.

## Step tracker (`terminal_status/steps`)

```nim
type
  StepSnapshot* = object
    label*: string
    detail*: string
    state*: StatusState
    startedAt*: Option[MonoTime]
    finishedAt*: Option[MonoTime]

  StepTracker* = object # fields private

proc initStepTracker*(
  labels: openArray[string],
  title = ""
): StepTracker

proc title*(tracker: StepTracker): string
proc state*(tracker: StepTracker): StatusState
proc len*(tracker: StepTracker): int
proc currentIndex*(tracker: StepTracker): Option[int]
proc steps*(tracker: StepTracker): seq[StepSnapshot]
proc step*(tracker: StepTracker, index: int): StepSnapshot
proc elapsed*(tracker: StepTracker,
              now = getMonoTime()): Duration

proc setTitle*(tracker: var StepTracker, title: string)
proc setCurrentDetail*(tracker: var StepTracker, detail: string)
proc start*(tracker: var StepTracker, now = getMonoTime())
proc advance*(tracker: var StepTracker, now = getMonoTime())
proc failCurrent*(tracker: var StepTracker, detail = "",
                  now = getMonoTime())
proc cancel*(tracker: var StepTracker, now = getMonoTime())
```

Construction:

- `labels` MUST contain at least one item and every label must be meaningful;
- title MAY be empty; a non-empty title must be meaningful;
- every step and the tracker begin in `statusPending` with no timestamps;
- `currentIndex()` is `none` before start.

Transitions:

| Operation/current state | Result |
| --- | --- |
| `start` / pending | Tracker and step 0 become running; both record `now`. |
| `start` / running | Idempotent no-op; current step and timestamps stay unchanged. |
| `start` / terminal | Same terminal state is not expressible; raise `StatusStateError`. |
| `advance` / running, not last | Current step succeeds; next step starts at the same `now`; index increments. |
| `advance` / running, last | Current step and tracker succeed at `now`; current index remains the last index. |
| `advance` / pending or terminal | Raise `StatusStateError`. |
| `failCurrent` / running | Current step and tracker fail at `now`; later steps stay pending. |
| `failCurrent` / already failed | Idempotent; if a non-empty detail is supplied, update the failed step detail, but preserve timestamps. |
| `failCurrent` / other state | Raise `StatusStateError`. |
| `cancel` / pending | Tracker and every step become cancelled at `now`; current index stays `none`. |
| `cancel` / running | Tracker, current step, and all later pending steps become cancelled at `now`; earlier succeeded steps remain succeeded. |
| `cancel` / cancelled | Idempotent no-op. |
| `cancel` / succeeded or failed | Raise `StatusStateError`. |

`setCurrentDetail` requires a current step (running or terminal) and raises
`StatusStateError` before start/cancel-before-start. It is allowed after success,
failure, or cancellation to provide a final detail. `step(index)` raises
`ValueError` for a negative or out-of-range index. `steps()` returns a copy.
`setTitle` is allowed in every state and applies the normal optional-title
validation.

`elapsed` is zero before start, uses the tracker's start time while running,
and freezes at the tracker's finish time in a terminal state.

## Overloads and façade behavior

The same verb names (`setLabel`, `advance`, `complete`, `fail`, `cancel`) are
intentional Nim overloads. Avoid aliases with competing semantics.

The façade module `terminal_status.nim` MUST re-export all model types and
procedures. It MUST NOT retain the scaffold `add` procedure or export the
placeholder `Submodule` type once implementation begins.
