import std/[os, unittest]

import terminal_screen
import terminal_status

let
  repositoryDir = currentSourcePath().parentDir.parentDir
  temporaryDir = repositoryDir / "build" / "test-tmp"

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
