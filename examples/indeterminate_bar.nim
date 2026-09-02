## A finite indeterminate-progress render at deterministic pulse positions.

import std/[monotimes, options, times]

import terminal_status

let started = getMonoTime()
var discovery = initIndeterminateProgressBar(
  "Discover mirrors", "mirrors", started)

doAssert discovery.mode == progressIndeterminate
doAssert discovery.total == none(int64)
doAssert discovery.fraction == none(float)
doAssert discovery.ratePerSecond(started + initDuration(seconds = 1)).isNone

var renderOptions = defaultRenderOptions()
renderOptions.useColor = false
renderOptions.barWidth = 8
echo discovery.render(renderOptions, started)
echo discovery.render(renderOptions, started + initDuration(milliseconds = 500))

discovery.setLabel("Mirrors discovered")
discovery.complete(started + initDuration(milliseconds = 750))

doAssert discovery.completed == 0
doAssert discovery.elapsed(started + initDuration(seconds = 5)).inMilliseconds == 750
echo discovery.render(renderOptions, started + initDuration(seconds = 5))
