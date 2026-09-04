## Demonstrates deterministic, final-only output for a file or pipe.
##
## Auto mode selects this strategy when its borrowed stream is redirected.
## This example forces plain mode so its observable output is identical when
## run interactively: only "release ready" is written when the scope closes.

import terminal_status

var options = defaultLiveDisplayOptions(stdout)
options.mode = livePlain
doAssert options.plainPolicy == plainFinalOnly

withLiveDisplay display, options:
  display.update("preparing release")
  display.update("building documentation")
  display.update("release ready")
