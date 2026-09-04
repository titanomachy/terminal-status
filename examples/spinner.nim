## A finite spinner renderer example.
##
## This component-focused example redraws one line directly with
## TerminalScreen's cursor helpers. Applications that need a managed multi-row
## region should use `LiveDisplay`, as shown by `live_status.nim`. Redirected
## output receives only the final spinner snapshot.

import std/[monotimes, os, times]

import terminal_screen
import terminal_status

let started = getMonoTime()
var spinner = initSpinner("Indexing project", arcSpinner(), started)
let ansiOutput = detectCapabilities(output = stdout).supportsAnsi
let interval = spinner.style.intervalMs
var options = defaultRenderOptions()
options.useColor = ansiOutput

if ansiOutput:
  stdout.hideCursor(flush = true)

try:
  if ansiOutput:
    for tick in 0 ..< 18:
      let sampleTime = started +
        initDuration(milliseconds = int64(tick * interval))
      stdout.write "\r" & spinner.render(options, sampleTime)
      stdout.flushFile()
      sleep(interval)

  let finished = started + initDuration(milliseconds = int64(18 * interval))
  spinner.setLabel("Project indexed!")
  spinner.succeed(finished)
  stdout.write (if ansiOutput: "\r" else: "") &
    spinner.render(options, finished) & "\n"
  stdout.flushFile()
  if ansiOutput:
    sleep(interval)
finally:
  if ansiOutput:
    stdout.showCursor(flush = true)
