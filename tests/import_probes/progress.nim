## Process-isolated focused import probe for progress models.
import terminal_status/progress

static:
  doAssert compiles(initProgressBar("focused import probe", 1))
  doAssert compiles(initMultiProgress().len)
