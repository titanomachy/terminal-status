import std/[options, os, strutils, unittest]

import terminal_status
import terminal_screen
import terminal_style

let
  repositoryDir = currentSourcePath().parentDir.parentDir
  temporaryDir = repositoryDir / "build" / "test-tmp"

var captureNumber = 0

proc capturePath(label: string): string =
  createDir(temporaryDir)
  inc captureNumber
  temporaryDir / ("live-" & label & "-" & $captureNumber & ".txt")

proc openCapture(label: string): tuple[path: string, output: File] =
  result.path = capturePath(label)
  if fileExists(result.path):
    removeFile(result.path)
  if not open(result.output, result.path, fmWrite):
    raise newException(IOError, "cannot open live-output test capture")

proc finishCapture(capture: var tuple[path: string, output: File]): string =
  capture.output.close()
  result = readFile(capture.path)
  removeFile(capture.path)

proc clearingBytes(rows: int): string =
  ## Mirrors the normative algorithm while sourcing movement codes from
  ## TerminalScreen, so these tests also follow its command encoding.
  if rows <= 0:
    return ""
  result = "\r"
  if rows > 1:
    result.add cursorUpCode(rows - 1)
  for row in 0 ..< rows:
    result.add "\e[2K"
    if row < rows - 1:
      result.add cursorDownCode(1)
      result.add '\r'
  if rows > 1:
    result.add cursorUpCode(rows - 1)
  result.add '\r'

proc screenRows(bytes: string; columns: int): seq[string] =
  ## Small ASCII screen model with delayed autowrap, CR/LF, and the cursor/erase
  ## commands used by LiveDisplay. It checks visible results, not just bytes.
  var row = 0
  var column = 0
  result = @[repeat(' ', columns)]
  template ensureRow() =
    while result.len <= row:
      result.add repeat(' ', columns)
  for token in tokenizeAnsi(bytes):
    case token.kind
    of atkText:
      for character in token.value:
        case character
        of '\r': column = 0
        of '\n':
          inc row
          ensureRow()
        else:
          doAssert character in {' ' .. '~'}
          if column == columns:
            column = 0
            inc row
            ensureRow()
          result[row][column] = character
          inc column
    of atkCsi:
      case token.value[^1]
      of 'K':
        doAssert token.value == "\e[2K"
        result[row] = repeat(' ', columns)
      of 'A': row = max(0, row - parseInt(token.value[2 ..< token.value.high]))
      of 'B':
        row += parseInt(token.value[2 ..< token.value.high])
        ensureRow()
      of 'm': discard
      else: doAssert false, "unexpected screen command"
    of atkOsc: discard
    of atkEscape: doAssert false, "unexpected escape"

