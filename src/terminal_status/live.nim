## Explicit, bounded live output for rendered TerminalStatus frames.
##
## A live display borrows its output `File` and chooses ANSI redraw or plain
## log output when opened. Each display has one owning thread and uses no
## global lock or background worker. It never owns, enters, or restores
## terminal input modes, and it does not own terminal size, a refresh timer,
## or the supplied stream.

import std/[options, strutils, unicode]

import terminal_screen
import terminal_style

import terminal_status/types

type
  LiveMode* = enum
    ## Selects how a live display writes frames.
    liveAuto
    liveAnsi
    livePlain

  PlainOutputPolicy* = enum
    ## Selects whether plain output retains only the final frame or logs every
    ## changed visible frame.
    plainFinalOnly
    plainEveryChange

  FinishPolicy* = enum
    ## Selects whether the current frame remains visible when the display
    ## closes.
    finishKeep
    finishClear

  LiveDisplayState* = enum
    ## Lifecycle state of a single-use live display.
    displayNew
    displayOpen
    displayClosed

  LiveDisplayError* = object of StatusError
    ## Raised when a live display operation is invalid for its lifecycle.

  LiveDisplayOptions* = object
    ## Per-display output and lifecycle options.
    ##
    ## `output` is borrowed and is never closed by `LiveDisplay`. A display is
    ## single-thread owned; callers must serialize any other writes to the
    ## same terminal rows.
    output*: File
      ## Borrowed destination stream. The default is `stderr`.
    mode*: LiveMode
      ## Requested output strategy, resolved once by `open`.
    plainPolicy*: PlainOutputPolicy
      ## Redirected-output coalescing or changed-frame logging policy.
    finishPolicy*: FinishPolicy
      ## Whether `close` leaves the last frame visible or erases its rows.
    hideCursor*: bool
      ## Hides the cursor only in ANSI mode and restores it during cleanup.
    flushWrites*: bool
      ## Flushes effective updates and close output when enabled.

  LiveDisplay* = object
    ## A single-use live output region with private mutable state.
    options: LiveDisplayOptions
    currentState: LiveDisplayState
    selectedMode: Option[LiveMode]
    cachedFrame: string
    ownedRows: int
    lastPlainFrame: string
    cursorHidden: bool

const
  EraseWholeLine = "\e[2K"
  TerminalRowJoin = "\r\n"

proc defaultLiveDisplayOptions*(output: File = stderr): LiveDisplayOptions =
  ## Returns conservative live-output defaults for the borrowed `output`.
  ##
  ## Auto mode writes ANSI only to an ANSI-capable terminal. Redirected output
  ## caches the latest frame and emits it once when the display closes.
  LiveDisplayOptions(
    output: output,
    mode: liveAuto,
    plainPolicy: plainFinalOnly,
    finishPolicy: finishKeep,
    hideCursor: false,
    flushWrites: true
  )

proc initLiveDisplay*(
    options = defaultLiveDisplayOptions()
): LiveDisplay =
  ## Initializes a new display without querying or writing to the terminal.
  LiveDisplay(options: options, currentState: displayNew)

proc state*(display: LiveDisplay): LiveDisplayState =
  ## Returns the display's current lifecycle state.
  display.currentState

proc effectiveMode*(display: LiveDisplay): Option[LiveMode] =
  ## Returns the selected ANSI/plain mode after `open`, or none while new.
  display.selectedMode

proc validOsc8(sequence: string): bool =
  if not sequence.startsWith("\e]8;"):
    return false

  let bodyEnd =
    if sequence.endsWith("\e\\"): sequence.len - 2
    elif sequence.endsWith("\a"): sequence.len - 1
    else: return false
  if bodyEnd < 4:
    return false

  let body = sequence[4 ..< bodyEnd]
  if body.find(';') < 0:
    return false
  for rune in body.runes:
    let codepoint = int(rune)
    if codepoint < 0x20 or codepoint in 0x7f .. 0x9f:
      return false
  true

proc validateFrame(frame: string) =
  if frame.len > 0 and frame[^1] == '\n':
    raise newException(ValueError, "live frame must not end in a newline")

  for token in tokenizeAnsi(frame):
    case token.kind
    of atkText:
      for rune in token.value.runes:
        let codepoint = int(rune)
        if (codepoint < 0x20 and codepoint != 0x0a) or
            codepoint in 0x7f .. 0x9f:
          raise newException(ValueError,
            "live frame contains a disallowed control character")
    of atkCsi:
      if token.value[^1] != 'm':
        raise newException(ValueError,
          "live frame contains a non-SGR CSI sequence")
    of atkOsc:
      if not token.value.validOsc8:
        raise newException(ValueError,
          "live frame contains a non-OSC-8 sequence")
    of atkEscape:
      raise newException(ValueError,
        "live frame contains a two-byte escape sequence")

proc logicalRows(frame: string): int =
  if frame.len == 0: 0 else: frame.count('\n') + 1

proc terminalFrame(frame: string): string =
  frame.replace("\n", TerminalRowJoin)

proc clearingBytes(rows: int): string =
  # Starting after the final owned row, walk only the owned region. Clearing
  # every old row makes both narrower text and fewer replacement rows safe.
  if rows <= 0:
    return ""
  result = "\r"
  if rows > 1:
    result.add cursorUpCode(rows - 1)
  for row in 0 ..< rows:
    result.add EraseWholeLine
    if row < rows - 1:
      result.add cursorDownCode(1)
      result.add '\r'
  if rows > 1:
    result.add cursorUpCode(rows - 1)
  result.add '\r'

