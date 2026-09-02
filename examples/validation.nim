## Shared validation helpers for component and extension authors.
##
## Invalid caller input raises catchable `ValueError` exceptions in every
## build mode; validation does not rewrite accepted strings.

import terminal_status/types

let styledLabel = "\e[32mReady\e[0m"
requireMeaningfulText(styledLabel)
requireMeaningfulOrEmptyText("", "unit")
requirePositive(100, "intervalMs")
requireNonNegative(0'i64, "completed")
requireValidIndex(1, 3)
requireSameLength(4, 4, "spinner frame sets")

doAssert styledLabel == "\e[32mReady\e[0m"
doAssert validateFrameWidths(["界", "好"]) == 2
doAssert validateFrameWidths(["-", "\\", "|", "/"],
  asciiOnly = true) == 1

proc showRejection(description: string; operation: proc ()) =
  try:
    operation()
  except ValueError as error:
    echo description, ": ", error.msg

showRejection("empty label") do ():
  requireMeaningfulText("\e[31m\e[0m")

showRejection("unequal frame widths") do ():
  discard validateFrameWidths(["-", "界"], "spinner")

showRejection("negative count") do ():
  requireNonNegative(-1, "completed")
