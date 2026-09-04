## Process-isolated focused import probe for explicit live output.
import terminal_status/live

static:
  doAssert compiles(initLiveDisplay())
  doAssert compiles(block:
    var display: LiveDisplay
    discard display
  )
