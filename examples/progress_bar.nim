## A finite determinate-progress render with exact rate and ETA samples.

import std/[monotimes, options, os, times]

import terminal_status

let started = getMonoTime()
var download = initProgressBar("Download packages", 10, "packages", started)

if "--demo" in commandLineParams():
  var liveOptions = defaultLiveDisplayOptions(stdout)
  liveOptions.hideCursor = true

  withLiveDisplay display, liveOptions:
    var renderOptions = defaultRenderOptions()
    renderOptions.useColor = display.effectiveMode.get == liveAnsi
    renderOptions.barWidth = 10
    renderOptions.width = 78

    for completed in 0'i64 .. 10'i64:
      let now = started + initDuration(milliseconds = completed * 200)
      download.setCompleted(completed, now)
      display.update(download.render(renderOptions, now))
      if display.effectiveMode.get == liveAnsi and completed < 10:
        sleep(90)
    if display.effectiveMode.get == liveAnsi:
      sleep(200)

  doAssert download.state == statusSucceeded
  quit(QuitSuccess)

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
