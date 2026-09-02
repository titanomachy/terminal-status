## A finite determinate-progress model with exact rate and ETA samples.
##
## Rendering is introduced in Phase 2; this example prints model queries so it
## remains deterministic and demonstrates the Phase 1 API directly.

import std/[monotimes, options, times]

import terminal_status

let started = getMonoTime()
var download = initProgressBar("Download packages", 10, "packages", started)

download.setCompleted(4, started + initDuration(seconds = 2))
let sampledAt = started + initDuration(seconds = 2)

echo download.label, ": ", download.completed, "/", download.total.get,
  " ", download.unit
echo "fraction: ", download.fraction.get
echo "average rate: ", download.ratePerSecond(sampledAt).get, " packages/s"
echo "ETA: ", download.eta(sampledAt).get.inSeconds, " s"

download.complete(started + initDuration(seconds = 4))
doAssert download.state == statusSucceeded
doAssert download.completed == download.total.get
doAssert download.elapsed(sampledAt).inSeconds == 4

echo "finished: ", download.state
