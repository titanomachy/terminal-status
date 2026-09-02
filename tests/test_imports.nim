import std/unittest

import terminal_status

suite "public imports":
  test "the facade exports every Phase 1 model":
    check statusPending is StatusState
    check progressDeterminate is ProgressMode
    check $TaskId(42) == "42"

    let spinner = initSpinner("Facade spinner", lineSpinner())
    check spinner.state == statusRunning
    check spinner.style.intervalMs == 100

    let progress = initProgressBar("Facade progress", 2)
    check progress.mode == progressDeterminate

    let tracker = initStepTracker(["Facade step"])
    check tracker.state == statusPending
