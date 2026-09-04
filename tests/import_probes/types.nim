## Process-isolated focused import probe for shared contracts.
import terminal_status/types

static:
  doAssert compiles(statusSucceeded.isTerminal)
  doAssert compiles($TaskId(42))
