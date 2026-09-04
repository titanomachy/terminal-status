## A finite ordered step-tracker render with explicit timestamps.

import std/[monotimes, os, times]
from std/options import get

import terminal_status

let started = getMonoTime()
var release = initStepTracker(
  ["Build package", "Run tests", "Publish archive"],
  title = "Release")

var renderOptions = defaultRenderOptions()
renderOptions.useColor = false

if "--demo" in commandLineParams():
  var liveOptions = defaultLiveDisplayOptions(stdout)
  liveOptions.hideCursor = true

  withLiveDisplay display, liveOptions:
    renderOptions.useColor = display.effectiveMode.get == liveAnsi
    release.start(started)
    release.setCurrentDetail("release mode")
    display.update(release.render(renderOptions, started))
    if display.effectiveMode.get == liveAnsi:
      sleep(350)

    release.advance(started + initDuration(milliseconds = 100))
    display.update(release.render(renderOptions,
      started + initDuration(milliseconds = 100)))
    if display.effectiveMode.get == liveAnsi:
      sleep(350)

    release.advance(started + initDuration(milliseconds = 250))
    release.setCurrentDetail("registry upload")
    display.update(release.render(renderOptions,
      started + initDuration(milliseconds = 250)))
    if display.effectiveMode.get == liveAnsi:
      sleep(350)

    release.advance(started + initDuration(milliseconds = 400))
    display.update(release.render(renderOptions,
      started + initDuration(milliseconds = 400)))
    if display.effectiveMode.get == liveAnsi:
      sleep(200)
else:
  release.start(started)
  release.setCurrentDetail("release mode")
  release.advance(started + initDuration(milliseconds = 100))
  release.advance(started + initDuration(milliseconds = 250))
  release.setCurrentDetail("registry upload")
  release.advance(started + initDuration(milliseconds = 400))

  echo release.render(renderOptions, started + initDuration(seconds = 2))

doAssert release.state == statusSucceeded
doAssert release.currentIndex.get == release.len - 1
doAssert release.elapsed(started + initDuration(seconds = 2)).inMilliseconds == 400
