## Shared model contracts and validation helpers for TerminalStatus.
##
## This module is pure: it defines the common states, identifiers, snapshots,
## and invariant helpers used by component models without performing terminal
## I/O or reading wall-clock time.

import std/[hashes, monotimes, options, times, unicode]

import terminal_style

type
  StatusState* = enum
    ## Lifecycle state shared by status components.
    statusPending
    statusRunning
    statusSucceeded
    statusFailed
    statusCancelled

  ProgressMode* = enum
    ## Whether a progress task has a known numeric total.
    progressDeterminate
    progressIndeterminate

  StatusError* = object of CatchableError
    ## Base exception for TerminalStatus model errors.
  StatusStateError* = object of StatusError
    ## Raised when an operation is invalid for the current lifecycle state.
  UnknownTaskError* = object of StatusError
    ## Raised when a multi-progress task ID does not exist.
  TaskIdExhaustedError* = object of StatusError
    ## Raised before allocating a task ID would wrap or be reused.

  TaskId* = distinct uint64
    ## Stable identifier allocated by a multi-progress collection.

  ProgressTaskSnapshot* = object
    ## Detached, read-only-by-ownership view of a progress task.
    ##
    ## Mutating this value never mutates the collection that produced it.
    id*: TaskId
    label*: string
    unit*: string
    mode*: ProgressMode
    state*: StatusState
    completed*: int64
    total*: Option[int64]
    startedAt*: MonoTime
    finishedAt*: Option[MonoTime]

  StepSnapshot* = object
    ## Detached, read-only-by-ownership view of one tracker step.
    ##
    ## Mutating this value never mutates the tracker that produced it.
    label*: string
    detail*: string
    state*: StatusState
    startedAt*: Option[MonoTime]
    finishedAt*: Option[MonoTime]

proc `==`*(left, right: TaskId): bool {.borrow.}
  ## Compares task IDs by their underlying unsigned value.

proc `$`*(id: TaskId): string =
  ## Returns the task ID as an unsigned decimal string without a prefix.
  $uint64(id)

proc hash*(id: TaskId): Hash =
  ## Hashes a task ID for use in ordinary hashed collections.
  hash(uint64(id))

proc isTerminal*(state: StatusState): bool =
  ## Returns whether `state` is succeeded, failed, or cancelled.
  state in {statusSucceeded, statusFailed, statusCancelled}

proc requireMeaningfulText*(value: string; fieldName = "label") =
  ## Raises `ValueError` unless `value` contains visible text after ANSI
  ## controls and surrounding Unicode whitespace are ignored.
  ##
  ## Validation never rewrites `value`; component models retain the original
  ## text for later renderer normalization.
  let visibleText = unicode.strip(stripAnsi(value))
  if visibleText.len == 0 or displayWidth(visibleText) == 0:
    raise newException(ValueError, fieldName & " must contain visible text")

proc requireMeaningfulOrEmptyText*(value: string; fieldName: string) =
  ## Accepts an empty optional field, otherwise applies meaningful-text
  ## validation.
  if value.len > 0:
    requireMeaningfulText(value, fieldName)

proc requirePositive*[T: SomeInteger](value: T; fieldName: string) =
  ## Raises `ValueError` unless an integer API argument is positive.
  if value <= 0:
    raise newException(ValueError, fieldName & " must be positive")

proc requireNonNegative*[T: SomeInteger](value: T; fieldName: string) =
  ## Raises `ValueError` unless an integer API argument is non-negative.
  if value < 0:
    raise newException(ValueError, fieldName & " must not be negative")

proc requireValidIndex*(index, length: int; fieldName = "index") =
  ## Raises `ValueError` unless `index` addresses a collection of `length`.
  if index < 0 or index >= length:
    raise newException(ValueError, fieldName & " is out of range")

proc validateFrameWidths*(frames: openArray[string]; fieldName = "frames";
                          asciiOnly = false): int =
  ## Validates a non-empty, control-free, equal-cell-width frame sequence and
  ## returns its display width. With `asciiOnly`, every byte must be printable
  ## ASCII.
  if frames.len == 0:
    raise newException(ValueError, fieldName & " must not be empty")

  var expectedWidth = -1
  # Indexing produces an owned string value here. Passing the `lent string`
  # yielded directly by an `openArray` into `unicode.runes` is unsafe under
  # Nim 2.2.10 with ORC.
  for index in 0 ..< frames.len:
    let frame = frames[index]
    if frame.len == 0:
      raise newException(ValueError, fieldName & " must not contain empty frames")

    for token in tokenizeAnsi(frame):
      if token.kind != atkText:
        raise newException(ValueError, fieldName & " must not contain ANSI controls")

    for rune in frame.runes:
      let codepoint = int(rune)
      if codepoint < 0x20 or codepoint in 0x7f .. 0x9f:
        raise newException(ValueError, fieldName & " must contain one control-free line")

    if asciiOnly:
      for character in frame:
        if ord(character) < 0x20 or ord(character) > 0x7e:
          raise newException(ValueError, fieldName & " must contain printable ASCII only")

    let width = displayWidth(frame)
    if width <= 0:
      raise newException(ValueError, fieldName & " frames must have positive display width")
    if expectedWidth < 0:
      expectedWidth = width
    elif width != expectedWidth:
      raise newException(ValueError, fieldName & " frames must have equal display widths")

  result = expectedWidth

proc requireSameLength*(leftLength, rightLength: int;
                        fieldName = "sequences") =
  ## Raises `ValueError` unless two related sequences have the same length.
  if leftLength != rightLength:
    raise newException(ValueError, fieldName & " must have the same number of entries")

proc copyValues*[T](values: openArray[T]): seq[T] =
  ## Returns fresh sequence storage for value snapshots and model-owned data.
  result = newSeqOfCap[T](values.len)
  for value in values:
    result.add value

proc transitionToTerminal*(state: var StatusState;
                           finishedAt: var Option[MonoTime];
                           target: StatusState; now: MonoTime) =
  ## Applies the common finite terminal-transition contract.
  ##
  ## Repeating the current terminal state is an idempotent no-op that retains
  ## the first finish time. Switching between terminal states raises
  ## `StatusStateError`.
  if not target.isTerminal:
    raise newException(ValueError, "target state must be terminal")
  if state.isTerminal:
    if state == target:
      return
    raise newException(StatusStateError,
      "cannot transition from " & $state & " to " & $target)

  state = target
  finishedAt = some(now)

proc clampedDuration*(startedAt, endedAt: MonoTime): Duration =
  ## Returns a monotonic duration, defensively clamped to zero.
  if endedAt <= startedAt:
    initDuration()
  else:
    endedAt - startedAt

proc elapsedDuration*(startedAt: MonoTime; finishedAt: Option[MonoTime];
                      now: MonoTime): Duration =
  ## Returns a running duration or the frozen duration at first termination.
  clampedDuration(startedAt,
    if finishedAt.isSome: finishedAt.get else: now)
