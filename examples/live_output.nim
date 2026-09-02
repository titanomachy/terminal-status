## A finite live-output example using auto detection and redirected-output
## coalescing. Run with `--every-change` to demonstrate opt-in plain logging.

import std/os

import terminal_status

var options = defaultLiveDisplayOptions(stdout)
for argument in commandLineParams():
  case argument
  of "--every-change":
    options.mode = livePlain
    options.plainPolicy = plainEveryChange
  of "--help", "-h":
    echo "Usage: live_output [--every-change]"
    quit(QuitSuccess)
  else:
    stderr.writeLine "unknown option: " & argument
    quit(QuitFailure)

withLiveDisplay display, options:
  display.update("Preparing release\n0/2 tasks complete")
  display.update("Building documentation\n1/2 tasks complete")
  display.update("Release ready\n2/2 tasks complete")
