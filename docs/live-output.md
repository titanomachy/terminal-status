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

The finite [`redirected_output.nim`](../examples/redirected_output.nim)
example forces this final-only strategy so it prints the same single snapshot
in a terminal, file, or pipe. [`live_output.nim`](../examples/live_output.nim)
uses auto mode by default and also demonstrates `--every-change`, forced
`--ansi`, `--clear`, and display-owned `--hide-cursor` behavior.

## Complete-frame safety

`update` accepts an empty frame or LF-separated logical rows with no trailing
LF. It retains only safe SGR styling and well-formed OSC-8 hyperlinks. A
carriage return, tab, other C0/C1 control, cursor movement, erasure, terminal
title or clipboard operation, two-byte escape, unrelated OSC, or malformed or
incomplete escape raises `ValueError` before anything is written or the cached
final frame changes. This strict boundary prevents a caller-supplied frame
from moving outside the rows owned by the display.

Pure TerminalStatus renderers already satisfy this contract. If an application
constructs frames itself, normalize untrusted labels through a renderer rather
than passing arbitrary terminal byte strings directly to `update`.

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

The finite [`live_status.nim`](../examples/live_status.nim) example shows the
complete pattern: mutate a model, render it with the loop's monotonic timestamp,
submit the complete frame explicitly, and let `withLiveDisplay` own cleanup.

For application logs, clear or close the display before writing and then redraw
or create a new display. Two displays may target unrelated streams, but sharing
the same terminal rows is a caller error; TerminalStatus keeps no global active
display registry or lock.

## TerminalScreen composition

TerminalScreen and TerminalStatus have separate ownership boundaries. A
TerminalScreen session may own input and platform state while a `LiveDisplay`
borrows its output stream and owns only its rendered rows. Configure one owner
for cursor visibility and keep all writes to those rows on the display's owning
thread:

```nim
import terminal_screen
import terminal_status

var sessionOptions = defaultSessionOptions()
sessionOptions.rawMode = false
sessionOptions.hideCursor = false
sessionOptions.requireTerminal = false
sessionOptions.monitorResize = false

withTerminalSession screen, stdin, stdout, sessionOptions:
  var liveOptions = defaultLiveDisplayOptions(stdout)
  withLiveDisplay display, liveOptions:
    display.update("TerminalStatus inside TerminalScreen")
  doAssert screen.isOpen
```

Closing the display neither closes the surrounding session nor enters or
restores any input mode. The finite
[`screen_composition.nim`](../examples/screen_composition.nim) example contains
the complete runnable form.
