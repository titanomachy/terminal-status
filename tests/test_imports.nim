import std/[os, osproc, strutils, unittest]

import terminal_status

let
  repositoryDir = currentSourcePath().parentDir.parentDir
  probeDir = repositoryDir / "tests" / "import_probes"
  probeBuildDir = repositoryDir / "build" / "import-probes"

proc compileAndRunProbe(name: string): tuple[compileOutput: string,
    compileCode: int, runOutput: string, runCode: int] =
  createDir(probeBuildDir)
  let
    source = probeDir / (name & ".nim")
    executable = probeBuildDir / (name & ExeExt)
    compileCommand = getCurrentCompilerExe().quoteShell &
      " c --hints:off --verbosity:0 --out:" & executable.quoteShell &
      " " & source.quoteShell
    compilation = execCmdEx(compileCommand, options = {poStdErrToStdOut})

  result.compileOutput = compilation.output
  result.compileCode = compilation.exitCode
  if compilation.exitCode == 0:
    let execution = execCmdEx(executable.quoteShell,
      options = {poStdErrToStdOut})
    result.runOutput = execution.output
    result.runCode = execution.exitCode

suite "public imports":
  test "the facade exports models, renderers, and live output types":
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

    check defaultLiveDisplayOptions().mode == liveAuto
    check initLiveDisplay().state == displayNew

  test "facade and every public submodule import in an empty process":
    for moduleName in [
      "facade", "types", "spinners", "progress", "steps", "themes",
      "rendering", "live"
    ]:
      let probe = compileAndRunProbe(moduleName)
      checkpoint moduleName & " compile output:\n" & probe.compileOutput
      check probe.compileCode == 0
      checkpoint moduleName & " runtime output:\n" & probe.runOutput
      check probe.runCode == 0
      check probe.runOutput == ""
