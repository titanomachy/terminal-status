## A finite indeterminate-progress lifecycle.
##
## Indeterminate motion is derived by the Phase 2 renderer from the model's
## monotonic start time. The model itself has no numeric completion to mutate.

import std/[monotimes, options, times]

import terminal_status

let started = getMonoTime()
var discovery = initIndeterminateProgressBar(
  "Discover mirrors", "mirrors", started)

doAssert discovery.mode == progressIndeterminate
doAssert discovery.total == none(int64)
doAssert discovery.fraction == none(float)
doAssert discovery.ratePerSecond(started + initDuration(seconds = 1)).isNone

discovery.setLabel("Mirrors discovered")
discovery.complete(started + initDuration(milliseconds = 750))

doAssert discovery.completed == 0
doAssert discovery.elapsed(started + initDuration(seconds = 5)).inMilliseconds == 750
echo discovery.label, ": ", discovery.state
