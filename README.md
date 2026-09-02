# TerminalStatus

TerminalStatus is a pure-Nim library under active development for terminal
spinners, single and multi-progress bars, and ordered task step-trackers. Phase
1 now provides the shared model contracts and validation foundation; component
models and rendering are still being implemented.

The `0.1.x` line requires Nim 2.2.10 or newer and builds on
`terminal_style >= 0.1.1` and `terminal_screen >= 0.1.1`. The normative design
and API contracts live in [`specs/`](specs/).

## Available API

Import `terminal_status/types` directly or use the `terminal_status` façade for
the currently implemented shared API:

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

## Development

Compiler products, caches, test executables, and generated documentation must
remain under `build/`. Hand-written source, tests, examples, and documentation
remain in their normal repository directories.

```sh
nimble check
nim c --path:src src/terminal_status.nim
nimble test
nimble docs
```

The documentation task writes generated API documentation and indexes to
`build/docs/`; it does not create the conventional `htmldocs/` directory.
