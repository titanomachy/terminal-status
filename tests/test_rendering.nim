import std/[monotimes, options, strutils, times, unittest]

import terminal_style
import terminal_status

let baseTime = getMonoTime()

proc at(milliseconds: int64): MonoTime =
  baseTime + initDuration(milliseconds = milliseconds)

proc plainOptions(barWidth = 10): RenderOptions =
  result = defaultRenderOptions()
  result.characters = statusAscii
  result.useColor = false
  result.barWidth = barWidth

proc unstyledOptions(): RenderOptions =
  result = defaultRenderOptions()
  result.theme = StatusTheme()

proc checkRowsBounded(value: string; width: int) =
  for row in value.splitLines:
    check displayWidth(row) <= width

suite "pure component renderers":
  test "every renderer validates every option before rendering":
    let
      spinner = initSpinner("Spin", now = at(0))
      bar = initProgressBar("Work", 10, now = at(0))
      multi = initMultiProgress()
      tracker = initStepTracker(["Step"])

    for invalidField in 0 .. 2:
      var options = plainOptions()
      case invalidField
      of 0: options.width = -1
      of 1: options.barWidth = 0
      else: options.indeterminateIntervalMs = 0
      expect ValueError:
        discard spinner.render(options, at(0))
      expect ValueError:
        discard bar.render(options, at(0))
      expect ValueError:
        discard multi.render(options, at(0))
      expect ValueError:
        discard tracker.render(options, at(0))

  test "spinner frames and terminal markers have exact plain forms":
    var spinner = initSpinner("Fetching packages", dotsSpinner(), at(0))
    var options = plainOptions()
    options.characters = statusUnicode

    check spinner.render(options, at(0)) == "⠋ Fetching packages"
    check spinner.render(options, at(80)) == "⠙ Fetching packages"
    spinner.succeed(at(160))
    check spinner.render(options, at(900)) == "✓ Fetching packages"

    var failed = initSpinner("Fetching packages", now = at(0))
    failed.fail(at(10))
    options.characters = statusAscii
    check failed.render(options, at(900)) == "x Fetching packages"
    check '\n' notin failed.render(options, at(900))
    check '\r' notin failed.render(options, at(900))

  test "determinate progress formats percentage count rate ETA and elapsed":
    var bar = initProgressBar("Downloading", 100, "MB", at(0))
    bar.setCompleted(50, at(2_000))
    var options = plainOptions()
    check bar.render(options, at(2_000)) ==
      "> Downloading [#####-----]  50% 50/100 MB 25.0 MB/s ETA 2s"

    options.showElapsed = true
    check bar.render(options, at(2_000)).endsWith("elapsed 2s")
    bar.complete(at(4_000))
    check bar.render(options, at(99_000)) ==
      "+ Downloading [##########] 100% 100/100 MB 25.0 MB/s elapsed 4s"

  test "percentage uses floor at representative boundaries":
    var options = plainOptions(4)
    options.showCount = false
    options.showRate = false
    options.showEta = false
    for item in [(0'i64, "  0%"), (7'i64, "  7%"),
                 (50'i64, " 50%"), (99'i64, " 99%")]:
      var bar = initProgressBar("Work", 100, now = at(0))
      bar.setCompleted(item[0], at(1_000))
      check bar.render(options, at(1_000)).endsWith(item[1])

    var complete = initProgressBar("Work", 100, now = at(0))
    complete.complete(at(1_000))
    check complete.render(options, at(1_000)).endsWith("100%")

  test "duration formatting crosses every specified boundary":
    var options = plainOptions(4)
    options.showCount = false
    options.showRate = false
    options.showEta = false
    options.showElapsed = true
    for item in [(0'i64, "0s"), (59'i64, "59s"),
                 (60'i64, "1m 00s"),
                 (3_599'i64, "59m 59s"),
                 (3_600'i64, "1h 00m 00s")]:
      let bar = initProgressBar("Work", 10, now = at(0))
      check bar.render(options, at(item[0] * 1_000)).endsWith(
        "elapsed " & item[1])

    var etaBar = initProgressBar("Work", 2, now = at(0))
    etaBar.advance(1, at(1_500))
    options.showElapsed = false
    options.showEta = true
    check etaBar.render(options, at(1_500)).endsWith("ETA 2s")

  test "count and rate omit an empty unit cleanly":
    var bar = initProgressBar("Items", 10, now = at(0))
    bar.advance(5, at(2_000))
    check bar.render(plainOptions(), at(2_000)).endsWith(
      "5/10 2.5/s ETA 2s")

  test "indeterminate pulse bounces and terminal forms freeze":
    var bar = initIndeterminateProgressBar("Waiting", now = at(0))
    var options = plainOptions(5)
    check bar.render(options, at(0)) == "> Waiting [###--]"
    check bar.render(options, at(200)) == "> Waiting [--###]"
    check bar.render(options, at(400)) == "> Waiting [###--]"

    bar.fail(at(200))
    check bar.render(options, at(9_000)) == "x Waiting [--###]"

    var complete = initIndeterminateProgressBar("Waiting", now = at(0))
    complete.complete(at(100))
    check complete.render(options, at(9_000)) == "+ Waiting [#####]"

    let oneCell = initIndeterminateProgressBar("One", now = at(0))
    options.barWidth = 1
    check oneCell.render(options, at(9_000)) == "> One [#]"

  test "multi-progress preserves insertion order and has no final newline":
    var multi = initMultiProgress()
    let
      first = multi.addTask("Compile", 4, now = at(0))
      second = multi.addIndeterminateTask("Upload", now = at(0))
    multi.advance(first, 2, at(1_000))
    var options = plainOptions(4)
    options.showRate = false
    options.showEta = false

    check multi.render(options, at(0)) ==
      "> Compile [##--]  50% 2/4\n> Upload [###-]"
    check not multi.render(options, at(0)).endsWith("\n")
    multi.removeTask(second)
    check multi.render(options, at(0)).startsWith("> Compile")
    var empty = initMultiProgress()
    check empty.render(options, at(0)) == ""

  test "step tracker renders title details pulse and semantic states":
    var tracker = initStepTracker(["Fetch", "Build", "Publish"], "Release")
    tracker.start(at(0))
    tracker.setCurrentDetail("downloading")
    let options = plainOptions()
    check tracker.render(options, at(0)) ==
      "Release\n. Fetch - downloading\no Build\no Publish"

    tracker.advance(at(120))
    tracker.failCurrent("compiler error", at(240))
    check tracker.render(options, at(900)) ==
      "Release\n+ Fetch - downloading\nx Build - compiler error\no Publish"
    check not tracker.render(options, at(900)).endsWith("\n")

    var cancelled = initStepTracker(["One", "Two"])
    cancelled.cancel(at(0))
    check cancelled.render(options, at(0)) == "- One\n- Two"

suite "responsive cell widths":
  test "every positive width bounds all component rows":
    var
      spinner = initSpinner("編譯 e\u0301moji 👩‍💻 and flag 🇳🇱", now = at(0))
      bar = initProgressBar("編譯 e\u0301moji 👩‍💻 and flag 🇳🇱", 100,
        "項目", at(0))
      multi = initMultiProgress()
      tracker = initStepTracker(
        ["編譯 e\u0301moji 👩‍💻 and flag 🇳🇱", "Second"], "Release 🚀")
    bar.advance(49, at(2_000))
    discard multi.addTask("編譯 e\u0301moji 👩‍💻 and flag 🇳🇱", 100,
      "項目", at(0))
    discard multi.addIndeterminateTask("Waiting", now = at(0))
    tracker.start(at(0))
    tracker.setCurrentDetail("detail with many cells")

    for width in 1 .. 80:
      var options = plainOptions()
      options.characters = statusUnicode
      options.width = width
      spinner.render(options, at(2_000)).checkRowsBounded(width)
      bar.render(options, at(2_000)).checkRowsBounded(width)
      multi.render(options, at(2_000)).checkRowsBounded(width)
      tracker.render(options, at(2_000)).checkRowsBounded(width)

  test "Unicode and ASCII truncation use whole graphemes and their suffix":
    let spinner = initSpinner("界界界", initSpinnerStyle(["*"], 100), at(0))
    var options = plainOptions()
    options.characters = statusUnicode
    options.width = 5
    check spinner.render(options, at(0)) == "* 界…"

    options.characters = statusAscii
    options.width = 7
    let asciiSpinner = initSpinner("abcdef", initSpinnerStyle(["*"] , 100), at(0))
    check asciiSpinner.render(options, at(0)) == "* ab..."

  test "progress reduction removes metadata then bar structure deterministically":
    var bar = initProgressBar("Download", 100, "MB", at(0))
    bar.advance(50, at(2_000))
    var options = plainOptions(6)
    options.showElapsed = true

    options.width = 51
    check "elapsed" notin bar.render(options, at(2_000))
    check "25.0 MB/s" in bar.render(options, at(2_000))
    options.width = 35
    check "25.0 MB/s" notin bar.render(options, at(2_000))
    options.width = 24
    check "ETA" notin bar.render(options, at(2_000))
    options.width = 18
    check "50/100" notin bar.render(options, at(2_000))
    options.width = 14
    check "[" in bar.render(options, at(2_000))
    options.width = 9
    check "%" notin bar.render(options, at(2_000))
    options.width = 6
    check "[" notin bar.render(options, at(2_000))

  test "step labels retain priority over details":
    var tracker = initStepTracker(["ImportantLabel"])
    tracker.start(at(0))
    tracker.setCurrentDetail("secondary detail")
    var options = plainOptions()
    options.width = 16
    check tracker.render(options, at(0)) == ". ImportantLabel"
    options.width = 10
    check tracker.render(options, at(0)) == ". Impor..."

suite "safe user text and color control":
  test "row boundaries and terminal-moving controls are normalized or dropped":
    let hostile = "A\r\n  B\tC\e[2K\e]0;owned\a\e7!"
    let spinner = initSpinner(hostile, initSpinnerStyle(["*"] , 100), at(0))
    let rendered = spinner.render(plainOptions(), at(0))
    check rendered == "* A B C!"
    check '\n' notin rendered
    check '\r' notin rendered
    check '\e' notin rendered

    let malformed = initSpinner("bad\xfftext", initSpinnerStyle(["*"], 100), at(0))
    check malformed.render(plainOptions(), at(0)).startsWith("* bad")

  test "safe SGR and OSC-8 survive enabled rendering and close locally":
    let
      hyperlink = "\e]8;;https://example.com\aLink"
      styled = "\e[31mred"
      style = initSpinnerStyle(["*"], 100)
      hyperlinkSpinner = initSpinner(hyperlink, style, at(0))
      styledSpinner = initSpinner(styled, style, at(0))
      options = unstyledOptions()

    check hyperlinkSpinner.render(options, at(0)) ==
      "* \e]8;;https://example.com\aLink\e]8;;\e\\"
    check styledSpinner.render(options, at(0)) == "* \e[31mred\e[0m"

    var plain = options
    plain.useColor = false
    check hyperlinkSpinner.render(plain, at(0)) == "* Link"
    check styledSpinner.render(plain, at(0)) == "* red"

  test "color disabled strips both caller and theme ANSI from every renderer":
    var
      spinner = initSpinner("\e[35mSpin\e[0m", now = at(0))
      bar = initProgressBar("\e[35mWork\e[0m", 2, now = at(0))
      multi = initMultiProgress()
      tracker = initStepTracker(["\e[35mStep\e[0m"], "\e[1mTitle\e[0m")
      options = plainOptions()
    discard multi.addTask("\e[35mTask\e[0m", 2, now = at(0))
    tracker.start(at(0))
    for rendered in [spinner.render(options, at(0)), bar.render(options, at(0)),
                     multi.render(options, at(0)), tracker.render(options, at(0))]:
      check '\e' notin rendered

  test "ANSI-aware truncation closes retained styles and hyperlinks":
    let spinner = initSpinner(
      "\e]8;;https://example.com\a\e[31mabcdefghij",
      initSpinnerStyle(["*"], 100), at(0))
    var options = unstyledOptions()
    options.width = 8
    let rendered = spinner.render(options, at(0))
    check displayWidth(rendered) <= 8
    check rendered.endsWith("\e]8;;\e\\\e[0m…") or
      rendered.endsWith("\e[0m\e]8;;\e\\…")

  test "rendering is deterministic and does not mutate models":
    var bar = initProgressBar("Work", 10, now = at(0))
    bar.advance(4, at(1_000))
    let before = (bar.label, bar.state, bar.completed, bar.finishedAt)
    let first = bar.render(plainOptions(), at(2_000))
    check bar.render(plainOptions(), at(2_000)) == first
    check (bar.label, bar.state, bar.completed, bar.finishedAt) == before
