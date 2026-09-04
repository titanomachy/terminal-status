## Pure determinate, indeterminate, and ordered multi-progress models.
##
## Progress models own their state and use caller-supplied monotonic timestamps.
## They perform no terminal I/O, rendering, sleeping, or background work.

import std/[math, monotimes, options, times]

import terminal_status/types

type
  ProgressBar* = object
    ## A running or terminal progress task with optional numeric completion.
    ##
    ## Determinate bars expose a total, fraction, average rate, and ETA.
    ## Indeterminate bars retain the same lifecycle but have no numeric total.
    labelValue: string
    unitValue: string
    modeValue: ProgressMode
    stateValue: StatusState
    completedValue: int64
    totalValue: Option[int64]
    startedAtValue: MonoTime
    finishedAtValue: Option[MonoTime]

  ProgressEntry = object
    id: TaskId
    bar: ProgressBar

  MultiProgress* = object
    ## An insertion-ordered collection of independently mutable progress tasks.
    ##
    ## Task IDs are stable and never reused after removal. Queries return
    ## detached snapshots rather than aliases into this collection.
    entries: seq[ProgressEntry]
    nextIdValue: uint64
    idsExhausted: bool

proc initProgressBar*(label: string, total: int64, unit = "",
                      now = getMonoTime()): ProgressBar =
  ## Creates a running determinate progress bar at monotonic timestamp `now`.
  ##
  ## `label` must contain visible text, `total` must be positive, and `unit`
  ## must be empty or contain visible text. Invalid values raise `ValueError`.
  requireMeaningfulText(label)
  requirePositive(total, "total")
  requireMeaningfulOrEmptyText(unit, "unit")
  ProgressBar(
    labelValue: label,
    unitValue: unit,
    modeValue: progressDeterminate,
    stateValue: statusRunning,
    completedValue: 0,
    totalValue: some(total),
    startedAtValue: now,
    finishedAtValue: none(MonoTime)
  )

proc initIndeterminateProgressBar*(label: string, unit = "",
                                   now = getMonoTime()): ProgressBar =
  ## Creates a running indeterminate progress bar at monotonic timestamp `now`.
  ##
  ## Indeterminate bars have no total, fraction, rate, or ETA. Labels and
  ## non-empty units must contain visible text.
  requireMeaningfulText(label)
  requireMeaningfulOrEmptyText(unit, "unit")
  ProgressBar(
    labelValue: label,
    unitValue: unit,
    modeValue: progressIndeterminate,
    stateValue: statusRunning,
    completedValue: 0,
    totalValue: none(int64),
    startedAtValue: now,
    finishedAtValue: none(MonoTime)
  )

proc label*(bar: ProgressBar): string =
  ## Returns the original, unnormalized label value.
  bar.labelValue

proc unit*(bar: ProgressBar): string =
  ## Returns the optional descriptive unit.
  bar.unitValue

proc mode*(bar: ProgressBar): ProgressMode =
  ## Returns whether the bar is determinate or indeterminate.
  bar.modeValue

proc state*(bar: ProgressBar): StatusState =
  ## Returns the progress bar's lifecycle state.
  bar.stateValue

proc completed*(bar: ProgressBar): int64 =
  ## Returns numeric completion, which remains zero for indeterminate bars.
  bar.completedValue

proc total*(bar: ProgressBar): Option[int64] =
  ## Returns the determinate total, or `none` for an indeterminate bar.
  bar.totalValue

proc startedAt*(bar: ProgressBar): MonoTime =
  ## Returns the monotonic timestamp supplied at construction.
  bar.startedAtValue

proc finishedAt*(bar: ProgressBar): Option[MonoTime] =
  ## Returns the first terminal-transition timestamp, if the bar ended.
  bar.finishedAtValue

proc elapsed*(bar: ProgressBar, now = getMonoTime()): Duration =
  ## Returns running elapsed time or the duration frozen at termination.
  elapsedDuration(bar.startedAtValue, bar.finishedAtValue, now)

proc fraction*(bar: ProgressBar): Option[float] =
  ## Returns determinate completion in the inclusive range 0.0 through 1.0.
  if bar.modeValue == progressDeterminate:
    some(bar.completedValue.float / bar.totalValue.get.float)
  else:
    none(float)

proc ratePerSecond*(bar: ProgressBar,
                    now = getMonoTime()): Option[float] =
  ## Returns the lifetime-average determinate completion rate.
  ##
  ## A rate is absent for indeterminate bars, zero completion, or zero elapsed
  ## time. The calculation uses monotonic elapsed nanoseconds.
  if bar.modeValue != progressDeterminate or bar.completedValue <= 0:
    return none(float)

  let elapsedNanoseconds = bar.elapsed(now).inNanoseconds
  if elapsedNanoseconds <= 0:
    return none(float)

  let rate = bar.completedValue.float * 1_000_000_000.0 /
    elapsedNanoseconds.float
  if classify(rate) in {fcNan, fcInf, fcNegInf} or rate <= 0.0:
    none(float)
  else:
    some(rate)

