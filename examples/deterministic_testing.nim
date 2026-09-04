## Test time-derived progress without sleeping or consulting wall-clock time.

import std/[monotimes, options, times]

import terminal_status

let base = getMonoTime()

proc at(milliseconds: int64): MonoTime =
  base + initDuration(milliseconds = milliseconds)

var compile = initProgressBar("Compile modules", 10, "modules", at(0))
compile.setCompleted(4, at(2_000))

doAssert compile.elapsed(at(2_000)).inMilliseconds == 2_000
doAssert compile.ratePerSecond(at(2_000)) == some(2.0)
doAssert compile.eta(at(2_000)).get.inMilliseconds == 3_000

var renderOptions = defaultRenderOptions()
renderOptions.characters = statusAscii
renderOptions.useColor = false
renderOptions.barWidth = 10

doAssert compile.render(renderOptions, at(2_000)) ==
  "> Compile modules [####------]  40% 4/10 modules 2.0 modules/s ETA 3s"

echo compile.render(renderOptions, at(2_000))