suite "live output strategies":
  test "defaults borrow stderr and defer all effects until open":
    let options = defaultLiveDisplayOptions()
    var display = initLiveDisplay()

    check options.output == stderr
    check options.mode == liveAuto
    check options.plainPolicy == plainFinalOnly
    check options.finishPolicy == finishKeep
    check not options.hideCursor
    check options.flushWrites
    check options.width == 0
    check display.state == displayNew
    check display.effectiveMode == none(LiveMode)
    check display.width == none(int)

    display.close()
    check display.state == displayClosed
    check display.effectiveMode == none(LiveMode)

  test "single-use lifecycle rejects updates and reopening at exact boundaries":
    var capture = openCapture("lifecycle")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    var display = initLiveDisplay(options)

    expect LiveDisplayError:
      display.update("too early")
    display.open()
    display.open() # Repeated open while open is the documented no-op.
    check display.state == displayOpen
    check display.effectiveMode == some(livePlain)
    display.close()
    expect LiveDisplayError:
      display.update("too late")
    expect LiveDisplayError:
      display.open()
    display.close()

    check capture.finishCapture() == ""

  test "negative widths are rejected before selecting a mode or writing":
    for mode in [liveAnsi, livePlain, liveAuto]:
      var capture = openCapture("negative-width")
      var options = defaultLiveDisplayOptions(capture.output)
      options.mode = mode
      options.width = -1
      options.hideCursor = true
      var display = initLiveDisplay(options)
      expect ValueError:
        display.open()
      check display.state == displayNew
      check display.effectiveMode.isNone
      check display.width.isNone
      display.close()
      check capture.finishCapture() == ""

  test "plain output retains full rows regardless of an explicit ANSI width":
    for policy in [plainFinalOnly, plainEveryChange]:
      var capture = openCapture("plain-width")
      var options = defaultLiveDisplayOptions(capture.output)
      options.mode = livePlain
      options.plainPolicy = policy
      options.width = 3
      withLiveDisplay display, options:
        check display.width.isNone
        display.update("123456789012345")
      check capture.finishCapture() == "123456789012345\n"

  test "a nil borrowed stream fails open without changing lifecycle state":
    var options = defaultLiveDisplayOptions()
    options.output = nil
    options.mode = livePlain
    var display = initLiveDisplay(options)

    expect ValueError:
      display.open()
    check display.state == displayNew
    check display.effectiveMode == none(LiveMode)
    display.close()
    check display.state == displayClosed

  test "forced plain caches only the latest visible frame by default":
    var capture = openCapture("plain-final")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    var display = initLiveDisplay(options)

    display.open()
    check display.effectiveMode == some(livePlain)
    display.update("\e[31mfirst\e[0m")
    display.update("second\nrow")
    display.close()

    # LiveDisplay borrows the stream: it remains writable after close.
    capture.output.write("tail\n")
    capture.output.flushFile()
    check capture.finishCapture() == "second\nrow\ntail\n"

  test "plain every-change logs changed visible frames without duplicates":
    var capture = openCapture("plain-every")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    options.plainPolicy = plainEveryChange
    var display = initLiveDisplay(options)

    display.open()
    display.update("\e[31mone\e[0m")
    display.update("\e[34mone\e[0m")
    display.update("two\nrows")
    display.update("")
    display.close()

    check capture.finishCapture() == "one\ntwo\nrows\n"

  test "plain final-only suppresses duplicate and empty final frames":
    var capture = openCapture("plain-empty-final")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    var display = initLiveDisplay(options)

    display.open()
    display.update("one")
    display.update("one")
    display.update("")
    display.close()

    check capture.finishCapture() == ""

  test "auto mode uses plain output for a redirected file":
    var capture = openCapture("auto")
    let options = defaultLiveDisplayOptions(capture.output)
    var display = initLiveDisplay(options)

    display.open()
    check display.effectiveMode == some(livePlain)
    display.update("old")
    display.update("final")
    display.close()

    check capture.finishCapture() == "final\n"

  test "forced ANSI bypasses redirected-stream capability detection":
    var capture = openCapture("ansi")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = false
    var display = initLiveDisplay(options)

    display.open()
    check display.effectiveMode == some(liveAnsi)
    display.update("one")
    display.close()

    check capture.finishCapture() == "one\r\n"

  test "invalid updates do not replace the cached plain final frame":
    var capture = openCapture("invalid")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    var display = initLiveDisplay(options)

    display.open()
    display.update("safe")
    expect ValueError:
      display.update("invalid\n")
    display.close()

    check capture.finishCapture() == "safe\n"

  test "safe SGR and OSC-8 controls pass validation":
    var capture = openCapture("safe-controls")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = false
    var display = initLiveDisplay(options)
    let frame = "\e[1;32mready\e[0m\n" &
      "\e]8;;https://example.com\e\\docs\e]8;;\e\\"

    display.open()
    display.update(frame)
    display.close()

    check capture.finishCapture() ==
      frame.replace("\n", "\r\n") & "\r\n"

  test "private and intermediate m commands fail without output or cache changes":
    for mode in [liveAnsi, livePlain]:
      for policy in [plainFinalOnly, plainEveryChange]:
        var capture = openCapture("non-sgr-m")
        var options = defaultLiveDisplayOptions(capture.output)
        options.mode = mode
        options.plainPolicy = policy
        var display = initLiveDisplay(options)
        display.open()
        display.update("safe")
        let before = readFile(capture.path)
        for command in ["\e[>4;2m", "\e[?4m", "\e[=1m", "\e[1$m", "\e[1 m"]:
          expect ValueError:
            display.update("unsafe" & command)
          check readFile(capture.path) == before
        display.close()
        check capture.finishCapture() ==
          (if mode == liveAnsi: "safe\r\n" else: "safe\n")

  test "numeric SGR accepts empty resets indexed colors and RGB subparameters":
    var capture = openCapture("numeric-sgr")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = false
    let frame = "\e[m\e[1;32mready\e[38;5;123m indexed" &
      "\e[38;2;255;0;0m RGB\e[48:2::0:128:255m background\e[0m"
    withLiveDisplay display, options:
      display.update(frame)
    check capture.finishCapture() == frame & "\r\n"

  test "every unsafe frame class is rejected before output or cache mutation":
    var capture = openCapture("unsafe-controls")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = true
    var display = initLiveDisplay(options)
    let unsafeFrames = [
      "carriage\rreturn",
      "tab\tcharacter",
      "nul\x00character",
      "delete\x7fcharacter",
      "C1 \xC2\x9B control",
      "cursor up \e[2A",
      "erase line \e[2K",
      "title \e]0;changed\a",
      "clipboard \e]52;c;c2VjcmV0\a",
      "two-byte escape \e7",
      "incomplete CSI \e[31",
      "incomplete OSC \e]8;;https://example.com",
      "malformed CSI \e[\x01m",
      "malformed OSC-8 \e]8;missing-uri-separator\a",
      "OSC-8 control \e]8;;bad\ruri\a",
      "trailing newline\n"
    ]

    display.open()
    display.update("safe")
    for frame in unsafeFrames:
      expect ValueError:
        display.update(frame)
      check readFile(capture.path) == "safe"

    display.update("final")
    display.close()

    check capture.finishCapture() ==
      "safe" & clearingBytes(1) & "final\r\n"

  test "scoped plain output emits its final frame during exception cleanup":
    var capture = openCapture("scoped")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    var caught = false

    try:
      withLiveDisplay display, options:
        display.update("last valid frame")
        raise newException(IOError, "deliberate body failure")
    except IOError as error:
      caught = error.msg == "deliberate body failure"

    check caught
    check capture.finishCapture() == "last valid frame\n"

