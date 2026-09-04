## Embeds one pure TerminalStatus string in sibling layout and table packages.
##
## Run from the suite workspace with:
## nim c -r --path:src --path:../terminal-styles/src \
##   --path:../terminal-layout/src --path:../terminal-tables/src \
##   examples/interoperability.nim

import std/[monotimes, times]

import terminal_layout
import terminal_table
import terminal_status/[progress, rendering]

let baseTime = getMonoTime()
var bar = initProgressBar("Compile suite", 4, "modules", now = baseTime)
bar.advance(3, baseTime + initDuration(seconds = 1))

var options = defaultRenderOptions()
options.width = 32
options.barWidth = 8
options.useColor = false
options.showCount = false
options.showRate = false
options.showEta = false
let status = bar.render(options, baseTime + initDuration(seconds = 1))

var table = initTable(["Current status"])
table.addRow(status)

when isMainModule:
  echo initPanel(status, width = 36, useColor = false).render()
  echo ""
  echo table.render()
