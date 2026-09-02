# Progress models

`terminal_status/progress` provides determinate and indeterminate progress bars
plus an insertion-ordered `MultiProgress` collection. These are pure in-memory
models: the caller records work with explicit mutations, and a later rendering
phase decides how bars and pulses look.

## Determinate progress

```nim
import std/[monotimes, options, times]
import terminal_status

let started = getMonoTime()
var download = initProgressBar("Download", 10, "files", started)

download.advance(4, started + initDuration(seconds = 2))
doAssert download.fraction.get == 0.4
doAssert download.ratePerSecond(
  started + initDuration(seconds = 2)).get == 2.0
doAssert download.eta(
  started + initDuration(seconds = 2)).get.inSeconds == 3

download.complete(started + initDuration(seconds = 5))
```

`advance` rejects negative increments, integer overflow, and completion beyond
the total before modifying the bar. `setCompleted` is monotonic. Either
operation automatically succeeds the bar when it reaches the exact total;
`complete` fills the remaining total atomically.

Average rate is lifetime `completed / elapsed`, based only on monotonic time.
ETA exists only for a running determinate bar with positive completion and
elapsed time. It is rounded to the nearest millisecond. Terminal elapsed time
and rates use the first finish timestamp, while ETA becomes absent.

## Indeterminate progress

Use `initIndeterminateProgressBar` when no meaningful total exists. Its total,
fraction, rate, and ETA are absent; `advance` and `setCompleted` raise
`StatusStateError`. `complete`, `fail`, and `cancel` still provide the ordinary
lifecycle. The future pure renderer derives pulse movement from the stored
start timestamp, so no model mutation or background timer is needed per frame.

## Multi-progress ownership

```nim
var work = initMultiProgress()
let
  first = work.addTask("Compile", 12, "modules")
  second = work.addIndeterminateTask("Upload")

work.advance(first, 3)
work.complete(second)

doAssert work.taskIds == @[first, second]
```

IDs begin at one, increase monotonically, and are not reused after removal.
All ID-targeted operations raise `UnknownTaskError` before mutation if the task
is absent. `task`, `tasks`, and `taskIds` return detached values or fresh
sequence storage; callers cannot reorder or modify the collection through a
snapshot.

See the finite
[`progress_bar.nim`](../examples/progress_bar.nim),
[`indeterminate_bar.nim`](../examples/indeterminate_bar.nim), and
[`multi_progress.nim`](../examples/multi_progress.nim) examples.
