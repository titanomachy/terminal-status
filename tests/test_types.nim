import std/[hashes, monotimes, options, sets, times, unittest]

import terminal_status/types

const
  redOpen = "\e[31m"
  ansiReset = "\e[0m"

let baseTime = getMonoTime()

proc at(milliseconds: int64): MonoTime =
  baseTime + initDuration(milliseconds = milliseconds)

suite "shared status types":
  test "terminal states are classified exactly":
    check not statusPending.isTerminal
    check not statusRunning.isTerminal
    check statusSucceeded.isTerminal
    check statusFailed.isTerminal
    check statusCancelled.isTerminal

  test "task IDs format, compare, and hash by unsigned value":
    let
      first = TaskId(1)
      same = TaskId(1)
      largest = TaskId(uint64.high)
    check first == same
    check first != TaskId(2)
    check $first == "1"
    check $largest == $uint64.high
    check hash(first) == hash(same)

    var ids = initHashSet[TaskId]()
    ids.incl first
    ids.incl same
    ids.incl TaskId(2)
    check ids.len == 2

  test "specialized errors are catchable through StatusError":
    for message in ["state", "unknown", "exhausted"]:
      var caught = false
      try:
        case message
        of "state":
          raise newException(StatusStateError, message)
        of "unknown":
          raise newException(UnknownTaskError, message)
        else:
          raise newException(TaskIdExhaustedError, message)
      except StatusError as error:
        caught = true
        check error.msg == message
      check caught

suite "shared validation":
  test "meaningful text ignores ANSI and Unicode whitespace":
    requireMeaningfulText(redOpen & " active " & ansiReset)
    requireMeaningfulText("\u2003界\u2003")

    expect ValueError:
      requireMeaningfulText("")
    expect ValueError:
      requireMeaningfulText("\t\u2003\n")
    expect ValueError:
      requireMeaningfulText(redOpen & ansiReset)
    expect ValueError:
      requireMeaningfulText("\e]8;;https://example.com\e\\\e]8;;\e\\")
    expect ValueError:
      requireMeaningfulText("\u0301")

  test "optional meaningful text accepts only exactly empty or visible text":
    requireMeaningfulOrEmptyText("", "unit")
    requireMeaningfulOrEmptyText("items", "unit")
    expect ValueError:
      requireMeaningfulOrEmptyText("  ", "unit")

  test "numeric and index guards raise exceptions":
    requirePositive(1, "total")
    requirePositive(1'i64, "total")
    requireNonNegative(0, "amount")
    requireNonNegative(1'i64, "amount")
    requireValidIndex(0, 1)

    expect ValueError:
      requirePositive(0, "interval")
    expect ValueError:
      requirePositive(-1'i64, "total")
    expect ValueError:
      requireNonNegative(-1'i64, "amount")
    expect ValueError:
      requireValidIndex(-1, 1)
    expect ValueError:
      requireValidIndex(1, 1)

  test "frame validation uses terminal cells and rejects unsafe values":
    check validateFrameWidths(["界", "好"]) == 2
    check validateFrameWidths(["-", "\\", "|", "/"], asciiOnly = true) == 1

    expect ValueError:
      discard validateFrameWidths(newSeq[string]())
    expect ValueError:
      discard validateFrameWidths([""])
    expect ValueError:
      discard validateFrameWidths(["-", "界"])
    expect ValueError:
      discard validateFrameWidths(["\n"])
    expect ValueError:
      discard validateFrameWidths(["\t"])
    expect ValueError:
      discard validateFrameWidths(["\u0085"])
    expect ValueError:
      discard validateFrameWidths([redOpen & "x" & ansiReset])
    expect ValueError:
      discard validateFrameWidths(["界"], asciiOnly = true)
    expect ValueError:
      discard validateFrameWidths(["\u0301"])

  test "related sequence lengths must match":
    requireSameLength(2, 2, "spinner frame sets")
    expect ValueError:
      requireSameLength(2, 1, "spinner frame sets")

  test "copyValues returns independent sequence storage":
    var source = @["first", "second"]
    var snapshot = copyValues(source)
    snapshot[0][0] = 'F'
    snapshot.add "third"
    check source == @["first", "second"]

suite "shared transitions and monotonic durations":
  test "pending and running states can terminate":
    for initial in [statusPending, statusRunning]:
      for target in [statusSucceeded, statusFailed, statusCancelled]:
        var
          state = initial
          finishedAt = none(MonoTime)
        transitionToTerminal(state, finishedAt, target, at(250))
        check state == target
        check finishedAt == some(at(250))

  test "repeating a terminal transition preserves its first timestamp":
    var
      state = statusRunning
      finishedAt = none(MonoTime)
    transitionToTerminal(state, finishedAt, statusSucceeded, at(100))
    transitionToTerminal(state, finishedAt, statusSucceeded, at(900))
    check state == statusSucceeded
    check finishedAt == some(at(100))

  test "different and non-terminal targets are rejected without mutation":
    var
      state = statusFailed
      finishedAt = some(at(100))
    expect StatusStateError:
      transitionToTerminal(state, finishedAt, statusCancelled, at(200))
    check state == statusFailed
    check finishedAt == some(at(100))

    expect ValueError:
      transitionToTerminal(state, finishedAt, statusRunning, at(200))
    check state == statusFailed
    check finishedAt == some(at(100))

  test "elapsed duration runs, clamps, and freezes":
    check elapsedDuration(at(100), none(MonoTime), at(350)).inMilliseconds == 250
    check elapsedDuration(at(100), none(MonoTime), at(50)).inNanoseconds == 0
    check elapsedDuration(at(100), some(at(275)), at(900)).inMilliseconds == 175
    check clampedDuration(at(100), at(50)).inNanoseconds == 0

suite "snapshot value contracts":
  test "progress and step snapshots own mutable string values":
    var progress = ProgressTaskSnapshot(
      id: TaskId(7),
      label: "download",
      unit: "files",
      mode: progressDeterminate,
      state: statusRunning,
      completed: 2,
      total: some(4'i64),
      startedAt: at(0),
      finishedAt: none(MonoTime)
    )
    var copiedProgress = progress
    copiedProgress.label[0] = 'D'
    check progress.label == "download"

    var step = StepSnapshot(label: "build", detail: "",
      state: statusPending, startedAt: none(MonoTime),
      finishedAt: none(MonoTime))
    var copiedStep = step
    copiedStep.label[0] = 'B'
    check step.detail == ""
    check step.label == "build"