proc eta*(bar: ProgressBar, now = getMonoTime()): Option[Duration] =
  ## Returns the running determinate ETA rounded to the nearest millisecond.
  ##
  ## Terminal and indeterminate bars return `none`. Extremely large legal
  ## estimates saturate at the largest whole-millisecond `Duration` instead
  ## of overflowing.
  if bar.modeValue != progressDeterminate or bar.stateValue != statusRunning or
      bar.completedValue >= bar.totalValue.get:
    return none(Duration)

  let rate = bar.ratePerSecond(now)
  if rate.isNone or rate.get <= 0.0:
    return none(Duration)

  let milliseconds =
    (bar.totalValue.get - bar.completedValue).float / rate.get * 1_000.0
  if classify(milliseconds) in {fcNan, fcNegInf} or milliseconds < 0.0:
    return none(Duration)

  # Duration stores seconds and a nanosecond remainder. Reserving one second
  # keeps rounding away from `int64.high` and makes saturation representable.
  const maxMilliseconds = int64.high - 1_000'i64
  let roundedMilliseconds =
    if classify(milliseconds) == fcInf or milliseconds >= maxMilliseconds.float:
      maxMilliseconds
    else:
      int64(round(milliseconds))
  some(initDuration(milliseconds = roundedMilliseconds))

proc setLabel*(bar: var ProgressBar, label: string) =
  ## Replaces the label in any lifecycle state after meaningful-text validation.
  requireMeaningfulText(label)
  bar.labelValue = label

proc setUnit*(bar: var ProgressBar, unit: string) =
  ## Replaces the optional unit in any lifecycle state after validation.
  requireMeaningfulOrEmptyText(unit, "unit")
  bar.unitValue = unit

proc requireNumericMutation(bar: ProgressBar) =
  if bar.stateValue.isTerminal:
    raise newException(StatusStateError,
      "cannot mutate completion after progress has terminated")
  if bar.modeValue != progressDeterminate:
    raise newException(StatusStateError,
      "indeterminate progress has no numeric completion")

proc advance*(bar: var ProgressBar, amount: int64 = 1,
              now = getMonoTime()) =
  ## Increases determinate completion without overflow or partial mutation.
  ##
  ## `amount` must be non-negative and fit within the remaining total.
  ## Reaching the exact total atomically marks the bar succeeded at `now`.
  ## Numeric mutation of indeterminate or terminal bars raises
  ## `StatusStateError`.
  bar.requireNumericMutation()
  requireNonNegative(amount, "amount")
  let remaining = bar.totalValue.get - bar.completedValue
  if amount > remaining:
    raise newException(ValueError, "amount exceeds remaining progress")

  let updated = bar.completedValue + amount
  if updated == bar.totalValue.get:
    transitionToTerminal(
      bar.stateValue, bar.finishedAtValue, statusSucceeded, now)
  bar.completedValue = updated

proc setCompleted*(bar: var ProgressBar, value: int64,
                   now = getMonoTime()) =
  ## Sets monotonic determinate completion without partial mutation.
  ##
  ## `value` must be at least the current completion and at most the total.
  ## Reaching the total atomically marks the bar succeeded at `now`.
  bar.requireNumericMutation()
  requireNonNegative(value, "completed")
  if value < bar.completedValue:
    raise newException(ValueError, "completed must not decrease")
  if value > bar.totalValue.get:
    raise newException(ValueError, "completed exceeds total")

  if value == bar.totalValue.get:
    transitionToTerminal(
      bar.stateValue, bar.finishedAtValue, statusSucceeded, now)
  bar.completedValue = value

proc complete*(bar: var ProgressBar, now = getMonoTime()) =
  ## Marks the bar succeeded at `now` and fills a determinate total atomically.
  ##
  ## Repeating completion is idempotent. Trying to replace failure or
  ## cancellation with success raises `StatusStateError`.
  if bar.stateValue == statusSucceeded:
    return
  transitionToTerminal(
    bar.stateValue, bar.finishedAtValue, statusSucceeded, now)
  if bar.modeValue == progressDeterminate:
    bar.completedValue = bar.totalValue.get

proc fail*(bar: var ProgressBar, now = getMonoTime()) =
  ## Marks the bar failed and freezes its elapsed duration at `now`.
  transitionToTerminal(
    bar.stateValue, bar.finishedAtValue, statusFailed, now)

proc cancel*(bar: var ProgressBar, now = getMonoTime()) =
  ## Marks the bar cancelled and freezes its elapsed duration at `now`.
  transitionToTerminal(
    bar.stateValue, bar.finishedAtValue, statusCancelled, now)

proc snapshot(id: TaskId, bar: ProgressBar): ProgressTaskSnapshot =
  ProgressTaskSnapshot(
    id: id,
    label: bar.labelValue,
    unit: bar.unitValue,
    mode: bar.modeValue,
    state: bar.stateValue,
    completed: bar.completedValue,
    total: bar.totalValue,
    startedAt: bar.startedAtValue,
    finishedAt: bar.finishedAtValue
  )

proc initMultiProgress*(): MultiProgress =
  ## Creates an empty collection whose first allocated ID is `TaskId(1)`.
  MultiProgress(entries: @[], nextIdValue: 1, idsExhausted: false)

