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
mode by default. It also demonstrates `--every-change`, forced `--ansi`,
`--clear`, and display-owned `--hide-cursor` behavior.

## ANSI redraw and finalization

ANSI mode owns only the rows written by its latest frame. The first frame is
written directly with logical LF separators converted to CRLF. A changed frame
returns to the first owned row, erases every previously owned row, returns to
that first row, and writes the replacement. Consequently, shorter text and
frames with fewer rows cannot leave stale content, and rows outside the owned
region are untouched. Byte-identical updates perform no write or flush; an
empty update clears the current region and owns no rows.

`finishKeep` retains a non-empty ANSI frame and writes one CRLF so later output
starts below it. `finishClear` erases the owned rows without adding a newline.
Both policies write nothing when no frame is owned. Plain final-only output
uses the same policy intent: keep emits the cached snapshot and clear
suppresses it, while already-written every-change log entries cannot be
retracted.

Cursor hiding is opt-in. When `hideCursor` is true and ANSI mode is selected,
the display records ownership only after writing the hide command and writes
exactly one show command during `close`. It never shows a cursor it did not
hide. Close is idempotent, flushes finalization and cursor restoration together
when configured, and leaves the borrowed `File` open.

## Ownership and lifecycle

A display is single-use and has one owning thread. Call `open`, submit complete
frames with `update`, then call `close`; `withLiveDisplay` performs the close
from a `finally` block during normal return or Nim exception unwinding. It does
not handle process termination, signals, defects, or `SIGKILL`.

Do not let another writer modify the display's terminal rows while it is open.
TerminalStatus does not enter raw mode, create a TerminalScreen session, query
terminal geometry, or run a background refresh loop. Applications choose
renderer widths and schedule their own refreshes.

For application logs, clear or close the display before writing and then redraw
or create a new display. Two displays may target unrelated streams, but sharing
the same terminal rows is a caller error; TerminalStatus keeps no global active
display registry or lock.
