# Live output strategies

`terminal_status/live` turns complete rendered strings into either an ANSI
redraw region or plain log output. A `LiveDisplay` borrows its `File`: opening,
updating, or closing a display never closes the stream. Construction performs
no I/O or capability detection.

## Selecting a mode

`liveAuto` is the default. `open` asks TerminalScreen whether the configured
output supports ANSI exactly once, then selects `liveAnsi` or `livePlain`.
Use a forced mode when the application already knows the stream contract or
needs deterministic output in a test:

```nim
import terminal_status

var options = defaultLiveDisplayOptions(stdout)
options.mode = livePlain

withLiveDisplay display, options:
  display.update("starting")
  display.update("finished")
```

The default borrowed stream is `stderr`, leaving `stdout` available for a
program's primary data. Importing the module and calling
`initLiveDisplay` remain side-effect free; auto detection occurs only in
`open`.

## Redirected output

ANSI cursor movement cannot redraw a file or pipe. The default
`plainFinalOnly` policy therefore validates and caches each update, strips
safe SGR and OSC-8 controls, and writes only the latest non-empty frame at
close. Each logical row, including the last, receives a newline. This prevents
a fast spinner from flooding logs with transient animation frames.

Set `plainPolicy = plainEveryChange` for a progress log. It writes each changed
visible frame immediately, still strips ANSI, and suppresses duplicates after
stripping. Changing only a color does not create another log entry. An empty
frame updates the snapshot but writes no row.

```nim
var options = defaultLiveDisplayOptions(stdout)
options.mode = livePlain
options.plainPolicy = plainEveryChange
```

The finite [`live_output.nim`](../examples/live_output.nim) example uses auto
mode by default and accepts `--every-change` to show the opt-in log policy.

## Ownership and lifecycle

A display is single-use and has one owning thread. Call `open`, submit complete
frames with `update`, then call `close`; `withLiveDisplay` performs the close
from a `finally` block during normal return or Nim exception unwinding. It does
not handle process termination, signals, defects, or `SIGKILL`.

Do not let another writer modify the display's terminal rows while it is open.
TerminalStatus does not enter raw mode, create a TerminalScreen session, query
terminal geometry, or run a background refresh loop. Applications choose
renderer widths and schedule their own refreshes.