when defined(terminalStatusTest):
  proc setNextTaskIdForTesting*(multi: var MultiProgress; nextId: uint64) =
    ## Positions an empty collection at a chosen next ID for exhaustion tests.
    ##
    ## This deterministic test seam is unavailable in ordinary package builds.
    ## It rejects non-empty collections so tests cannot invalidate existing ID
    ## ordering or uniqueness guarantees.
    if multi.entries.len != 0:
      raise newException(ValueError,
        "task ID test seam requires an empty multi-progress collection")
    multi.nextIdValue = nextId
    multi.idsExhausted = false

proc len*(multi: MultiProgress): int =
  ## Returns the number of currently stored tasks.
  multi.entries.len

proc isEmpty*(multi: MultiProgress): bool =
  ## Returns whether the collection contains no tasks.
  multi.entries.len == 0

proc taskIds*(multi: MultiProgress): seq[TaskId] =
  ## Returns task IDs in insertion order using fresh sequence storage.
  result = newSeqOfCap[TaskId](multi.entries.len)
  for entry in multi.entries:
    result.add entry.id

proc tasks*(multi: MultiProgress): seq[ProgressTaskSnapshot] =
  ## Returns detached task snapshots in insertion order.
  result = newSeqOfCap[ProgressTaskSnapshot](multi.entries.len)
  for entry in multi.entries:
    result.add snapshot(entry.id, entry.bar)

proc findTaskIndex(multi: MultiProgress, id: TaskId): int =
  for index, entry in multi.entries:
    if entry.id == id:
      return index
  raise newException(UnknownTaskError, "unknown progress task ID " & $id)

proc task*(multi: MultiProgress, id: TaskId): ProgressTaskSnapshot =
  ## Returns a detached snapshot for `id` or raises `UnknownTaskError`.
  let index = multi.findTaskIndex(id)
  snapshot(multi.entries[index].id, multi.entries[index].bar)

proc allocateTaskId(multi: var MultiProgress): TaskId =
  if multi.idsExhausted:
    raise newException(TaskIdExhaustedError, "progress task IDs are exhausted")
  result = TaskId(multi.nextIdValue)
  if multi.nextIdValue == uint64.high:
    multi.idsExhausted = true
  else:
    inc multi.nextIdValue

proc addTask*(multi: var MultiProgress, label: string, total: int64,
              unit = "", now = getMonoTime()): TaskId =
  ## Appends a determinate task and returns its stable, never-reused ID.
  ##
  ## Task validation completes before ID allocation, so rejected input does
  ## not consume an ID.
  let bar = initProgressBar(label, total, unit, now)
  let id = multi.allocateTaskId()
  multi.entries.add ProgressEntry(id: id, bar: bar)
  id

proc addIndeterminateTask*(multi: var MultiProgress, label: string,
                           unit = "", now = getMonoTime()): TaskId =
  ## Appends an indeterminate task and returns its stable, never-reused ID.
  let bar = initIndeterminateProgressBar(label, unit, now)
  let id = multi.allocateTaskId()
  multi.entries.add ProgressEntry(id: id, bar: bar)
  id

proc removeTask*(multi: var MultiProgress, id: TaskId) =
  ## Removes `id` regardless of its state; removed IDs are never reused.
  multi.entries.delete(multi.findTaskIndex(id))

proc setLabel*(multi: var MultiProgress, id: TaskId, label: string) =
  ## Replaces the label of `id`, or raises `UnknownTaskError` if absent.
  let index = multi.findTaskIndex(id)
  multi.entries[index].bar.setLabel(label)

proc setUnit*(multi: var MultiProgress, id: TaskId, unit: string) =
  ## Replaces the unit of `id`, or raises `UnknownTaskError` if absent.
  let index = multi.findTaskIndex(id)
  multi.entries[index].bar.setUnit(unit)

proc advance*(multi: var MultiProgress, id: TaskId, amount: int64 = 1,
              now = getMonoTime()) =
  ## Delegates checked numeric advancement to task `id`.
  let index = multi.findTaskIndex(id)
  multi.entries[index].bar.advance(amount, now)

proc setCompleted*(multi: var MultiProgress, id: TaskId, value: int64,
                   now = getMonoTime()) =
  ## Delegates checked numeric completion assignment to task `id`.
  let index = multi.findTaskIndex(id)
  multi.entries[index].bar.setCompleted(value, now)

proc complete*(multi: var MultiProgress, id: TaskId,
               now = getMonoTime()) =
  ## Marks task `id` succeeded, filling its total when determinate.
  let index = multi.findTaskIndex(id)
  multi.entries[index].bar.complete(now)

proc fail*(multi: var MultiProgress, id: TaskId,
           now = getMonoTime()) =
  ## Marks task `id` failed.
  let index = multi.findTaskIndex(id)
  multi.entries[index].bar.fail(now)

proc cancel*(multi: var MultiProgress, id: TaskId,
             now = getMonoTime()) =
  ## Marks task `id` cancelled.
  let index = multi.findTaskIndex(id)
  multi.entries[index].bar.cancel(now)
