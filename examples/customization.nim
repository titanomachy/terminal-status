## A finite marker, theme, and custom-spinner presentation example.
##
## Component renderers arrive in a later Phase 2 slice, so this example applies
## TerminalStyle values directly to preview the same semantic presentation
## contract. Use `--ascii` or `--no-color` to exercise explicit fallbacks.

import std/[monotimes, os, strutils, times]

import terminal_screen
import terminal_style
import terminal_status

proc usage() =
  echo "Usage: customization [--ascii] [--no-color] [--once] [--help]"
  echo "  --ascii    use printable-ASCII markers and spinner frames"
  echo "  --no-color disable theme and caller ANSI styling"
  echo "  --once     print one spinner frame without animation"

var
  options = defaultRenderOptions()
  animate = true

for argument in commandLineParams():
  case argument
  of "--ascii":
    options.characters = statusAscii
  of "--no-color":
    options.useColor = false
  of "--once":
    animate = false
  of "--help", "-h":
    usage()
    quit(QuitSuccess)
  else:
    stderr.writeLine "unknown option: " & argument
    usage()
    quit(QuitFailure)

# Themes are ordinary values. Customizing this copy cannot change defaults.
options.theme.runningStyle = initTerminalStyle(foreground = colorBlue)
options.theme.successStyle = initTerminalStyle(
  foreground = colorMagenta,
  attributes = {taBold}
)

let
  markers = if options.characters == statusAscii:
    asciiStatusMarkers()
  else:
    unicodeStatusMarkers()
  arrows = initSpinnerStyle(
    frames = ["←", "↑", "→", "↓"],
    intervalMs = 90,
    asciiFrames = ["<", "^", ">", "v"]
  )
  started = getMonoTime()
  spinner = initSpinner("Custom arrow preset", arrows, started)
  ansiOutput = animate and
    detectCapabilities(output = stdout).supportsAnsi

proc paint(value: string; textStyle: TerminalStyle): string =
  applyStyle(value, textStyle, enabled = options.useColor)

echo paint("TerminalStatus semantic theme", options.theme.labelStyle)
echo paint(markers.pending, options.theme.pendingStyle), " pending"
echo paint(markers.running, options.theme.runningStyle), " running"
echo paint(markers.succeeded, options.theme.successStyle), " succeeded"
echo paint(markers.failed, options.theme.failureStyle), " failed"
echo paint(markers.cancelled, options.theme.cancelledStyle), " cancelled"
echo markers.barStart,
  paint(markers.barComplete.repeat(8), options.theme.completeBarStyle),
  paint(markers.barRemaining.repeat(4), options.theme.remainingBarStyle),
  markers.barEnd, " ", paint("67%", options.theme.metadataStyle)
echo ""

if ansiOutput:
  stdout.hideCursor(flush = true)

try:
  let frameTotal = if ansiOutput: 16 else: 1
  for tick in 0 ..< frameTotal:
    let now = started + initDuration(
      milliseconds = int64(tick * arrows.intervalMs)
    )
    let frame = spinner.frame(
      asciiOnly = options.characters == statusAscii,
      now = now
    )
    stdout.write(
      (if ansiOutput: "\r" else: "") &
      paint(frame, options.theme.spinnerStyle) & " " & spinner.label
    )
    stdout.flushFile()
    if ansiOutput:
      sleep(arrows.intervalMs)

  if ansiOutput:
    stdout.write "\r"
  else:
    stdout.write "\n"
  stdout.writeLine paint(markers.succeeded, options.theme.successStyle) &
    " Custom presentation ready"
  stdout.flushFile()
  if ansiOutput:
    sleep(arrows.intervalMs)
finally:
  if ansiOutput:
    stdout.showCursor(flush = true)
