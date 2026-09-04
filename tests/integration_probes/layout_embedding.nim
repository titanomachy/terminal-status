## Development-only string-boundary composition with sibling TerminalLayout.

import std/[monotimes, strutils, times]

import terminal_layout
import terminal_status/[progress, rendering]

let baseTime = getMonoTime()
var bar = initProgressBar("Layout child", 4, now = baseTime)
bar.advance(2, baseTime + initDuration(seconds = 1))

var options = defaultRenderOptions()
options.width = 26
options.useColor = false
options.showRate = false
options.showEta = false
let frame = bar.render(options, baseTime + initDuration(seconds = 1))

let composed = initPanel(frame, width = 30, useColor = false).render()
doAssert composed.contains(frame)

