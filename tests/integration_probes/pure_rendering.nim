## Proves focused model/render imports neither expose nor require live output.

import std/[monotimes, strutils, times]

import terminal_status/[progress, rendering]

when declared(LiveDisplay) or declared(initLiveDisplay):
  {.error: "focused pure rendering unexpectedly imported live output".}

let baseTime = getMonoTime()
var bar = initProgressBar("Compile", 4, now = baseTime)
bar.advance(3, baseTime + initDuration(seconds = 1))

var options = defaultRenderOptions()
options.useColor = false
options.showRate = false
options.showEta = false

doAssert bar.render(options, baseTime + initDuration(seconds = 1)).contains(
  "Compile")
