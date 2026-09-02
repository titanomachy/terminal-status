import std/unittest

import terminal_status

suite "public imports":
  test "the facade exports shared contracts":
    check statusPending is StatusState
    check progressDeterminate is ProgressMode
    check $TaskId(42) == "42"
