## Stable IDs and insertion-order snapshots from a finite multi-progress model.

import std/[monotimes, times]

import terminal_status

let started = getMonoTime()
var work = initMultiProgress()

let
  downloadId = work.addTask("Download", 4, "files", started)
  verifyId = work.addIndeterminateTask("Verify", now = started)

work.advance(downloadId, 2, started + initDuration(milliseconds = 100))
work.complete(verifyId, started + initDuration(milliseconds = 200))
work.complete(downloadId, started + initDuration(milliseconds = 300))

doAssert work.taskIds == @[downloadId, verifyId]
for task in work.tasks:
  echo "#", task.id, " ", task.label, ": ", task.state

work.removeTask(verifyId)
let publishId = work.addTask("Publish", 1, now = started)
doAssert publishId == TaskId(3) # Removed IDs are never reused.
