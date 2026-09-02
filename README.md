# TerminalStatus

TerminalStatus is a pure-Nim library under active development for terminal
spinners, single and multi-progress bars, and ordered task step-trackers. Phase
1 provides the complete, side-effect-free component model layer. Pure
rendering and live output are the next implementation phases.

The `0.1.x` line requires Nim 2.2.10 or newer and builds on
`terminal_style >= 0.1.1` and `terminal_screen >= 0.1.1`. The normative design
and API contracts live in [`specs/`](specs/).

![A finite TerminalStatus arc-spinner demo](docs/images/spinner.gif)

[Download the source asciicast](docs/recordings/spinner.cast) or run the
finite [`examples/spinner.nim`](examples/spinner.nim) demo locally.

## Spinner

Import the façade, choose a built-in preset, and sample frames whenever your
application refreshes its display:

```nim
import std/[monotimes, times]
import terminal_status

let started = getMonoTime()
var spinner = initSpinner("Indexing files", arcSpinner(), started)

# Frame selection is pure and deterministic; no background timer is started.
let later = started + initDuration(milliseconds = 200)
doAssert spinner.frame(now = later) == "◝"

spinner.setLabel("Index complete")
spinner.succeed(later)
doAssert spinner.state == statusSucceeded
doAssert spinner.elapsed(later).inMilliseconds == 200
```

`dotsSpinner`, `lineSpinner`, `arcSpinner`, and `pulseSpinner` include both
Unicode frames and printable-ASCII fallbacks. Pass `asciiOnly = true` to
`frame` for the fallback. `initSpinnerStyle` validates custom frame widths,
controls, fallback counts, and positive intervals.

Animation is derived from monotonic elapsed time; callers explicitly sample
and refresh it. Terminal transitions freeze elapsed time and frame selection.
Repeating the same success, failure, or cancellation is harmless, while
switching terminal outcomes raises `StatusStateError`. See the
[Spinner model guide](docs/spinners.md) for presets, customization, ownership,
and transition behavior.

## Progress

Determinate progress checks every numeric update before mutation and
automatically succeeds when it reaches the exact total:

```nim
import std/[monotimes, options, times]
import terminal_status

let started = getMonoTime()
var download = initProgressBar("Download", 10, "files", started)

download.advance(4, started + initDuration(seconds = 2))
doAssert download.fraction.get == 0.4
doAssert download.ratePerSecond(
  started + initDuration(seconds = 2)).get == 2.0
doAssert download.eta(
  started + initDuration(seconds = 2)).get.inSeconds == 3

download.complete(started + initDuration(seconds = 5))
```

Rates are lifetime averages based on monotonic elapsed time. ETA is available
only for running determinate work with a positive rate and is rounded to the
nearest millisecond. Terminal elapsed time and rate freeze at the first finish
timestamp, and terminal ETA is absent.

`initIndeterminateProgressBar` represents work without a total. Its future
renderer derives pulse motion from the stored start timestamp, so it needs no
per-frame model mutation. See the [Progress models guide](docs/progress.md) and
the finite [`progress_bar.nim`](examples/progress_bar.nim) and
[`indeterminate_bar.nim`](examples/indeterminate_bar.nim) examples.

## Multi-progress

`MultiProgress` keeps insertion order and assigns IDs that are never reused:

```nim
var work = initMultiProgress()
let
  compileId = work.addTask("Compile", 12, "modules")
  uploadId = work.addIndeterminateTask("Upload")

work.advance(compileId, 3)
work.complete(uploadId)
doAssert work.taskIds == @[compileId, uploadId]
```

All mutations by ID reject unknown tasks without changing the collection.
Snapshot queries return detached values and fresh sequence storage. The finite
[`multi_progress.nim`](examples/multi_progress.nim) example demonstrates task
mutation, removal, and non-reused IDs.

## Steps

```nim
var release = initStepTracker(["Build", "Test", "Publish"], "Release")
release.start()
release.setCurrentDetail("release mode")
release.advance()
```

Advancing succeeds the current step and starts the next; advancing the last
step succeeds the tracker. Failure affects the current step while leaving later
steps pending. Cancellation preserves earlier successful steps. See the
[Step tracker guide](docs/steps.md) and finite
[`step_tracker.nim`](examples/step_tracker.nim) example.

## Shared contracts

Import `terminal_status/types` directly or use the `terminal_status` façade for
the shared API:

```nim
import terminal_status

let taskId = TaskId(42)
doAssert $taskId == "42"
doAssert statusSucceeded.isTerminal
```

The shared module includes lifecycle and progress states, catchable model
errors, task IDs, detached progress/step snapshots, meaningful-text and numeric
validation, finite terminal transitions, and clamped monotonic-duration
helpers. See [Shared contracts](docs/shared-contracts.md) for behavior and
ownership details. The finite [`shared_types.nim`](examples/shared_types.nim)
and [`validation.nim`](examples/validation.nim) examples show those contracts
and their failure handling as runnable programs.

## Modules

| Module | Available responsibility |
| --- | --- |
| `terminal_status` | Side-effect-free façade exporting implemented public modules. |
| `terminal_status/types` | Shared states, errors, IDs, snapshots, validation, transitions, and time helpers. |
| `terminal_status/spinners` | Validated presets and pure, time-derived spinner state. |
| `terminal_status/progress` | Determinate/indeterminate progress metrics and ordered multi-progress tasks. |
| `terminal_status/steps` | Ordered step state, details, failure, and cancellation. |

TerminalStatus uses TerminalStyle for ANSI-aware validation and terminal-cell
measurement. The finite demo uses TerminalScreen for terminal detection and
cursor ownership. Library model modules never query or write to a terminal.

## Development

Compiler products, caches, test executables, and generated documentation must
remain under `build/`. Hand-written source, tests, examples, and documentation
remain in their normal repository directories.

```sh
nimble check
nim c --path:src src/terminal_status.nim
nimble test
nimble c -r examples/shared_types.nim
nimble c -r examples/validation.nim
nimble c -r examples/spinner.nim
nimble c -r examples/progress_bar.nim
nimble c -r examples/indeterminate_bar.nim
nimble c -r examples/multi_progress.nim
nimble c -r examples/step_tracker.nim
nimble docs
```

The documentation task writes generated API documentation and indexes to
`build/docs/`; it does not create the conventional `htmldocs/` directory.
