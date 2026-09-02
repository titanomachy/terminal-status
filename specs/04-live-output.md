# Live output specification

`terminal_status/live` owns a bounded set of output rows. It does not own raw
input mode, the alternate screen, resize signals, the supplied stream, or a
background refresh loop.

## Public API

```nim
type
  LiveMode* = enum
    liveAuto
    liveAnsi
    livePlain

  PlainOutputPolicy* = enum
    plainFinalOnly
    plainEveryChange

  FinishPolicy* = enum
    finishKeep
    finishClear

  LiveDisplayState* = enum
    displayNew
    displayOpen
    displayClosed

  LiveDisplayError* = object of StatusError

  LiveDisplayOptions* = object
    output*: File
    mode*: LiveMode
    plainPolicy*: PlainOutputPolicy
    finishPolicy*: FinishPolicy
    hideCursor*: bool
    flushWrites*: bool

  LiveDisplay* = object # fields private

proc defaultLiveDisplayOptions*(output: File = stderr): LiveDisplayOptions
proc initLiveDisplay*(options = defaultLiveDisplayOptions()): LiveDisplay
proc state*(display: LiveDisplay): LiveDisplayState
proc effectiveMode*(display: LiveDisplay): Option[LiveMode]
proc open*(display: var LiveDisplay)
proc update*(display: var LiveDisplay, frame: string)
proc close*(display: var LiveDisplay)

template withLiveDisplay*(name: untyped,
                          options: LiveDisplayOptions,
                          body: untyped)
```

If Nim cannot use `stderr` or a constructed options object as a default value,
provide equivalent zero-argument overloads.

Default options:

- output: `stderr`;
- mode: `liveAuto`;
- plain policy: `plainFinalOnly`;
- finish policy: `finishKeep`;
- hide cursor: `false`;
- flush writes: `true`.

The cursor is not hidden by default because an application or TerminalScreen
session may already own cursor visibility. Applications can opt in when they
also own the output lifecycle.

## Lifecycle

`initLiveDisplay` stores options, begins in `displayNew`, performs no I/O, and
does not query capabilities.

`open` behavior:

- `displayNew`: validate options, select an effective mode, optionally hide the
  cursor in ANSI mode, and transition to `displayOpen`;
- `displayOpen`: idempotent no-op;
- `displayClosed`: raise `LiveDisplayError`; displays are single-use.

`update` requires `displayOpen`; calls in new or closed state raise
`LiveDisplayError`. It validates the complete frame before writing or changing
the cached frame. Invalid input never causes partial output.

`close` behavior:

- `displayNew`: transition directly to closed without capability detection or
  I/O;
- `displayOpen`: finalize according to effective mode and policies, restore a
  cursor hidden by this object, flush as configured, then become closed;
- `displayClosed`: idempotent no-op.

The implementation MUST mark the object closed in a `finally` path even when a
write/flush raises. It SHOULD attempt cursor restoration after a finalization
write fails, but MUST not hide the original exception with a later cleanup
error.

The scoped template has the same user shape as TerminalScreen:

```nim
withLiveDisplay display, defaultLiveDisplayOptions():
  display.update(render(progress, options, now))
```

It creates, opens, and exposes `name`, executes `body`, and calls `close` from a
`finally` block. A Nim exception in `body` is re-raised after cleanup. The
template does not catch defects, signals, process termination, or `SIGKILL`;
documentation must describe this realistic boundary.

## Effective-mode selection

- `liveAnsi`: effective mode is ANSI without capability detection. This is the
  deterministic test seam and an explicit caller assertion.
- `livePlain`: effective mode is plain without capability detection.
- `liveAuto`: call TerminalScreen `detectCapabilities(output = options.output)`
  during `open`; choose ANSI when `supportsAnsi` is true and plain otherwise.

`effectiveMode` is `none` in new state and `some(liveAnsi)` or
`some(livePlain)` after open/close. It never returns `liveAuto` after selection.
Capability detection occurs once per display, not per update.

TerminalStatus does not open a TerminalScreen session and never changes input
mode. It does not query terminal geometry. Renderer width is an explicit caller
choice.

## Frame contract

A frame is either empty or one or more logical rows separated by LF (`\n`). A
non-empty frame MUST NOT end in LF. Internal empty rows are allowed.

Before accepting a frame, validate:

- reject any carriage return (`\r`) or tab;
- reject C0/C1 controls other than LF and valid bytes inside retained ANSI
  sequences;
- using TerminalStyle tokenization, allow plain text, SGR CSI ending in `m`,
  and well-formed OSC-8 open/close tokens;
