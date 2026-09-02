## A finite dashboard of every pure component renderer.
##
## The example owns its short manual redraw loop because `LiveDisplay` belongs
## to a later phase. Redirected output receives only the completed frame. Use
## `--once` for deterministic documentation and build checks.

import std/[monotimes, os, strutils, times]

import terminal_screen
import terminal_style
import terminal_status

proc usage() =
  echo "Usage: renderers [--ascii] [--no-color] [--once] [--help]"
  echo "  --ascii    use printable-ASCII markers and spinner frames"
  echo "  --no-color remove theme and caller ANSI styling"
  echo "  --once     print only the completed frame"

var
  options = defaultRenderOptions()
  animate = true
  colorRequested = true

for argument in commandLineParams():
  case argument
  of "--ascii":
    options.characters = statusAscii
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
  ansiOutput = animate and detectCapabilities(output = stdout).supportsAnsi
  lastTick = 16
  tickMilliseconds = 120

options.width = 70
options.barWidth = 18
options.showElapsed = true
options.useColor = colorRequested and (ansiOutput or not animate)

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
  spinner.render(options, now) & "\n\n" &
    progress.render(options, now) & "\n\n" &
    tracker.render(options, now)

proc padded(value: string): string =
  var rows: seq[string]
  for row in value.splitLines:
    rows.add padAnsi(row, options.width)
  rows.join("\n")

if ansiOutput:
  stdout.hideCursor(flush = true)

try:
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

    let rendered = frame(now)
    if ansiOutput:
      if tick > 0:
        stdout.write cursorUpCode(rendered.splitLines.len - 1) & cursorColumnCode(1)
      stdout.write rendered.padded
      stdout.flushFile()
      sleep(tickMilliseconds)
    elif tick == lastTick:
      stdout.writeLine rendered

  if ansiOutput:
    stdout.write "\n"
    stdout.flushFile()
finally:
  if ansiOutput:
    stdout.showCursor(flush = true)
