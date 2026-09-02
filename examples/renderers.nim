## A finite dashboard of every pure component renderer.
##
## The example supplies frames from its short manual refresh loop to a
## `LiveDisplay`. Redirected output receives only the completed frame. Use
## `--once` for deterministic documentation and build checks.

import std/[monotimes, os, times]
from std/options import get

import terminal_status

proc usage() =
  echo "Usage: renderers [--ascii] [--no-color] [--once] [--help]"
  echo "  --ascii    use printable-ASCII markers and spinner frames"
  echo "  --no-color remove theme and caller ANSI styling"
  echo "  --once     print only the completed frame"

var
  renderOptions = defaultRenderOptions()
  animate = true
  colorRequested = true

for argument in commandLineParams():
  case argument
  of "--ascii":
    renderOptions.characters = statusAscii
  of "--no-color":
    colorRequested = false
  of "--once":
    animate = false
  of "--help", "-h":
    usage()
    quit(QuitSuccess)
  else:
    stderr.writeLine "unknown option: " & argument
    usage()
    quit(QuitFailure)

let
  started = getMonoTime()
  lastTick = 16
  tickMilliseconds = 120

renderOptions.width = 70
renderOptions.barWidth = 18
renderOptions.showElapsed = true
renderOptions.useColor = colorRequested

var
  spinner = initSpinner("Resolving package graph", arcSpinner(), started)
  progress = initMultiProgress()
  tracker = initStepTracker(
    ["Build package", "Run test suite", "Publish documentation"],
    "Release pipeline")

let
  compileId = progress.addTask("Compile modules", lastTick, "modules", started)
  testsId = progress.addTask("Run tests", lastTick div 2, "groups", started)
  uploadId = progress.addIndeterminateTask("Upload artifacts", now = started)

tracker.start(started)
tracker.setCurrentDetail("debug + release")

proc frame(now: MonoTime): string =
  spinner.render(renderOptions, now) & "\n\n" &
    progress.render(renderOptions, now) & "\n\n" &
    tracker.render(renderOptions, now)

var liveOptions = defaultLiveDisplayOptions(stdout)
liveOptions.hideCursor = true
if not animate:
  liveOptions.mode = livePlain

withLiveDisplay display, liveOptions:
  let ansiOutput = display.effectiveMode.get == liveAnsi
  for tick in 0 .. lastTick:
    let now = started + initDuration(
      milliseconds = int64(tick * tickMilliseconds))
    progress.setCompleted(compileId, int64(tick), now)
    progress.setCompleted(testsId, int64(tick div 2), now)

    if tick == 6:
      tracker.advance(now)
      tracker.setCurrentDetail("all memory managers")
    elif tick == 12:
      tracker.advance(now)
      tracker.setCurrentDetail("build/docs")
    elif tick == lastTick:
      tracker.advance(now)
      progress.complete(uploadId, now)
      spinner.setLabel("Package graph resolved")
      spinner.succeed(now)

    display.update(frame(now))
    if ansiOutput:
      sleep(tickMilliseconds)
