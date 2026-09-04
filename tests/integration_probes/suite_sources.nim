## Compiled by test_suite_integration.nim with explicit sibling source paths.

import std/[monotimes, strutils, times]

import terminal_screen
import terminal_style
import terminal_status

let baseTime = getMonoTime()
var bar = initProgressBar(
  applyStyle("界 build", initTerminalStyle(foreground = colorCyan)),
  2,
  now = baseTime)
bar.advance(1, baseTime + initDuration(seconds = 1))

var options = defaultRenderOptions()
options.width = 80
options.useColor = true
options.showRate = false
options.showEta = false

let frame = bar.render(options, baseTime + initDuration(seconds = 1))
doAssert displayWidth(frame) <= options.width
doAssert stripAnsi(frame).contains("界 build")
doAssert cursorUpCode(2) == "\e[2A"
