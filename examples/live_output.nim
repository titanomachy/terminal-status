## A finite live-output example using auto detection, redirected-output
## coalescing, and configurable ANSI cleanup.

import std/os

import terminal_status

proc usage() =
  echo "Usage: live_output [--ansi] [--every-change] [--clear] " &
    "[--hide-cursor]"
  echo "  --ansi         assert ANSI redraw support"
  echo "  --every-change force plain output and log every changed frame"
  echo "  --clear        erase the final ANSI frame on close"
  echo "  --hide-cursor  hide and restore the cursor in ANSI mode"

var options = defaultLiveDisplayOptions(stdout)
for argument in commandLineParams():
  case argument
  of "--ansi":
    options.mode = liveAnsi
  of "--every-change":
    options.mode = livePlain
    options.plainPolicy = plainEveryChange
  of "--clear":
    options.finishPolicy = finishClear
  of "--hide-cursor":
    options.hideCursor = true
  of "--help", "-h":
    usage()
    quit(QuitSuccess)
  else:
    stderr.writeLine "unknown option: " & argument
    usage()
    quit(QuitFailure)

withLiveDisplay display, options:
  display.update("Preparing release\n0/2 tasks complete")
  display.update("Building documentation\n1/2 tasks complete")
  display.update("Release ready\n2/2 tasks complete")
