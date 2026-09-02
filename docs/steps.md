# Step tracker model

`terminal_status/steps` models an ordered workflow without performing terminal
I/O. Every tracker and step begins pending. `start` selects step zero, and each
`advance` succeeds the current step before starting the next at the same
monotonic timestamp. Advancing the final step succeeds the tracker.

```nim
import std/[monotimes, times]
import terminal_status

let started = getMonoTime()
var release = initStepTracker(
  ["Build", "Test", "Publish"], title = "Release")

release.start(started)
release.setCurrentDetail("release mode")
release.advance(started + initDuration(milliseconds = 100))
release.advance(started + initDuration(milliseconds = 250))
release.advance(started + initDuration(milliseconds = 400))

doAssert release.state == statusSucceeded
doAssert release.elapsed(
  started + initDuration(seconds = 5)).inMilliseconds == 400
```

`failCurrent` fails only the active step and leaves later steps pending.
Repeating failure preserves timestamps and may attach a revised non-empty
detail. Cancelling before start cancels every step without choosing a current
index; cancelling during work preserves earlier successful steps and cancels
the current and later pending steps.

Titles may be changed in any state. A current step's detail may be changed
while running or after termination, but not before the tracker has a current
step. Queries return detached `StepSnapshot` values, and invalid indexes raise
`ValueError`.

See the finite [`step_tracker.nim`](../examples/step_tracker.nim) example.