proc writeAnsiUpdate(display: var LiveDisplay; frame: string) =
  if frame == display.cachedFrame:
    return

  var bytes: string
  if display.ownedRows > 0:
    bytes.add clearingBytes(display.ownedRows)
  if frame.len > 0:
    bytes.add terminalFrame(frame)

  if bytes.len > 0:
    display.options.output.write(bytes)
  display.cachedFrame = frame
  display.ownedRows = logicalRows(frame)
  if bytes.len > 0 and display.options.flushWrites:
    display.options.output.flushFile()

proc writePlainUpdate(display: var LiveDisplay; frame: string) =
  let plainFrame = stripAnsi(frame)
  display.cachedFrame = plainFrame
  if display.options.plainPolicy == plainEveryChange and
      plainFrame != display.lastPlainFrame:
    if plainFrame.len > 0:
      display.options.output.write(plainFrame & "\n")
    display.lastPlainFrame = plainFrame
    if plainFrame.len > 0 and display.options.flushWrites:
      display.options.output.flushFile()

proc open*(display: var LiveDisplay) =
  ## Opens a new display and selects its effective output mode once.
  ##
  ## Forced modes perform no capability query. Auto mode asks TerminalScreen
  ## whether the borrowed output supports ANSI. Opening an already-open display
  ## is a no-op; a closed display cannot be reused.
  case display.currentState
  of displayOpen:
    return
  of displayClosed:
    raise newException(LiveDisplayError,
      "a closed live display cannot be reopened")
  of displayNew:
    discard

  if display.options.output == nil:
    raise newException(ValueError, "live output file must not be nil")

  let selected = case display.options.mode
    of liveAnsi: liveAnsi
    of livePlain: livePlain
    of liveAuto:
      if detectCapabilities(output = display.options.output).supportsAnsi:
        liveAnsi
      else:
        livePlain

  display.selectedMode = some(selected)
  if selected == liveAnsi and display.options.hideCursor:
    display.options.output.hideCursor(flush = false)
    display.cursorHidden = true
    if display.options.flushWrites:
      try:
        display.options.output.flushFile()
      except CatchableError:
        # The hide bytes were written before flushing. Make a best effort to
        # restore visibility while leaving this display new and reusable.
        display.cursorHidden = false
        try:
          display.options.output.showCursor(flush = true)
        except CatchableError:
          discard
        raise
  display.currentState = displayOpen

proc update*(display: var LiveDisplay; frame: string) =
  ## Validates and submits one complete logical frame.
  ##
  ## A frame is empty or contains LF-separated rows without a trailing LF.
  ## Safe SGR and well-formed OSC-8 controls are retained; carriage returns,
  ## tabs, other C0/C1 controls, cursor movement, erasure, unrelated ANSI
  ## controls, and malformed/incomplete escapes raise `ValueError` before
  ## output or cached state changes.
  ##
  ## ANSI mode redraws the owned rows. Plain final-only mode caches the latest
  ## frame without writing, while every-change mode logs changed visible
  ## frames. Plain modes strip safe SGR and OSC-8 sequences before output.
  ## The owning thread must serialize updates with other writes to the same
  ## terminal rows.
  if display.currentState != displayOpen:
    raise newException(LiveDisplayError,
      "live display must be open before update")

  validateFrame(frame)
  case display.selectedMode.get
  of liveAnsi:
    display.writeAnsiUpdate(frame)
  of livePlain:
    display.writePlainUpdate(frame)
  of liveAuto:
    raise newException(Defect, "live auto mode was not resolved during open")

proc close*(display: var LiveDisplay) =
  ## Finalizes a display and releases its row/cursor ownership.
  ##
  ## `finishKeep` advances below a retained ANSI frame; `finishClear` erases
  ## it. Cursor visibility is restored only when this display hid it. Closing
  ## is idempotent, performs at most one configured final flush, and never
  ## closes the borrowed output stream.
  case display.currentState
  of displayClosed:
    return
  of displayNew:
    display.currentState = displayClosed
    return
  of displayOpen:
    discard

  var firstError: ref CatchableError
  var wrote = false
  try:
    try:
      case display.selectedMode.get
      of liveAnsi:
        if display.ownedRows > 0:
          if display.options.finishPolicy == finishKeep:
            display.options.output.write(TerminalRowJoin)
          else:
            display.options.output.write(clearingBytes(display.ownedRows))
          wrote = true
      of livePlain:
        if display.options.plainPolicy == plainFinalOnly and
            display.options.finishPolicy == finishKeep and
            display.cachedFrame.len > 0:
          display.options.output.write(display.cachedFrame & "\n")
          wrote = true
      of liveAuto:
        raise newException(Defect,
          "live auto mode was not resolved during open")
    except CatchableError as error:
      firstError = error

    if display.cursorHidden:
      display.cursorHidden = false
      try:
        display.options.output.showCursor(flush = false)
        wrote = true
      except CatchableError as error:
        if firstError.isNil:
          firstError = error

    if wrote and display.options.flushWrites:
      try:
        display.options.output.flushFile()
      except CatchableError as error:
        if firstError.isNil:
          firstError = error
  finally:
    display.currentState = displayClosed

  if not firstError.isNil:
    raise firstError

template withLiveDisplay*(name: untyped, options: LiveDisplayOptions,
                          body: untyped) =
  ## Opens a scoped display named `name` and always closes it when `body`
  ## returns or raises a catchable Nim exception. If both the body and cleanup
  ## fail, the original body exception is preserved. Process termination,
  ## signals, defects, and `SIGKILL` are outside this guarantee.
  block:
    var name = initLiveDisplay(options)
    name.open()
    var bodyError: ref CatchableError
    try:
      try:
        body
      except CatchableError as error:
        bodyError = error
    finally:
      try:
        name.close()
      except CatchableError:
        if bodyError.isNil:
          raise
    if not bodyError.isNil:
      raise bodyError
