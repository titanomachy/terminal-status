## A finite LiveDisplay composed inside a non-raw TerminalScreen session.

import terminal_screen
import terminal_status

var sessionOptions = defaultSessionOptions()
sessionOptions.rawMode = false
sessionOptions.hideCursor = false
sessionOptions.requireTerminal = false
sessionOptions.monitorResize = false

withTerminalSession screen, stdin, stdout, sessionOptions:
  var liveOptions = defaultLiveDisplayOptions(stdout)
  withLiveDisplay display, liveOptions:
    display.update("Preparing composition\n1/2 checks complete")
    display.update("Composition verified\n2/2 checks complete")

  # LiveDisplay owns only its output rows. TerminalScreen still owns the
  # surrounding session and is solely responsible for session restoration.
  doAssert screen.isOpen
