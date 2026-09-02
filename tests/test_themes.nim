import std/unittest

import terminal_style
import terminal_status/rendering
import terminal_status/themes

proc markerValues(markers: StatusMarkers): seq[string] =
  @[
    markers.pending,
    markers.running,
    markers.succeeded,
    markers.failed,
    markers.cancelled,
    markers.barStart,
    markers.barEnd,
    markers.barComplete,
    markers.barRemaining
  ]

suite "status marker presets":
  test "Unicode markers match the normative preset":
    let markers = unicodeStatusMarkers()
    check markers.pending == "○"
    check markers.running == "●"
    check markers.succeeded == "✓"
    check markers.failed == "✗"
    check markers.cancelled == "–"
    check markers.barStart == "["
    check markers.barEnd == "]"
    check markers.barComplete == "█"
    check markers.barRemaining == "░"
    check markers.detailSeparator == " — "

  test "ASCII markers match the normative preset":
    let markers = asciiStatusMarkers()
    check markers.pending == "o"
    check markers.running == ">"
    check markers.succeeded == "+"
    check markers.failed == "x"
    check markers.cancelled == "-"
    check markers.barStart == "["
    check markers.barEnd == "]"
    check markers.barComplete == "#"
    check markers.barRemaining == "-"
    check markers.detailSeparator == " - "

  test "both presets provide cell-equivalent semantic markers":
    let
      unicodeMarkers = unicodeStatusMarkers()
      asciiMarkers = asciiStatusMarkers()

    check unicodeMarkers.markerValues.len == asciiMarkers.markerValues.len
    for marker in unicodeMarkers.markerValues:
      check displayWidth(marker) == 1
    for marker in asciiMarkers.markerValues:
      check marker.len == 1
      check marker[0] in ' ' .. '~'
      check displayWidth(marker) == 1
    check displayWidth(unicodeMarkers.detailSeparator) ==
      displayWidth(asciiMarkers.detailSeparator)

  test "preset calls return independent values":
    var changed = unicodeStatusMarkers()
    changed.succeeded = "!"
    check unicodeStatusMarkers().succeeded == "✓"

suite "default status theme":
  test "semantic colors and subdued attributes match the specification":
    let theme = defaultStatusTheme()
    check theme.spinnerStyle == initTerminalStyle(foreground = colorCyan)
    check theme.runningStyle == initTerminalStyle(foreground = colorCyan)
    check theme.successStyle == initTerminalStyle(foreground = colorGreen)
    check theme.failureStyle == initTerminalStyle(foreground = colorRed)
    check theme.cancelledStyle == initTerminalStyle(foreground = colorYellow)
    check theme.labelStyle == initTerminalStyle()
    check theme.completeBarStyle == initTerminalStyle(foreground = colorGreen)

    let subdued = initTerminalStyle(
      foreground = colorBrightBlack,
      attributes = {taDim}
    )
    check theme.pendingStyle == subdued
    check theme.detailStyle == subdued
    check theme.remainingBarStyle == subdued
    check theme.metadataStyle == subdued

  test "theme construction and styling are pure value operations":
    var changed = defaultStatusTheme()
    changed.successStyle = initTerminalStyle(foreground = colorMagenta)
    check defaultStatusTheme().successStyle ==
      initTerminalStyle(foreground = colorGreen)

    let styledValue = applyStyle("done", defaultStatusTheme().successStyle)
    check styledValue.contains('\e')
    check stripAnsi(styledValue) == "done"

suite "render options foundation":
  test "defaults match the pure rendering contract":
    let options = defaultRenderOptions()
    check options.width == 0
    check options.barWidth == 20
    check options.characters == statusUnicode
    check options.useColor
    check options.showCount
    check not options.showElapsed
    check options.showRate
    check options.showEta
    check options.indeterminateIntervalMs == 100
    check options.theme == defaultStatusTheme()

  test "color selection is explicit and TerminalStyle removes caller ANSI":
    var options = defaultRenderOptions()
    options.useColor = false
    let callerStyled =
      "\e]8;;https://example.com\a\e[1;35mcustom\e[0m\e]8;;\a"
    let output = applyStyle(
      callerStyled,
      options.theme.successStyle,
      enabled = options.useColor
    )
    check output == "custom"
    check not output.contains('\e')

  test "options and themes can be customized without global mutation":
    var options = defaultRenderOptions()
    options.characters = statusAscii
    options.theme.runningStyle = initTerminalStyle(foreground = colorBlue)
    options.showRate = false

    let defaults = defaultRenderOptions()
    check defaults.characters == statusUnicode
    check defaults.theme.runningStyle ==
      initTerminalStyle(foreground = colorCyan)
    check defaults.showRate
