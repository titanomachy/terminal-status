import std/[monotimes, options, times, unittest]

import terminal_status/progress
import terminal_status/types

import ./fixtures

suite "determinate progress":
  test "construction validates and exposes the initial model":
    let bar = initProgressBar("Download", 10, "files", at(100))
    check bar.label == "Download"
    check bar.unit == "files"
    check bar.mode == progressDeterminate
    check bar.state == statusRunning
    check bar.completed == 0
    check bar.total == some(10'i64)
    check bar.startedAt == at(100)
    check bar.finishedAt == none(MonoTime)
    check bar.fraction == some(0.0)

    expect ValueError:
      discard initProgressBar("", 10, now = at(0))
    expect ValueError:
      discard initProgressBar("Download", 0, now = at(0))
    expect ValueError:
      discard initProgressBar("Download", -1, now = at(0))
    expect ValueError:
      discard initProgressBar("Download", 10, "  ", at(0))

  test "advance accepts zero and completes exactly":
    var bar = initProgressBar("Download", 3, now = at(0))
    bar.advance(0, at(100))
    check bar.completed == 0
    check bar.state == statusRunning
    check bar.finishedAt == none(MonoTime)

    bar.advance(now = at(200))
    check bar.completed == 1
    check bar.fraction.get == 1.0 / 3.0
    bar.advance(2, at(300))
    check bar.completed == 3
    check bar.fraction == some(1.0)
    check bar.state == statusSucceeded
    check bar.finishedAt == some(at(300))

  test "setCompleted is monotonic and completes at the total":
    var bar = initProgressBar("Compile", 10, now = at(0))
    bar.setCompleted(4, at(100))
    bar.setCompleted(4, at(200))
    check bar.completed == 4
    check bar.state == statusRunning
    bar.setCompleted(10, at(300))
    check bar.completed == 10
    check bar.state == statusSucceeded
    check bar.finishedAt == some(at(300))

  test "invalid numeric changes never partially mutate":
    var bar = initProgressBar("Compile", int64.high, now = at(0))
    bar.setCompleted(int64.high - 1, at(100))
    let before = (bar.completed, bar.state, bar.finishedAt)

    expect ValueError:
      bar.advance(2, at(200))
    check (bar.completed, bar.state, bar.finishedAt) == before

    expect ValueError:
      bar.advance(-1, at(200))
    check (bar.completed, bar.state, bar.finishedAt) == before

    expect ValueError:
      bar.setCompleted(int64.high - 2, at(200))
    check (bar.completed, bar.state, bar.finishedAt) == before

    var bounded = initProgressBar("Bounded", 10, now = at(0))
    bounded.setCompleted(8, at(100))
    let boundedBefore = (bounded.completed, bounded.state, bounded.finishedAt)
    expect ValueError:
      bounded.advance(3, at(200))
    check (bounded.completed, bounded.state, bounded.finishedAt) == boundedBefore
    expect ValueError:
      bounded.setCompleted(11, at(200))
    check (bounded.completed, bounded.state, bounded.finishedAt) == boundedBefore

  test "explicit terminal operations obey transition rules":
    block:
      var bar = initProgressBar("Complete", 10, now = at(0))
      bar.setCompleted(3, at(50))
      bar.complete(at(100))
      bar.complete(at(900))
      check bar.completed == 10
      check bar.state == statusSucceeded
      check bar.finishedAt == some(at(100))
      expect StatusStateError:
        bar.fail(at(1000))
    block:
      var bar = initProgressBar("Fail", 10, now = at(0))
      bar.advance(2, at(50))
      bar.fail(at(100))
      bar.fail(at(900))
      check bar.completed == 2
      check bar.finishedAt == some(at(100))
      expect StatusStateError:
        bar.cancel(at(1000))
    block:
      var bar = initProgressBar("Cancel", 10, now = at(0))
      bar.cancel(at(100))
      bar.cancel(at(900))
      check bar.state == statusCancelled
      check bar.finishedAt == some(at(100))

  test "terminal bars reject all numeric mutation but accept text changes":
    var bar = initProgressBar("Old", 10, "items", at(0))
    bar.cancel(at(100))
    for operation in 0 .. 2:
      expect StatusStateError:
        case operation
        of 0: bar.advance(0, at(200))
        of 1: bar.setCompleted(0, at(200))
        else: bar.complete(at(200))
    check bar.completed == 0
    check bar.finishedAt == some(at(100))

    bar.setLabel("Final")
    bar.setUnit("")
    check bar.label == "Final"
    check bar.unit == ""
    expect ValueError:
      bar.setLabel("\e[31m\e[0m")
    expect ValueError:
      bar.setUnit("  ")

  test "elapsed rate and ETA use exact monotonic time":
    var bar = initProgressBar("Download", 10, now = at(100))
    check bar.ratePerSecond(at(100)).isNone
    check bar.eta(at(100)).isNone

    bar.setCompleted(4, at(2100))
    check bar.elapsed(at(2100)).inMilliseconds == 2000
    check bar.ratePerSecond(at(2100)) == some(2.0)
    check bar.eta(at(2100)).get.inMilliseconds == 3000

    bar.fail(at(2600))
    check bar.elapsed(at(9000)).inMilliseconds == 2500
    check bar.ratePerSecond(at(9000)) == some(1.6)
    check bar.eta(at(9000)).isNone

  test "rates and ETAs remain finite for extreme legal counts":
    var bar = initProgressBar("Large", int64.high, now = at(0))
    bar.setCompleted(int64.high - 1, at(1))
    let rate = bar.ratePerSecond(at(1))
    check rate.isSome
    check rate.get > 0.0
    check rate.get < Inf
    let estimate = bar.eta(at(1))
    check estimate.isSome
    check estimate.get.inNanoseconds >= 0

suite "indeterminate progress":
  test "construction has no numeric metrics":
    let bar = initIndeterminateProgressBar("Waiting", now = at(0))
    check bar.label == "Waiting"
    check bar.unit == ""
    check bar.mode == progressIndeterminate
    check bar.state == statusRunning
    check bar.completed == 0
    check bar.total == none(int64)
    check bar.startedAt == at(0)
    check bar.finishedAt == none(MonoTime)
    check bar.elapsed(at(250)).inMilliseconds == 250
    check bar.fraction == none(float)
    check bar.ratePerSecond(at(1000)) == none(float)
    check bar.eta(at(1000)) == none(Duration)

    expect ValueError:
      discard initIndeterminateProgressBar("  ", now = at(0))
    expect ValueError:
      discard initIndeterminateProgressBar("Waiting", "\e[31m\e[0m", at(0))

  test "numeric mutation is rejected and lifecycle operations remain valid":
    var bar = initIndeterminateProgressBar("Waiting", "requests", at(0))
    expect StatusStateError:
      bar.advance(now = at(100))
    expect StatusStateError:
      bar.setCompleted(0, at(100))
    check bar.completed == 0
    check bar.state == statusRunning

    bar.complete(at(250))
    bar.complete(at(900))
    check bar.completed == 0
    check bar.state == statusSucceeded
    check bar.finishedAt == some(at(250))

  test "failure cancellation and post-terminal text changes work":
    block:
      var bar = initIndeterminateProgressBar("Wait", now = at(0))
      bar.fail(at(100))
      bar.fail(at(900))
      check bar.state == statusFailed
      check bar.finishedAt == some(at(100))
      check bar.elapsed(at(2_000)).inMilliseconds == 100
      expect StatusStateError:
        bar.cancel(at(1_000))
    block:
      var bar = initIndeterminateProgressBar("Wait", now = at(0))
      bar.cancel(at(100))
      bar.cancel(at(900))
      bar.setLabel("Stopped")
      bar.setUnit("operations")
      check bar.state == statusCancelled
      check bar.finishedAt == some(at(100))
      check bar.label == "Stopped"
      check bar.unit == "operations"
      expect StatusStateError:
        bar.complete(at(1_000))
