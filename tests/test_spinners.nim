import std/[monotimes, options, times, unittest]

import terminal_status/spinners
import terminal_status/types

import ./fixtures

const
  redOpen = "\e[31m"
  ansiReset = "\e[0m"

suite "spinner styles":
  test "invalid primary frame sets and intervals are rejected":
    expect ValueError:
      discard initSpinnerStyle(newSeq[string](), 100)
    expect ValueError:
      discard initSpinnerStyle([""], 100)
    expect ValueError:
      discard initSpinnerStyle(["-", "界"], 100)
    expect ValueError:
      discard initSpinnerStyle(["\n"], 100)
    expect ValueError:
      discard initSpinnerStyle(["\r"], 100)
    expect ValueError:
      discard initSpinnerStyle(["\t"], 100)
    expect ValueError:
      discard initSpinnerStyle([redOpen & "x" & ansiReset], 100)
    expect ValueError:
      discard initSpinnerStyle(["\u0301"], 100)
    expect ValueError:
      discard initSpinnerStyle(["-"], 0)
    expect ValueError:
      discard initSpinnerStyle(["-"], -1)

  test "omitted fallback requires printable ASCII primary frames":
    let style = initSpinnerStyle(["-", "+"], 75)
    check style.frames == @["-", "+"]
    check style.asciiFrames == @["-", "+"]

    expect ValueError:
      discard initSpinnerStyle(["◜", "◝"], 75)

  test "explicit fallback is validated independently":
    let widePrimary = initSpinnerStyle(["界", "好"], 90, ["-", "+"])
    check widePrimary.frames == @["界", "好"]
    check widePrimary.asciiFrames == @["-", "+"]

    expect ValueError:
      discard initSpinnerStyle(["◜", "◝"], 90, ["-"])
    expect ValueError:
      discard initSpinnerStyle(["◜", "◝"], 90, ["-", "界"])
    expect ValueError:
      discard initSpinnerStyle(["◜", "◝"], 90, ["-", "++"])
    expect ValueError:
      discard initSpinnerStyle(["◜", "◝"], 90, ["-", "\n"])

  test "frame getters return independent sequence storage":
    let style = initSpinnerStyle(["-", "+"], 75)
    var preferred = style.frames
    var fallback = style.asciiFrames
    preferred[0][0] = '='
    preferred.add "*"
    fallback[1][0] = 'x'
    fallback.add "/"
    check style.frames == @["-", "+"]
    check style.asciiFrames == @["-", "+"]

  test "built-in presets match the normative values":
    let dots = dotsSpinner()
    check dots.frames == @["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦",
        "⠧", "⠇", "⠏"]
    check dots.asciiFrames == @[".", "o", "O", "@", "*", "@", "O", "o", ".", "+"]
    check dots.intervalMs == 80

    let line = lineSpinner()
    check line.frames == @["─", "\\", "│", "/"]
    check line.asciiFrames == @["-", "\\", "|", "/"]
    check line.intervalMs == 100

    let arc = arcSpinner()
    check arc.frames == @["◜", "◠", "◝", "◞", "◡", "◟"]
    check arc.asciiFrames == @["-", "\\", "|", "/", "-", "\\"]
    check arc.intervalMs == 100

    let pulse = pulseSpinner()
    check pulse.frames == @["·", "•", "●", "•"]
    check pulse.asciiFrames == @[".", "o", "O", "o"]
    check pulse.intervalMs == 120

suite "spinner model":
  test "construction starts a pure running model":
    let spinner = initSpinner("Indexing files", lineSpinner(), at(100))
    check spinner.label == "Indexing files"
    check spinner.state == statusRunning
    check spinner.startedAt == at(100)
    check spinner.finishedAt == none(MonoTime)
    check spinner.elapsed(at(350)).inMilliseconds == 250
    check spinner.style.frames == lineSpinner().frames

    expect ValueError:
      discard initSpinner("Invalid style", default(SpinnerStyle), at(0))

  test "labels are validated and may change after termination":
    expect ValueError:
      discard initSpinner(" \u2003 ", now = at(0))

    var spinner = initSpinner("Starting", now = at(0))
    spinner.setLabel(redOpen & "Working" & ansiReset)
    check spinner.label == redOpen & "Working" & ansiReset

    spinner.succeed(at(100))
    spinner.setLabel("Finished")
    check spinner.label == "Finished"

    expect ValueError:
      spinner.setLabel("\t\n")
    check spinner.label == "Finished"

  test "frame indexes use exact interval boundaries and clamp negatives":
    let spinner = initSpinner("Waiting", lineSpinner(), at(100))
    check spinner.frameIndex(at(50)) == 0
    check spinner.frameIndex(at(100)) == 0
    check spinner.frameIndex(at(199)) == 0
    check spinner.frameIndex(at(200)) == 1
    check spinner.frameIndex(at(499)) == 3
    check spinner.frameIndex(at(500)) == 0
    check spinner.frameIndex(at(900)) == 0

  test "preferred and ASCII frames use the same time-derived index":
    let spinner = initSpinner("Waiting", pulseSpinner(), at(0))
    check spinner.frame(now = at(0)) == "·"
    check spinner.frame(now = at(240)) == "●"
    check spinner.frame(asciiOnly = true, now = at(240)) == "O"

  test "success failure and cancellation record their exact timestamps":
    block:
      var spinner = initSpinner("Success", now = at(0))
      spinner.succeed(at(125))
      check spinner.state == statusSucceeded
      check spinner.finishedAt == some(at(125))
    block:
      var spinner = initSpinner("Failure", now = at(0))
      spinner.fail(at(250))
      check spinner.state == statusFailed
      check spinner.finishedAt == some(at(250))
    block:
      var spinner = initSpinner("Cancellation", now = at(0))
      spinner.cancel(at(375))
      check spinner.state == statusCancelled
      check spinner.finishedAt == some(at(375))

  test "same terminal transition is idempotent and another is rejected":
    var spinner = initSpinner("Work", now = at(0))
    spinner.succeed(at(100))
    spinner.succeed(at(900))
    check spinner.finishedAt == some(at(100))

    expect StatusStateError:
      spinner.fail(at(1000))
    check spinner.state == statusSucceeded
    check spinner.finishedAt == some(at(100))

  test "elapsed duration and frame freeze at the first finish time":
    var spinner = initSpinner("Work", lineSpinner(), at(100))
    spinner.cancel(at(350))
    check spinner.elapsed(at(900)).inMilliseconds == 250
    check spinner.frameIndex(at(900)) == 2
    check spinner.frame(now = at(900)) == "│"
    check spinner.frame(asciiOnly = true, now = at(900)) == "|"
