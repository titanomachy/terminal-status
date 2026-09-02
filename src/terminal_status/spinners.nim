## Pure spinner presets and time-derived spinner state.
##
## Spinners perform no terminal I/O and use monotonic timestamps supplied by
## callers. Animation is a query: no timer, thread, or per-frame mutation is
## required.

import std/[monotimes, options, times]

import terminal_status/types

type
  SpinnerStyle* = object
    ## An immutable-by-API spinner preset with Unicode and ASCII frame sets.
    ##
    ## Frame query procedures always return fresh sequence storage.
    frameValues: seq[string]
    asciiFrameValues: seq[string]
    intervalMilliseconds: int

  Spinner* = object
    ## A running or terminal spinner whose frame is derived from elapsed time.
    ##
    ## A spinner owns its label and style, performs no I/O, and freezes its
    ## elapsed duration and frame at the first terminal transition.
    labelValue: string
    stateValue: StatusState
    styleValue: SpinnerStyle
    startedAtValue: MonoTime
    finishedAtValue: Option[MonoTime]

proc copyStyle(style: SpinnerStyle): SpinnerStyle =
  result = SpinnerStyle(
    frameValues: copyValues(style.frameValues),
    asciiFrameValues: copyValues(style.asciiFrameValues),
    intervalMilliseconds: style.intervalMilliseconds
  )

proc initSpinnerStyle*(frames: openArray[string], intervalMs: int,
                       asciiFrames: openArray[string] = []): SpinnerStyle =
  ## Creates a validated spinner style and copies both frame sets.
  ##
  ## Frames must be non-empty, control-free, single-line strings of equal
  ## terminal-cell width. `intervalMs` must be positive. If `asciiFrames` is
  ## omitted, the primary frames must themselves be printable ASCII and are
  ## copied as the fallback. Otherwise the fallback must contain the same
  ## number of printable-ASCII frames; its width may differ from the primary
  ## width. Invalid input raises `ValueError`.
  requirePositive(intervalMs, "intervalMs")
  discard validateFrameWidths(frames)

  let ownedFrames = copyValues(frames)
  var ownedAsciiFrames: seq[string]
  if asciiFrames.len == 0:
    discard validateFrameWidths(frames, "frames", asciiOnly = true)
    ownedAsciiFrames = copyValues(frames)
  else:
    requireSameLength(frames.len, asciiFrames.len, "spinner frame sets")
    discard validateFrameWidths(asciiFrames, "asciiFrames", asciiOnly = true)
    ownedAsciiFrames = copyValues(asciiFrames)

  result = SpinnerStyle(
    frameValues: ownedFrames,
    asciiFrameValues: ownedAsciiFrames,
    intervalMilliseconds: intervalMs
  )

proc frames*(style: SpinnerStyle): seq[string] =
  ## Returns a copy of the Unicode/preferred frame sequence.
  copyValues(style.frameValues)

proc asciiFrames*(style: SpinnerStyle): seq[string] =
  ## Returns a copy of the printable-ASCII fallback frame sequence.
  copyValues(style.asciiFrameValues)

proc intervalMs*(style: SpinnerStyle): int =
  ## Returns the number of milliseconds for which each frame is selected.
  style.intervalMilliseconds

proc dotsSpinner*(): SpinnerStyle =
  ## Returns the ten-frame, 80 ms braille-dots preset.
  initSpinnerStyle(
    ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    80,
    [".", "o", "O", "@", "*", "@", "O", "o", ".", "+"]
  )

proc lineSpinner*(): SpinnerStyle =
  ## Returns the four-frame, 100 ms rotating-line preset.
  initSpinnerStyle(["─", "\\", "│", "/"], 100, ["-", "\\", "|", "/"])

proc arcSpinner*(): SpinnerStyle =
  ## Returns the six-frame, 100 ms rotating-arc preset.
  initSpinnerStyle(
    ["◜", "◠", "◝", "◞", "◡", "◟"],
    100,
    ["-", "\\", "|", "/", "-", "\\"]
  )

proc pulseSpinner*(): SpinnerStyle =
  ## Returns the four-frame, 120 ms growing-and-shrinking pulse preset.
  initSpinnerStyle(["·", "•", "●", "•"], 120, [".", "o", "O", "o"])

