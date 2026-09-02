import std/[strutils, unittest]

import terminal_status

suite "public imports":
  test "the facade exports models and Phase 2 renderers":
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

    check unicodeStatusMarkers().succeeded == "✓"
    check defaultRenderOptions().theme.successStyle ==
      defaultStatusTheme().successStyle

    var options = defaultRenderOptions()
    options.useColor = false
    check spinner.render(options).endsWith(" Facade spinner")
    check progress.render(options).startsWith("● Facade progress")
    check tracker.render(options) == "○ Facade step"
