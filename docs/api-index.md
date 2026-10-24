.. title:: TerminalStatus documentation

TerminalStatus is a pure-Nim library for spinners, progress bars, and ordered
step trackers. Render a snapshot as an ordinary string, or explicitly send
frames to a live display as your application makes progress.

- [Complete API reference](terminal_status.html)
- [Search all exported symbols](theindex.html)
- [Guides](#guides) and [runnable examples](#examples)
- [Package README](https://github.com/titanomachy/terminal-status#readme)

.. image:: images/renderers.gif
   :alt: Spinners, progress bars, and step trackers rendered by TerminalStatus

## Install

Use Nim 2.0.0 or newer and install the package with Nimble:

```
nimble install terminal_status
```

Nimble also installs the TerminalStyle and TerminalScreen dependencies.
Most applications can import the complete API with `import terminal_status`.

## Quick start

Create a progress bar, record completed work, and render a snapshot:

```nim
import std/[monotimes, times]
import terminal_status

let started = getMonoTime()
var download = initProgressBar("Download", 100, "MB", started)

let now = started + initDuration(seconds = 2)
download.advance(50, now)

var options = defaultRenderOptions()
options.characters = statusAscii
options.useColor = false
options.barWidth = 10

echo download.render(options, now)
```

Save this as `download.nim` and run `nim r download.nim`. It prints:

```
> Download [#####-----]  50% 50/100 MB 25.0 MB/s ETA 2s
```

The model records work; `render` returns a string. Passing the same monotonic
timestamp to updates and rendering makes the frame and its metrics agree.
Rates are lifetime averages, and reaching the total automatically succeeds
the bar. See the [progress guide](https://github.com/titanomachy/terminal-status/blob/master/docs/progress.md)
for indeterminate work and multiple concurrent tasks.

For animation, call `display.update(model.render(...))` inside your own work
loop using [LiveDisplay](terminal_status/live.html). The
[live-status example](https://github.com/titanomachy/terminal-status/blob/master/examples/live_status.nim)
shows a finite refresh loop and exception-safe cleanup with `withLiveDisplay`.
The display borrows its stream and defaults to `stderr`; redirected output
emits the final frame by default. No background refresh thread is started.

## API reference

Use the [complete facade](terminal_status.html) for the whole API, or import
a focused module:

| Module | Use it for |
| --- | --- |
| [spinners](terminal_status/spinners.html) | Time-derived activity frames, presets, and success, failure, or cancellation |
| [progress](terminal_status/progress.html) | Determinate and indeterminate bars, rate and ETA, and ordered multi-progress tasks |
| [steps](terminal_status/steps.html) | Ordered workflows, current-step details, and terminal outcomes |
| [rendering](terminal_status/rendering.html) | Pure rendering, terminal-cell width limits, and safe caller text |
| [themes](terminal_status/themes.html) | Semantic styles, Unicode and ASCII characters, and marker presets |
| [live](terminal_status/live.html) | Explicit ANSI redraws, redirected output, and borrowed-stream lifecycle |
| [types](terminal_status/types.html) | Shared states, errors, task IDs, snapshots, and validation contracts |

Use the [symbol index](theindex.html) to look up a particular type or procedure.

## Guides

These focused guides are maintained alongside the source on GitHub:

- Models: [spinners](https://github.com/titanomachy/terminal-status/blob/master/docs/spinners.md),
  [progress and multi-progress](https://github.com/titanomachy/terminal-status/blob/master/docs/progress.md),
  and [step trackers](https://github.com/titanomachy/terminal-status/blob/master/docs/steps.md).
- Presentation: [pure rendering and width handling](https://github.com/titanomachy/terminal-status/blob/master/docs/rendering.md)
  and [themes and character presets](https://github.com/titanomachy/terminal-status/blob/master/docs/themes.md).
- Output: [live displays, redirection, and cleanup](https://github.com/titanomachy/terminal-status/blob/master/docs/live-output.md).
- Contracts: [shared types, ownership, and timing](https://github.com/titanomachy/terminal-status/blob/master/docs/shared-contracts.md)
  and [deterministic testing](https://github.com/titanomachy/terminal-status/blob/master/docs/testing.md).

## Examples

Clone the repository and run these finite examples from its root after
`nimble install --depsOnly -y`. Each source link opens the runnable Nim file
on GitHub.

| Example | Run from the repository root |
| --- | --- |
| [All component renderers](https://github.com/titanomachy/terminal-status/blob/master/examples/renderers.nim) | `nim r --path:src examples/renderers.nim --once` |
| [Spinner animation](https://github.com/titanomachy/terminal-status/blob/master/examples/spinner.nim) | `nim r --path:src examples/spinner.nim` |
| [Determinate progress](https://github.com/titanomachy/terminal-status/blob/master/examples/progress_bar.nim) | `nim r --path:src examples/progress_bar.nim --demo` |
| [Multiple tasks](https://github.com/titanomachy/terminal-status/blob/master/examples/multi_progress.nim) | `nim r --path:src examples/multi_progress.nim --demo` |
| [Ordered steps](https://github.com/titanomachy/terminal-status/blob/master/examples/step_tracker.nim) | `nim r --path:src examples/step_tracker.nim --demo` |
| [Live refresh and cleanup](https://github.com/titanomachy/terminal-status/blob/master/examples/live_status.nim) | `nim r --path:src examples/live_status.nim` |
| [Redirected final output](https://github.com/titanomachy/terminal-status/blob/master/examples/redirected_output.nim) | `nim r --path:src examples/redirected_output.nim` |
| [Themes and custom presets](https://github.com/titanomachy/terminal-status/blob/master/examples/customization.nim) | `nim r --path:src examples/customization.nim --once` |

See the [full example directory](https://github.com/titanomachy/terminal-status/tree/master/examples)
for focused imports, deterministic testing, validation, and suite composition.

## Generate locally

From a source checkout:

```
nimble docs
python3 -m http.server 8000 --directory build/docs
```

Open `http://localhost:8000` in your browser. Serving the documentation over
HTTP lets the generated API search load its index.
