## A finite determinate-progress render with exact rate and ETA samples.

import std/[monotimes, options, times]

import terminal_status

let started = getMonoTime()
var download = initProgressBar("Download packages", 10, "packages", started)

download.setCompleted(4, started + initDuration(seconds = 2))
let sampledAt = started + initDuration(seconds = 2)
var renderOptions = defaultRenderOptions()
renderOptions.useColor = false
renderOptions.barWidth = 10

echo download.render(renderOptions, sampledAt)

download.complete(started + initDuration(seconds = 4))
doAssert download.state == statusSucceeded
doAssert download.completed == download.total.get
doAssert download.elapsed(sampledAt).inSeconds == 4

echo download.render(renderOptions, download.finishedAt.get)
