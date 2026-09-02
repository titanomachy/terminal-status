## Shared states, identifiers, snapshots, and timing contracts.
##
## The shared types are plain in-memory values. This example uses explicit
## monotonic timestamps, so it is finite and deterministic without sleeping.

import std/[monotimes, options, tables, times]

import terminal_status/types

let started = getMonoTime()
let taskId = TaskId(42)

var labels = initTable[TaskId, string]()
labels[taskId] = "download"
doAssert labels[TaskId(42)] == "download"
doAssert $taskId == "42"

let progress = ProgressTaskSnapshot(
  id: taskId,
  label: "Download packages",
  unit: "packages",
  mode: progressDeterminate,
  state: statusRunning,
  completed: 3,
  total: some(10'i64),
  startedAt: started,
  finishedAt: none(MonoTime)
)

var detached = copyValues([progress])
detached[0].label = "Changed snapshot"
doAssert progress.label == "Download packages"

var
  state = statusRunning
  finishedAt = none(MonoTime)
let completedAt = started + initDuration(milliseconds = 250)

transitionToTerminal(state, finishedAt, statusSucceeded, completedAt)
transitionToTerminal(state, finishedAt, statusSucceeded,
  completedAt + initDuration(seconds = 1))

doAssert state.isTerminal
doAssert finishedAt == some(completedAt)
doAssert elapsedDuration(started, finishedAt,
  completedAt + initDuration(seconds = 2)).inMilliseconds == 250

try:
  transitionToTerminal(state, finishedAt, statusFailed, completedAt)
except StatusStateError as error:
  echo "rejected transition: ", error.msg

let step = StepSnapshot(
  label: "Verify archive",
  detail: "checksum matched",
  state: statusSucceeded,
  startedAt: some(started),
  finishedAt: some(completedAt)
)

echo "task ", progress.id, ": ", progress.completed, "/", progress.total.get,
  " ", progress.unit
echo step.label, ": ", step.state
echo "elapsed: ", elapsedDuration(started, finishedAt, completedAt).inMilliseconds,
  " ms"
