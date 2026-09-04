## Process-isolated focused import probe for spinner models.
import terminal_status/spinners

static:
  doAssert compiles(initSpinner("focused import probe"))
  doAssert compiles(lineSpinner().frames)
