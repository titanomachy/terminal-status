import std/[options, os, unittest]

import terminal_status

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
