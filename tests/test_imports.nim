import std/unittest

import terminal_status

suite "public imports":
  test "the facade exports shared contracts and spinner models":
    check statusPending is StatusState
    check progressDeterminate is ProgressMode
    check $TaskId(42) == "42"

    let spinner = initSpinner("Facade spinner", lineSpinner())
    check spinner.state == statusRunning
    check spinner.style.intervalMs == 100
