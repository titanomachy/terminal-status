## Deterministic monotonic-time fixtures shared by correctness tests.
##
## Tests construct every observed timestamp as an exact offset from one base;
## no assertion depends on wall time, scheduler timing, or sleeping.

import std/[monotimes, times]

let fixtureBaseTime = getMonoTime()

proc at*(milliseconds: int64): MonoTime =
  ## Returns an exact monotonic timestamp `milliseconds` from the test base.
  fixtureBaseTime + initDuration(milliseconds = milliseconds)