- reject cursor movement, erasure, title changes, clipboard OSC, two-byte
  escapes, malformed/incomplete escapes, and every other control sequence.

On violation, raise `ValueError` without modifying cached state or output.
This stricter live contract is intentional: renderer output already complies,
and arbitrary cursor-bearing strings could escape the display's owned region.

The live layer MUST NOT truncate or style frames. In ANSI mode it retains safe
SGR/OSC-8 tokens. In plain mode it removes all ANSI with TerminalStyle and
writes only visible text.

An empty frame means “no owned rows.” In ANSI mode it clears a previous region;
in plain mode it replaces the cached final snapshot with empty output.

## ANSI redraw algorithm

Use TerminalScreen's cursor command builders and these private constants:

```text
carriage return:  \r
erase whole line: ESC [ 2 K
terminal row join: \r\n
```

Do not export the erase sequence as a general cursor API.

### First non-empty update

Write the frame at the current cursor location, replacing each logical LF with
CRLF. Do not append a newline after the final row. Store the exact validated
frame and its logical row count. The cursor ends after the final row.

### Duplicate update

If the validated frame is byte-identical to the cached frame, perform no write
and no flush.

### Replacement update

If a previous non-empty frame owns `P` rows:

1. write CR;
2. if `P > 1`, write `cursorUpCode(P - 1)` to reach the first owned row;
3. for each previous row from first to last, write `ESC[2K`; between rows write
   `cursorDownCode(1)` followed by CR;
4. if `P > 1`, write `cursorUpCode(P - 1)`; then write CR;
5. write the new frame with CRLF row joins, or write nothing for an empty new
   frame;
6. replace cached text and row count, then flush once when configured.

This deliberately clears all previous rows before drawing. It is simpler and
safer than a diff renderer and correctly handles narrower lines and a smaller
new row count. It MUST NOT erase rows above the first owned row or below the
last previously owned row.

### ANSI close

- `finishKeep`: when a non-empty frame exists, write CRLF once so subsequent
  output begins at column one below the owned region. The visible frame remains.
- `finishClear`: clear the current owned rows using the replacement clearing
  algorithm and do not append a newline.
- if no frame exists, neither policy writes a row/newline.
- if this object successfully wrote a hide-cursor command during `open`, write
  TerminalScreen's show-cursor command exactly once during close. Never show a
  cursor this object did not hide.
- perform at most one final configured flush after finalization/restoration.

## Plain output behavior

ANSI cursor redraw is impossible for redirected streams, so policies are log
oriented.

### `plainFinalOnly` (default)

`update` validates, strips ANSI, and caches only the latest frame; it writes
nothing. On close with `finishKeep`, write the latest non-empty plain frame with
each logical row followed by `\n`, including a newline after the final row. With
`finishClear`, write nothing. An empty final frame writes nothing.

This means fast spinner refreshes do not flood redirected logs.

### `plainEveryChange`

On each update whose stripped plain frame differs from the last emitted plain
frame, write every logical row followed by `\n`, including the final row. Do
not write duplicate visible frames. Close does not repeat the last emitted
frame. `finishClear` cannot retract lines already written; it only suppresses a
not-yet-emitted cached final frame.

Plain mode never hides/shows the cursor and never emits any ANSI token.

## I/O and flushing

- The `File` is borrowed and remains open after `close` and after exceptions.
- `flushWrites == true`: flush after an effective non-duplicate ANSI update,
  after a plain every-change write, and once after close writes.
- `flushWrites == false`: perform no explicit flush.
- Duplicate updates perform neither write nor flush.
- Let normal Nim I/O exceptions propagate as catchable exceptions after cleanup
  state is made consistent.

## Byte-exact examples

Using forced ANSI, no cursor hiding, and `flushWrites = false`:

```text
update("one")
bytes: "one"

update("two")
bytes: "\r\e[2K\rtwo"

close(finishKeep)
bytes: "\r\n"
```

Replacing two rows with one:

```text
old frame write: "a\r\nb"
replacement control/write:
  "\r" + cursorUpCode(1) + "\e[2K" + cursorDownCode(1) +
  "\r\e[2K" + cursorUpCode(1) + "\r" + "c"
```

Tests SHOULD construct expected bytes with TerminalScreen cursor builders rather
than duplicating their escape literals.

## Concurrency and external output

`LiveDisplay` is not thread-safe. While it is open, no other writer may write to
the same terminal rows. Applications must serialize logs with updates by
closing/clearing the display, writing the log, then redrawing or creating a new
display. Providing a log interlock is outside `0.1.x`.

The implementation MUST NOT add process-global active-display tracking. Two
displays on unrelated streams are allowed; two displays sharing rows are a
caller error.

