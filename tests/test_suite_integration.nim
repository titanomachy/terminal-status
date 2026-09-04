import std/[os, osproc, unittest]

import terminal_screen
import terminal_status

let
  repositoryDir = currentSourcePath().parentDir.parentDir
  temporaryDir = repositoryDir / "build" / "test-tmp"
  probeDir = repositoryDir / "tests" / "integration_probes"
  siblingDir = repositoryDir.parentDir
  statusSourceDir = repositoryDir / "src"
  styleSourceDir = siblingDir / "terminal-styles" / "src"
  screenSourceDir = siblingDir / "terminal-screen" / "src"
  layoutSourceDir = siblingDir / "terminal-layout" / "src"
  tableSourceDir = siblingDir / "terminal-tables" / "src"

proc sourcesAvailable(paths: openArray[string]): bool =
  ## Keeps development-only layout/table checks optional outside a suite clone.
  for path in paths:
    if not dirExists(path):
      return false
  true

proc compileAndRunProbe(name: string; sourcePaths: openArray[string]): tuple[
    compileOutput: string, compileCode: int, runOutput: string, runCode: int] =
  ## Isolates every probe from Nimble resolution so explicit sibling paths are
  ## the dependencies actually compiled by the interoperability check.
  let
    buildDir = repositoryDir / "build" / "suite-integration" / name
    source = probeDir / (name & ".nim")
    executable = buildDir / (name & ExeExt)
    nimcache = buildDir / "nimcache"
  createDir(buildDir)

  var command = getCurrentCompilerExe().quoteShell &
    " c --skipUserCfg:on --skipParentCfg:on --skipProjCfg:on" &
    " --hints:off --verbosity:0" &
    " --nimcache:" & nimcache.quoteShell &
    " --out:" & executable.quoteShell
  for path in sourcePaths:
    command.add " --path:" & path.quoteShell
  command.add " " & source.quoteShell

  let compilation = execCmdEx(command, options = {poStdErrToStdOut})
  result.compileOutput = compilation.output
  result.compileCode = compilation.exitCode
  if compilation.exitCode == 0:
    let execution = execCmdEx(executable.quoteShell,
      options = {poStdErrToStdOut})
    result.runOutput = execution.output
    result.runCode = execution.exitCode

proc checkProbe(name: string; sourcePaths: openArray[string]) =
  let probe = compileAndRunProbe(name, sourcePaths)
  checkpoint name & " compile output:\n" & probe.compileOutput
  check probe.compileCode == 0
  checkpoint name & " runtime output:\n" & probe.runOutput
  check probe.runCode == 0
  check probe.runOutput == ""

suite "source-path and string-boundary interoperability":
  test "TerminalStyle and TerminalScreen sibling sources compile together":
    let paths = [statusSourceDir, styleSourceDir, screenSourceDir]
    if sourcesAvailable(paths):
      checkProbe("suite_sources", paths)
    else:
      checkpoint "sibling TerminalStyle/TerminalScreen sources unavailable"
      check true

  test "pure focused imports render without the live output layer":
    let paths = [statusSourceDir, styleSourceDir]
    if sourcesAvailable(paths):
      checkProbe("pure_rendering", paths)
    else:
      checkpoint "sibling TerminalStyle sources unavailable"
      check true

  test "a progress string embeds in a sibling TerminalLayout panel":
    let paths = [statusSourceDir, styleSourceDir, layoutSourceDir]
    if sourcesAvailable(paths):
      checkProbe("layout_embedding", paths)
    else:
      checkpoint "sibling TerminalLayout sources unavailable"
      check true

  test "a status string embeds in a sibling TerminalTable cell":
    let paths = [statusSourceDir, styleSourceDir, tableSourceDir]
    if sourcesAvailable(paths):
      checkProbe("table_embedding", paths)
    else:
      checkpoint "sibling TerminalTable sources unavailable"
      check true

