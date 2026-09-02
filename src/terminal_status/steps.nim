## Pure ordered step-tracker state.
##
## A tracker advances explicitly through owned step snapshots using monotonic
## timestamps. It performs no terminal I/O, rendering, or background work.

import std/[monotimes, options, times]

import terminal_status/types

type
  StepTracker* = object
    ## An ordered pending, running, or terminal sequence of work steps.
    ##
    ## Step storage is private; queries return detached values and sequences.
    titleValue: string
    stateValue: StatusState
    stepValues: seq[StepSnapshot]
    currentIndexValue: Option[int]
    startedAtValue: Option[MonoTime]
    finishedAtValue: Option[MonoTime]

proc initStepTracker*(labels: openArray[string], title = ""): StepTracker =
  ## Creates a pending tracker containing one or more validated step labels.
  ##
  ## `title` may be empty; a non-empty title and every label must contain
  ## visible text. Invalid input raises `ValueError` before construction.
  if labels.len == 0:
    raise newException(ValueError, "labels must not be empty")
  requireMeaningfulOrEmptyText(title, "title")
  for label in labels:
    requireMeaningfulText(label, "step label")

  result = StepTracker(
    titleValue: title,
    stateValue: statusPending,
    stepValues: newSeqOfCap[StepSnapshot](labels.len),
    currentIndexValue: none(int),
    startedAtValue: none(MonoTime),
    finishedAtValue: none(MonoTime)
  )
  for label in labels:
    result.stepValues.add StepSnapshot(
      label: label,
      detail: "",
      state: statusPending,
      startedAt: none(MonoTime),
      finishedAt: none(MonoTime)
    )

proc title*(tracker: StepTracker): string =
  ## Returns the optional, original, unnormalized title.
  tracker.titleValue

proc state*(tracker: StepTracker): StatusState =
  ## Returns the tracker's lifecycle state.
  tracker.stateValue

proc len*(tracker: StepTracker): int =
  ## Returns the number of steps.
  tracker.stepValues.len

proc currentIndex*(tracker: StepTracker): Option[int] =
  ## Returns the current step index, or `none` before the tracker starts.
  tracker.currentIndexValue

proc steps*(tracker: StepTracker): seq[StepSnapshot] =
  ## Returns detached step values in their original order.
  copyValues(tracker.stepValues)

proc step*(tracker: StepTracker, index: int): StepSnapshot =
  ## Returns a detached step value or raises `ValueError` for an invalid index.
  requireValidIndex(index, tracker.stepValues.len, "step index")
  tracker.stepValues[index]

proc elapsed*(tracker: StepTracker, now = getMonoTime()): Duration =
  ## Returns zero before start, running elapsed time, or frozen terminal time.
  if tracker.startedAtValue.isNone:
    initDuration()
  else:
    elapsedDuration(tracker.startedAtValue.get, tracker.finishedAtValue, now)

proc setTitle*(tracker: var StepTracker, title: string) =
  ## Replaces the optional title in any lifecycle state after validation.
  requireMeaningfulOrEmptyText(title, "title")
  tracker.titleValue = title

proc setCurrentDetail*(tracker: var StepTracker, detail: string) =
  ## Replaces the current step detail, including after termination.
  ##
  ## A detail may be empty; a non-empty detail must contain visible text.
  ## Calling this before a current step exists raises `StatusStateError`.
  if tracker.currentIndexValue.isNone:
    raise newException(StatusStateError, "step tracker has no current step")
  requireMeaningfulOrEmptyText(detail, "detail")
  tracker.stepValues[tracker.currentIndexValue.get].detail = detail

proc start*(tracker: var StepTracker, now = getMonoTime()) =
  ## Starts the tracker and its first step at `now`.
  ##
  ## Starting an already-running tracker is idempotent. Starting a terminal
  ## tracker raises `StatusStateError`.
  case tracker.stateValue
  of statusPending:
    tracker.stateValue = statusRunning
    tracker.currentIndexValue = some(0)
    tracker.startedAtValue = some(now)
    tracker.stepValues[0].state = statusRunning
    tracker.stepValues[0].startedAt = some(now)
  of statusRunning:
    discard
  else:
    raise newException(StatusStateError, "cannot start a terminal step tracker")

proc advance*(tracker: var StepTracker, now = getMonoTime()) =
  ## Succeeds the current step and starts the next one at the same timestamp.
  ##
  ## Advancing the final step succeeds the tracker and retains the last index.
  ## Pending or terminal trackers raise `StatusStateError`.
  if tracker.stateValue != statusRunning:
    raise newException(StatusStateError, "step tracker is not running")

  let index = tracker.currentIndexValue.get
  transitionToTerminal(tracker.stepValues[index].state,
    tracker.stepValues[index].finishedAt, statusSucceeded, now)
  if index == tracker.stepValues.high:
    transitionToTerminal(tracker.stateValue, tracker.finishedAtValue,
      statusSucceeded, now)
  else:
    let nextIndex = index + 1
    tracker.currentIndexValue = some(nextIndex)
    tracker.stepValues[nextIndex].state = statusRunning
    tracker.stepValues[nextIndex].startedAt = some(now)

proc failCurrent*(tracker: var StepTracker, detail = "",
                  now = getMonoTime()) =
  ## Fails the running current step and tracker at `now`.
  ##
  ## Repeating failure is idempotent; a supplied non-empty detail may still
  ## replace the failed step's detail without changing timestamps. Other
  ## states raise `StatusStateError`.
  if tracker.stateValue notin {statusRunning, statusFailed}:
    raise newException(StatusStateError,
      "only a running or failed step tracker can fail its current step")
  requireMeaningfulOrEmptyText(detail, "detail")

  let index = tracker.currentIndexValue.get
  if detail.len > 0:
    tracker.stepValues[index].detail = detail
  if tracker.stateValue == statusFailed:
    return

  transitionToTerminal(tracker.stepValues[index].state,
    tracker.stepValues[index].finishedAt, statusFailed, now)
  transitionToTerminal(tracker.stateValue, tracker.finishedAtValue,
    statusFailed, now)

proc cancel*(tracker: var StepTracker, now = getMonoTime()) =
  ## Cancels pending/running work at `now` while preserving succeeded steps.
  ##
  ## Cancellation before start cancels every step and leaves the current index
  ## absent. Repeating cancellation is idempotent; cancelling a succeeded or
  ## failed tracker raises `StatusStateError`.
  case tracker.stateValue
  of statusCancelled:
    return
  of statusSucceeded, statusFailed:
    raise newException(StatusStateError,
      "cannot cancel a succeeded or failed step tracker")
  of statusPending, statusRunning:
    discard

  for index in 0 ..< tracker.stepValues.len:
    if not tracker.stepValues[index].state.isTerminal:
      transitionToTerminal(tracker.stepValues[index].state,
        tracker.stepValues[index].finishedAt, statusCancelled, now)
  transitionToTerminal(tracker.stateValue, tracker.finishedAtValue,
    statusCancelled, now)
