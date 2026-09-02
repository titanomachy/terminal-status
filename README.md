# TerminalStatus

TerminalStatus is a pure-Nim library under active development for terminal
spinners, single and multi-progress bars, and ordered task step-trackers. Phase
1 now provides the shared model contracts and a complete, time-derived Spinner
model. Progress, steps, pure rendering, and live output are still being
implemented.

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
ownership details.

## Modules

| Module | Available responsibility |
| --- | --- |
| `terminal_status` | Side-effect-free façade exporting implemented public modules. |
| `terminal_status/types` | Shared states, errors, IDs, snapshots, validation, transitions, and time helpers. |
| `terminal_status/spinners` | Validated presets and pure, time-derived spinner state. |

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
nimble c -r examples/spinner.nim
nimble docs
```

The documentation task writes generated API documentation and indexes to
`build/docs/`; it does not create the conventional `htmldocs/` directory.
