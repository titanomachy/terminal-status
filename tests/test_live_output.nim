import std/[options, os, strutils, unittest]

import terminal_status
import terminal_screen

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
    check display.state == displayNew
    check display.effectiveMode == none(LiveMode)

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