suite "TerminalScreen composition":
  test "LiveDisplay stays inside a borrowed non-raw session lifecycle":
    createDir(temporaryDir)
    let captureId = $getCurrentProcessId()
    let
      inputPath = temporaryDir /
        ("screen-composition-input-" & captureId & ".txt")
      outputPath = temporaryDir /
        ("screen-composition-output-" & captureId & ".txt")
    writeFile(inputPath, "")

    var
      input: File
      output: File
    require open(input, inputPath, fmRead)
    require open(output, outputPath, fmWrite)
    defer:
      input.close()
      output.close()
      removeFile(inputPath)
      removeFile(outputPath)

    var sessionOptions = defaultSessionOptions()
    sessionOptions.rawMode = false
    sessionOptions.hideCursor = false
    sessionOptions.requireTerminal = false
    sessionOptions.monitorResize = false
    sessionOptions.ansiMode = ansiNever
    let session = openSession(input, output, sessionOptions)
    defer: session.close()

    var liveOptions = defaultLiveDisplayOptions(output)
    liveOptions.mode = livePlain
    withLiveDisplay display, liveOptions:
      display.update("composed safely")

    check session.isOpen
    session.close()
    check not session.isOpen

    output.write("still borrowed\n")
    output.flushFile()
    check readFile(outputPath) == "composed safely\nstill borrowed\n"

when defined(posix):
  import std/[posix, termios]

  when defined(linux):
    {.passL: "-lutil".}

  when defined(macosx):
    proc openpty(master, slave: ptr cint; name: cstring;
                 settings: ptr Termios; size: pointer): cint {.
      importc, header: "<util.h>".}
  else:
    proc openpty(master, slave: ptr cint; name: cstring;
                 settings: ptr Termios; size: pointer): cint {.
      importc, header: "<pty.h>".}

  when defined(macosx):
    var PENDIN {.importc, header: "<termios.h>".}: Cflag

  type Pty = object
    master: cint
    slave: File

  proc openPty(): Pty =
    var slaveFd: cint
    if openpty(addr result.master, addr slaveFd, nil, nil, nil) != 0:
      raiseOSError(osLastError())
    if not open(result.slave, FileHandle(slaveFd), fmReadWrite):
      discard posix.close(result.master)
      discard posix.close(slaveFd)
      raise newException(IOError, "cannot wrap PTY slave file descriptor")

  proc close(pty: var Pty) =
    pty.slave.close()
    discard posix.close(pty.master)

  proc comparableLocalFlags(mode: Termios): Cflag =
    when defined(macosx):
      mode.c_lflag and not PENDIN
    else:
      mode.c_lflag

  proc sameMode(left, right: Termios): bool =
    left.c_iflag == right.c_iflag and
      left.c_oflag == right.c_oflag and
      left.c_cflag == right.c_cflag and
      left.comparableLocalFlags == right.comparableLocalFlags and
      left.c_cc == right.c_cc

  suite "POSIX TerminalScreen composition":
    test "LiveDisplay never enters or restores terminal input modes":
      var pty = openPty()
      defer: pty.close()
      let slaveFd = cint(pty.slave.getFileHandle())

      var baseline: Termios
      require tcGetAttr(slaveFd, addr baseline) == 0

      var sessionOptions = defaultSessionOptions()
      sessionOptions.rawMode = false
      sessionOptions.hideCursor = false
      sessionOptions.monitorResize = false
      sessionOptions.ansiMode = ansiAlways
      let session = openSession(pty.slave, pty.slave, sessionOptions)
      defer: session.close()

      var duringSession: Termios
      require tcGetAttr(slaveFd, addr duringSession) == 0
      check duringSession.sameMode(baseline)

      var liveOptions = defaultLiveDisplayOptions(pty.slave)
      liveOptions.mode = liveAnsi
      liveOptions.hideCursor = false
      withLiveDisplay display, liveOptions:
        display.update("TerminalStatus inside TerminalScreen")

      check session.isOpen
      var afterDisplay: Termios
      require tcGetAttr(slaveFd, addr afterDisplay) == 0
      check afterDisplay.sameMode(duringSession)

      session.close()
      var afterSession: Termios
      require tcGetAttr(slaveFd, addr afterSession) == 0
      check afterSession.sameMode(baseline)
