## A finite manual-refresh live display driven by a caller-owned work loop.
##
## TerminalStatus does not create a timer or worker. The application mutates
## its model, renders one complete frame with a shared monotonic timestamp, and
## explicitly submits that frame. `withLiveDisplay` closes the borrowed output
## stream safely if the loop raises a catchable exception.

import std/[monotimes, options, os, times]

import terminal_status

const
  TotalFiles = 8'i64
  FrameIntervalMs = 90

let started = getMonoTime()
var scan = initProgressBar("Scan workspace", TotalFiles, "files", started)

var liveOptions = defaultLiveDisplayOptions(stdout)
liveOptions.hideCursor = true

withLiveDisplay display, liveOptions:
  var renderOptions = defaultRenderOptions()
  renderOptions.useColor = display.effectiveMode.get == liveAnsi
  renderOptions.barWidth = 16

  for completed in 0'i64 .. TotalFiles:
    let now = started + initDuration(
      milliseconds = completed * FrameIntervalMs)
    scan.setCompleted(completed, now)
    display.update(scan.render(renderOptions, now))

    # Sleeping is only presentation pacing for an interactive terminal. A
    # redirected run remains immediate and emits only the final frame.
    if display.effectiveMode.get == liveAnsi and completed < TotalFiles:
      sleep(FrameIntervalMs)