suite "ANSI redraw and cleanup":
  test "width bounds prevent stale wrapped rows after replacement and clear":
    # Confirm that the screen model detects the original logical-row bug.
    let oldBytes = "123456789012345" & clearingBytes(1) & "done" & clearingBytes(1)
    check screenRows(oldBytes, 10)[0] == "1234567890"

    var capture = openCapture("bounded-clear")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.width = 10
    options.finishPolicy = finishClear
    var display = initLiveDisplay(options)
    check display.width.isNone
    display.open()
    check display.width == some(10)
    display.update("123456789012345")
    check readFile(capture.path) == "\r1234567890"
    display.update("1234567890changed outside the visible width")
    check readFile(capture.path) == "\r1234567890"
    display.update("done")
    display.close()
    check display.width == some(10)
    let bytes = capture.finishCapture()
    check bytes == "\r1234567890" & clearingBytes(1) & "done" & clearingBytes(1)
    check screenRows("banner\r\n" & bytes, 10) ==
      @["banner    ", "          "]

  test "bounded multi-row frames clear every row and preserve internal blanks":
    var capture = openCapture("bounded-multi")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.width = 10
    options.finishPolicy = finishClear
    withLiveDisplay display, options:
      display.update("123456789012345\n\nabcdefghijklmno")
      display.update("done")
    let bytes = capture.finishCapture()
    check bytes == "\r1234567890\r\n\r\nabcdefghij" &
      clearingBytes(3) & "done" & clearingBytes(1)
    check screenRows("banner\r\n" & bytes, 10) ==
      @["banner    ", "          ", "          ", "          "]

  test "bounded keep output finishes below the final physical row":
    var capture = openCapture("bounded-keep")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.width = 10
    withLiveDisplay display, options:
      display.update("123456789012345")
    let bytes = capture.finishCapture()
    check bytes == "\r1234567890\r\n"
    check screenRows(bytes, 10) == @["1234567890", "          "]

  test "clipping preserves graphemes and closes sliced styling and hyperlinks":
    for sample in [
      ("界界界", 3, "界"),
      ("e\u0301e\u0301e\u0301", 2, "e\u0301e\u0301"),
      ("界", 1, ""),
      ("\e]8;;https://example.com\e\\\e[31mabcdef", 3, "abc")
    ]:
      var capture = openCapture("bounded-graphemes")
      var options = defaultLiveDisplayOptions(capture.output)
      options.mode = liveAnsi
      options.width = sample[1]
      withLiveDisplay display, options:
        display.update(sample[0])
      let bytes = capture.finishCapture()
      check stripAnsi(bytes).replace("\r", "").replace("\n", "") == sample[2]
      if sample[0].startsWith("\e]8;"):
        check "\e]8;;\e\\" in bytes
        check "\e[0m" in bytes

  test "unsafe input outside the clipped columns still rejects the entire frame":
    var capture = openCapture("bounded-unsafe")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.width = 4
    withLiveDisplay display, options:
      display.update("safe")
      expect ValueError:
        display.update("safe hidden\e[2J")
    check capture.finishCapture() == "\rsafe\r\n"

  test "a first multi-row frame uses only terminal row separators":
    var capture = openCapture("ansi-first-multi")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = false
    var display = initLiveDisplay(options)

    display.open()
    display.update("first\nsecond\nthird")
    display.close()

    check capture.finishCapture() == "first\r\nsecond\r\nthird\r\n"

  test "first draw is direct and duplicate updates write nothing":
    var capture = openCapture("ansi-duplicate")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = false
    var display = initLiveDisplay(options)

    display.open()
    display.update("one")
    display.update("one")
    display.update("two")
    display.close()

    check capture.finishCapture() ==
      "one" & clearingBytes(1) & "two\r\n"

  test "growing and shrinking frames clear exactly the previously owned rows":
    var capture = openCapture("ansi-resize")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = false
    var display = initLiveDisplay(options)

    display.open()
    display.update("a")
    display.update("b\nc\nd")
    display.update("e")
    display.close()

    check capture.finishCapture() ==
      "a" & clearingBytes(1) & "b\r\nc\r\nd" &
      clearingBytes(3) & "e\r\n"

  test "an empty update clears the owned region and leaves no final row":
    var capture = openCapture("ansi-empty")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = false
    var display = initLiveDisplay(options)

    display.open()
    display.update("first\nsecond")
    display.update("")
    display.close()

    check capture.finishCapture() ==
      "first\r\nsecond" & clearingBytes(2)

  test "finishClear erases the region and repeated close is a no-op":
    var capture = openCapture("ansi-clear")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.finishPolicy = finishClear
    options.flushWrites = false
    var display = initLiveDisplay(options)

    display.open()
    display.update("top\nbottom")
    display.close()
    display.close()

    check display.state == displayClosed
    check display.effectiveMode == some(liveAnsi)
    check capture.finishCapture() ==
      "top\r\nbottom" & clearingBytes(2)

  test "cursor restoration occurs exactly when this display hid it":
    var capture = openCapture("ansi-cursor")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.finishPolicy = finishClear
    options.hideCursor = true
    options.flushWrites = false
    var display = initLiveDisplay(options)

    display.open()
    display.update("owned")
    display.close()
    display.close()

    check capture.finishCapture() ==
      HideCursorCode & "owned" & clearingBytes(1) & ShowCursorCode

  test "configured update and close writes are flushed":
    var capture = openCapture("ansi-flush")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.flushWrites = true
    var display = initLiveDisplay(options)

    display.open()
    display.update("visible")
    check readFile(capture.path) == "visible"
    display.close()
    check readFile(capture.path) == "visible\r\n"

    capture.output.write("tail")
    capture.output.flushFile()
    check capture.finishCapture() == "visible\r\ntail"

  test "plain finishClear suppresses a cached final-only frame":
    var capture = openCapture("plain-clear")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    options.finishPolicy = finishClear
    var display = initLiveDisplay(options)

    display.open()
    display.update("not emitted")
    display.close()

    check capture.finishCapture() == ""

  test "a final write failure still closes the display":
    var capture = openCapture("failed-final-write")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = livePlain
    var display = initLiveDisplay(options)

    display.open()
    display.update("cannot be written")
    display.failNextFinalWriteForTesting()
    expect IOError:
      display.close()
    check display.state == displayClosed
    display.close()
    check capture.finishCapture() == ""

  test "scoped ANSI cleanup clears rows and restores its cursor on exceptions":
    var capture = openCapture("ansi-scoped")
    var options = defaultLiveDisplayOptions(capture.output)
    options.mode = liveAnsi
    options.finishPolicy = finishClear
    options.hideCursor = true
    options.flushWrites = false
    var caught = false

    try:
      withLiveDisplay display, options:
        display.update("working")
        raise newException(IOError, "deliberate ANSI body failure")
    except IOError as error:
      caught = error.msg == "deliberate ANSI body failure"

    check caught
    check capture.finishCapture() ==
      HideCursorCode & "working" & clearingBytes(1) & ShowCursorCode