proc initSpinner*(label: string, style = dotsSpinner(),
                  now = getMonoTime()): Spinner =
  ## Creates a running spinner at monotonic timestamp `now`.
  ##
  ## The label must contain visible text after ANSI controls and surrounding
  ## whitespace are ignored, or `ValueError` is raised. The spinner owns a
  ## copy of the supplied style and does not start background work. Supplying
  ## an uninitialized `SpinnerStyle` also raises `ValueError`.
  requireMeaningfulText(label)
  requirePositive(style.intervalMilliseconds, "style.intervalMs")
  discard validateFrameWidths(style.frameValues, "style.frames")
  requireSameLength(style.frameValues.len, style.asciiFrameValues.len,
    "spinner frame sets")
  discard validateFrameWidths(style.asciiFrameValues, "style.asciiFrames",
    asciiOnly = true)
  result = Spinner(
    labelValue: label,
    stateValue: statusRunning,
    styleValue: copyStyle(style),
    startedAtValue: now,
    finishedAtValue: none(MonoTime)
  )

proc label*(spinner: Spinner): string =
  ## Returns the original, unnormalized label value.
  spinner.labelValue

proc state*(spinner: Spinner): StatusState =
  ## Returns the spinner's lifecycle state.
  spinner.stateValue

proc style*(spinner: Spinner): SpinnerStyle =
  ## Returns an independently owned copy of the spinner style.
  copyStyle(spinner.styleValue)

proc startedAt*(spinner: Spinner): MonoTime =
  ## Returns the monotonic timestamp supplied at construction.
  spinner.startedAtValue

proc finishedAt*(spinner: Spinner): Option[MonoTime] =
  ## Returns the first terminal-transition timestamp, if the spinner ended.
  spinner.finishedAtValue

proc elapsed*(spinner: Spinner, now = getMonoTime()): Duration =
  ## Returns non-negative elapsed monotonic time.
  ##
  ## Running spinners use `now`; terminal spinners retain their duration at
  ## the first finish timestamp.
  elapsedDuration(spinner.startedAtValue, spinner.finishedAtValue, now)

proc setLabel*(spinner: var Spinner, label: string) =
  ## Replaces the label in any lifecycle state.
  ##
  ## Raises `ValueError` for a label without visible text and leaves the prior
  ## label unchanged when validation fails.
  requireMeaningfulText(label)
  spinner.labelValue = label

proc frameIndex*(spinner: Spinner, now = getMonoTime()): int =
  ## Selects a frame from elapsed monotonic time without mutating the spinner.
  ##
  ## Negative clock deltas defensively select frame zero. A terminal spinner
  ## uses its frozen elapsed duration.
  let elapsedMilliseconds = spinner.elapsed(now).inMilliseconds
  int((elapsedMilliseconds div int64(spinner.styleValue.intervalMilliseconds)) mod
      int64(spinner.styleValue.frameValues.len))

proc frame*(spinner: Spinner, asciiOnly = false,
            now = getMonoTime()): string =
  ## Returns the selected preferred or ASCII frame at `now`.
  ##
  ## Terminal state does not replace the preset frame with a semantic marker;
  ## renderers own that presentation choice. The selected frame freezes when
  ## the spinner first reaches a terminal state.
  let index = spinner.frameIndex(now)
  if asciiOnly:
    spinner.styleValue.asciiFrameValues[index]
  else:
    spinner.styleValue.frameValues[index]

proc succeed*(spinner: var Spinner, now = getMonoTime()) =
  ## Marks the spinner succeeded and freezes its time/frame at `now`.
  ##
  ## Repeating success is an idempotent no-op. A different terminal state
  ## raises `StatusStateError` without changing the first finish timestamp.
  transitionToTerminal(
    spinner.stateValue, spinner.finishedAtValue, statusSucceeded, now)

proc fail*(spinner: var Spinner, now = getMonoTime()) =
  ## Marks the spinner failed and freezes its time/frame at `now`.
  ##
  ## Repeating failure is an idempotent no-op. A different terminal state
  ## raises `StatusStateError` without changing the first finish timestamp.
  transitionToTerminal(
    spinner.stateValue, spinner.finishedAtValue, statusFailed, now)

proc cancel*(spinner: var Spinner, now = getMonoTime()) =
  ## Marks the spinner cancelled and freezes its time/frame at `now`.
  ##
  ## Repeating cancellation is an idempotent no-op. A different terminal state
  ## raises `StatusStateError` without changing the first finish timestamp.
  transitionToTerminal(
    spinner.stateValue, spinner.finishedAtValue, statusCancelled, now)
