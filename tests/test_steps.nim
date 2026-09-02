import std/[monotimes, options, times, unittest]

import terminal_status/steps
import terminal_status/types

let baseTime = getMonoTime()

proc at(milliseconds: int64): MonoTime =
  baseTime + initDuration(milliseconds = milliseconds)

suite "step tracker":
  test "construction validates pending steps and optional title":
    let tracker = initStepTracker(["Fetch", "Build"], "Release")
    check tracker.title == "Release"
    check tracker.state == statusPending
    check tracker.len == 2
    check tracker.currentIndex == none(int)
    check tracker.elapsed(at(100)).inNanoseconds == 0
    for item in tracker.steps:
      check item.state == statusPending
      check item.detail == ""
      check item.startedAt == none(MonoTime)
      check item.finishedAt == none(MonoTime)

    expect ValueError:
      discard initStepTracker(newSeq[string]())
    expect ValueError:
      discard initStepTracker(["Good", "  "])
    expect ValueError:
      discard initStepTracker(["Good"], "\e[31m\e[0m")

  test "start is idempotent and records the first timestamp":
    var tracker = initStepTracker(["Fetch", "Build"])
    tracker.start(at(100))
    tracker.setCurrentDetail("downloading")
    tracker.start(at(900))
    check tracker.state == statusRunning
    check tracker.currentIndex == some(0)
    check tracker.step(0).state == statusRunning
    check tracker.step(0).startedAt == some(at(100))
    check tracker.step(0).detail == "downloading"
    check tracker.elapsed(at(350)).inMilliseconds == 250

  test "advance succeeds each step and the tracker":
    var tracker = initStepTracker(["Fetch", "Build", "Test"], "Release")
    tracker.start(at(0))
    tracker.advance(at(100))
    check tracker.step(0).state == statusSucceeded
    check tracker.step(0).finishedAt == some(at(100))
    check tracker.step(1).state == statusRunning
    check tracker.step(1).startedAt == some(at(100))
    check tracker.currentIndex == some(1)

    tracker.advance(at(250))
    tracker.advance(at(400))
    check tracker.state == statusSucceeded
    check tracker.currentIndex == some(2)
    check tracker.step(2).state == statusSucceeded
    check tracker.step(2).finishedAt == some(at(400))
    check tracker.elapsed(at(900)).inMilliseconds == 400
    expect StatusStateError:
      tracker.advance(at(1000))
    expect StatusStateError:
      tracker.start(at(1000))

  test "advance before start is rejected without mutation":
    var tracker = initStepTracker(["Fetch"])
    expect StatusStateError:
      tracker.advance(at(100))
    check tracker.state == statusPending
    check tracker.currentIndex == none(int)

  test "failure freezes state and supports idempotent detail updates":
    var tracker = initStepTracker(["Fetch", "Build", "Test"])
    tracker.start(at(0))
    tracker.advance(at(100))
    tracker.failCurrent("compiler error", at(250))
    check tracker.state == statusFailed
    check tracker.currentIndex == some(1)
    check tracker.step(0).state == statusSucceeded
    check tracker.step(1).state == statusFailed
    check tracker.step(1).detail == "compiler error"
    check tracker.step(1).finishedAt == some(at(250))
    check tracker.step(2).state == statusPending
    check tracker.elapsed(at(900)).inMilliseconds == 250

    tracker.failCurrent("see build.log", at(900))
    check tracker.step(1).detail == "see build.log"
    check tracker.step(1).finishedAt == some(at(250))
    expect StatusStateError:
      tracker.cancel(at(1000))

  test "failure without detail preserves an existing detail":
    var tracker = initStepTracker(["Build"])
    tracker.start(at(0))
    tracker.setCurrentDetail("compiling")
    tracker.failCurrent(now = at(100))
    check tracker.step(0).detail == "compiling"

  test "cancellation before start cancels every step":
    var tracker = initStepTracker(["Fetch", "Build"])
    tracker.cancel(at(100))
    tracker.cancel(at(900))
    check tracker.state == statusCancelled
    check tracker.currentIndex == none(int)
    check tracker.elapsed(at(900)).inNanoseconds == 0
    for item in tracker.steps:
      check item.state == statusCancelled
      check item.startedAt == none(MonoTime)
      check item.finishedAt == some(at(100))
    expect StatusStateError:
      tracker.setCurrentDetail("cancelled")

  test "cancellation during work preserves completed steps":
    var tracker = initStepTracker(["Fetch", "Build", "Test"])
    tracker.start(at(0))
    tracker.advance(at(100))
    tracker.cancel(at(250))
    check tracker.state == statusCancelled
    check tracker.currentIndex == some(1)
    check tracker.step(0).state == statusSucceeded
    check tracker.step(1).state == statusCancelled
    check tracker.step(2).state == statusCancelled
    check tracker.elapsed(at(900)).inMilliseconds == 250
    tracker.setCurrentDetail("stopped by user")
    check tracker.step(1).detail == "stopped by user"

  test "titles and current details validate without partial mutation":
    var tracker = initStepTracker(["Build"], "Old")
    expect StatusStateError:
      tracker.setCurrentDetail("too early")
    tracker.start(at(0))
    tracker.setTitle("")
    tracker.setCurrentDetail("working")
    check tracker.title == ""
    check tracker.step(0).detail == "working"
    expect ValueError:
      tracker.setTitle("  ")
    expect ValueError:
      tracker.setCurrentDetail("\e[31m\e[0m")
    check tracker.title == ""
    check tracker.step(0).detail == "working"

  test "step queries validate indexes and return detached data":
    let tracker = initStepTracker(["Fetch", "Build"])
    expect ValueError:
      discard tracker.step(-1)
    expect ValueError:
      discard tracker.step(2)

    var allSteps = tracker.steps
    var first = tracker.step(0)
    allSteps[0].label[0] = 'f'
    allSteps.add allSteps[0]
    first.label = "Changed"
    check tracker.len == 2
    check tracker.step(0).label == "Fetch"
