## A finite, model-only spinner example.
##
## This example redraws one line itself because the LiveDisplay output layer is
## introduced in a later implementation phase. It uses TerminalScreen only for
## terminal detection and exception-safe cursor ownership. Redirected output
## receives the final snapshot without animation-frame flooding.

import std/[monotimes, os, times]

import terminal_screen
import terminal_status

let started = getMonoTime()
var spinner = initSpinner("Indexing project", arcSpinner(), started)
let ansiOutput = detectCapabilities(output = stdout).supportsAnsi
let interval = spinner.style.intervalMs

if ansiOutput:
  stdout.hideCursor(flush = true)

try:
  if ansiOutput:
    for tick in 0 ..< 18:
      let sampleTime = started +
        initDuration(milliseconds = int64(tick * interval))
      stdout.write "\r" & spinner.frame(now = sampleTime) & " " & spinner.label
      stdout.flushFile()
      sleep(interval)

  spinner.setLabel("Project indexed!")
  spinner.succeed(started + initDuration(milliseconds = int64(18 * interval)))
  stdout.write (if ansiOutput: "\r" else: "") & "✓ " & spinner.label & "\n"
  stdout.flushFile()
  if ansiOutput:
    sleep(interval)
finally:
  if ansiOutput:
    stdout.showCursor(flush = true)
