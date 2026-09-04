## Stable IDs and insertion-ordered rows from a finite multi-progress renderer.

import std/[monotimes, os, times]
from std/options import get

import terminal_status

let started = getMonoTime()
var work = initMultiProgress()

let
  downloadId = work.addTask("Download", 4, "files", started)
  verifyId = work.addIndeterminateTask("Verify", now = started)

var renderOptions = defaultRenderOptions()
renderOptions.useColor = false
renderOptions.barWidth = 8

if "--demo" in commandLineParams():
  var liveOptions = defaultLiveDisplayOptions(stdout)
  liveOptions.hideCursor = true

  withLiveDisplay display, liveOptions:
    renderOptions.useColor = display.effectiveMode.get == liveAnsi
    renderOptions.width = 64
    for completed in 0'i64 .. 4'i64:
      let now = started + initDuration(milliseconds = completed * 200)
      work.setCompleted(downloadId, completed, now)
      if completed == 2:
        work.complete(verifyId, now)
      display.update(work.render(renderOptions, now))
      if display.effectiveMode.get == liveAnsi and completed < 4:
        sleep(180)
    if display.effectiveMode.get == liveAnsi:
      sleep(200)
else:
  work.advance(downloadId, 2, started + initDuration(milliseconds = 100))
  work.complete(verifyId, started + initDuration(milliseconds = 200))
  work.complete(downloadId, started + initDuration(milliseconds = 300))

  echo work.render(renderOptions, started + initDuration(milliseconds = 300))

doAssert work.taskIds == @[downloadId, verifyId]

work.removeTask(verifyId)
let publishId = work.addTask("Publish", 1, now = started)
doAssert publishId == TaskId(3) # Removed IDs are never reused.
