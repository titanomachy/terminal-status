## Development-only string-boundary composition with sibling TerminalTable.

import std/[monotimes, strutils, times]

import terminal_table
import terminal_status/[progress, rendering]

let baseTime = getMonoTime()
var bar = initProgressBar("Table cell", 4, now = baseTime)
bar.advance(2, baseTime + initDuration(seconds = 1))

var options = defaultRenderOptions()
options.width = 26
options.useColor = false
options.showRate = false
options.showEta = false
let frame = bar.render(options, baseTime + initDuration(seconds = 1))

var table = initTable(["Status"])
table.addRow(frame)
doAssert table.render().contains(frame)

