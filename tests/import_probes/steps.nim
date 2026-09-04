## Process-isolated focused import probe for step trackers.
import terminal_status/steps

static:
  doAssert compiles(initStepTracker(["focused import probe"]))
