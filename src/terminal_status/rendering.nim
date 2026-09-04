## Pure, cell-aware renderers for TerminalStatus component models.
##
## Rendering performs no terminal queries or I/O and never mutates a model.
## Callers choose color, character repertoire, width, metadata, and the one
## monotonic timestamp used by an entire frame through `RenderOptions`.
## Returned frames are ordinary strings and require no adapter when embedded
## in TerminalLayout or TerminalTable. This module does not import live output
## or TerminalScreen and performs no terminal capability detection.

import std/[math, monotimes, options, strutils, times, unicode]

import terminal_style

import ./[progress, spinners, steps, themes, types]

type
  RenderOptions* = object
    ## Per-call presentation and metadata choices for pure renderers.
    ##
    ## `width == 0` means unbounded output. Positive widths are maximums rather
    ## than padding targets. `barWidth` and `indeterminateIntervalMs` must be
    ## positive. `useColor` controls both theme styling and safe caller ANSI;
    ## disabling it guarantees plain output.
    width*: int
      ## Maximum cells per output row, or zero for unbounded output.
    barWidth*: int
      ## Requested positive number of cells inside a progress bar.
    characters*: StatusCharacters
      ## Unicode or printable-ASCII presentation selection.
    useColor*: bool
      ## Enables theme and safe caller ANSI when true; otherwise strips both.
    showCount*: bool
      ## Requests completed/total count metadata when space permits.
    showElapsed*: bool
      ## Requests elapsed-time metadata when space permits.
    showRate*: bool
      ## Requests average lifetime-rate metadata when available and space permits.
    showEta*: bool
      ## Requests determinate running ETA when available and space permits.
    indeterminateIntervalMs*: int
      ## Positive milliseconds per indeterminate pulse position.
    theme*: StatusTheme
      ## Per-call semantic styles; rendering never mutates this value.

  ProgressRenderData = object
    label: string
    unit: string
    mode: ProgressMode
    state: StatusState
    completed: int64
    total: Option[int64]
    startedAt: MonoTime
    finishedAt: Option[MonoTime]

proc defaultRenderOptions*(): RenderOptions =
  ## Returns the normative unbounded, Unicode, color-enabled render options.
  ##
  ## The returned theme is a fresh value and can be customized without global
  ## mutation. No terminal is queried; applications choose `useColor` and an
  ## eventual positive width explicitly for each rendering context.
  RenderOptions(
    width: 0,
    barWidth: 20,
    characters: statusUnicode,
    useColor: true,
    showCount: true,
    showElapsed: false,
    showRate: true,
    showEta: true,
    indeterminateIntervalMs: 100,
    theme: defaultStatusTheme()
  )

proc validate(options: RenderOptions) =
  if options.width < 0:
    raise newException(ValueError, "width must not be negative")
  requirePositive(options.barWidth, "barWidth")
  requirePositive(options.indeterminateIntervalMs, "indeterminateIntervalMs")

proc isSgrReset(value: string): bool =
  if value.len < 3 or value[^1] != 'm':
    return false
  let parameters = value[2 ..< value.high]
  if parameters.len == 0:
    return true
  for parameter in parameters.split(';'):
    if parameter.len == 0 or parameter == "0":
      return true

proc osc8State(value: string; isOpen: var bool): bool =
  if not value.startsWith("\e]8;"):
    return false
  let bodyEnd =
    if value.endsWith("\e\\"): value.len - 2
    elif value.endsWith("\a"): value.len - 1
    else: return false
  if bodyEnd < 4:
    return false
  let body = value[4 ..< bodyEnd]
  let separator = body.find(';')
  if separator < 0:
    return false
  isOpen = separator + 1 < body.len
  true

proc normalizeText(value: string): string =
  ## Reduces caller text to one safe terminal row while retaining only SGR and
  ## well-formed OSC-8 controls. Any retained open state is closed locally so
  ## it cannot affect a later semantic segment.
  var
    boundaryActive = false
    lastVisibleWhitespace = false
    sgrOpen = false
    hyperlinkOpen = false

  for token in tokenizeAnsi(value):
    case token.kind
    of atkText:
      for rune in token.value.runes:
        let codepoint = int(rune)
        if codepoint in {0x09, 0x0a, 0x0d}:
          if not lastVisibleWhitespace:
            result.add ' '
            lastVisibleWhitespace = true
          boundaryActive = true
        elif codepoint < 0x20 or codepoint in 0x7f .. 0x9f:
          discard
        elif boundaryActive and rune.isWhiteSpace:
          discard
        else:
          result.add rune.toUTF8
          lastVisibleWhitespace = rune.isWhiteSpace
          boundaryActive = false
    of atkCsi:
      if token.value[^1] == 'm':
        result.add token.value
        sgrOpen = not token.value.isSgrReset
    of atkOsc:
      var open = false
      if token.value.osc8State(open):
        result.add token.value
        hyperlinkOpen = open
    of atkEscape:
      discard

  if hyperlinkOpen:
    result.add "\e]8;;\e\\"
  if sgrOpen:
    result.add ansiReset

proc markers(options: RenderOptions): StatusMarkers =
  if options.characters == statusAscii:
    asciiStatusMarkers()
  else:
    unicodeStatusMarkers()

proc suffix(options: RenderOptions): string =
  if options.characters == statusAscii: "..." else: "…"

proc paint(value: string; textStyle: TerminalStyle;
           options: RenderOptions): string =
  if value.len == 0:
    ""
  else:
    applyStyle(value, textStyle, enabled = options.useColor)

proc markerFor(state: StatusState; markerSet: StatusMarkers): string =
  case state
  of statusPending: markerSet.pending
  of statusRunning: markerSet.running
  of statusSucceeded: markerSet.succeeded
  of statusFailed: markerSet.failed
  of statusCancelled: markerSet.cancelled

proc styleFor(state: StatusState; theme: StatusTheme): TerminalStyle =
  case state
  of statusPending: theme.pendingStyle
  of statusRunning: theme.runningStyle
  of statusSucceeded: theme.successStyle
  of statusFailed: theme.failureStyle
  of statusCancelled: theme.cancelledStyle

proc bounded(value: string; options: RenderOptions): string =
  if options.width > 0:
    truncateAnsi(value, options.width, options.suffix)
  else:
    value

proc formatDuration(seconds: int64): string =
  let safeSeconds = max(0'i64, seconds)
  if safeSeconds < 60:
    $safeSeconds & "s"
  elif safeSeconds < 3_600:
    $(safeSeconds div 60) & "m " & align($(safeSeconds mod 60), 2, '0') & "s"
  else:
    $(safeSeconds div 3_600) & "h " &
      align($((safeSeconds mod 3_600) div 60), 2, '0') & "m " &
      align($(safeSeconds mod 60), 2, '0') & "s"

proc formatElapsed(value: Duration): string =
  formatDuration(value.inSeconds)

proc formatEta(value: Duration): string =
  var seconds = max(0'i64, value.inSeconds)
  if value > initDuration(seconds = seconds) and seconds < int64.high:
    inc seconds
  formatDuration(seconds)

proc elapsed(data: ProgressRenderData; now: MonoTime): Duration =
  elapsedDuration(data.startedAt, data.finishedAt, now)

proc rate(data: ProgressRenderData; now: MonoTime): Option[float] =
  if data.mode != progressDeterminate or data.completed <= 0:
    return none(float)
  let elapsedNanoseconds = data.elapsed(now).inNanoseconds
  if elapsedNanoseconds <= 0:
    return none(float)
  let value = data.completed.float * 1_000_000_000.0 /
    elapsedNanoseconds.float
  if classify(value) in {fcNan, fcInf, fcNegInf} or value <= 0.0:
    none(float)
  else:
    some(value)

proc eta(data: ProgressRenderData; now: MonoTime): Option[Duration] =
  if data.mode != progressDeterminate or data.state != statusRunning or
      data.completed >= data.total.get:
    return none(Duration)
  let average = data.rate(now)
  if average.isNone:
    return none(Duration)
  let milliseconds =
    (data.total.get - data.completed).float / average.get * 1_000.0
  if classify(milliseconds) in {fcNan, fcNegInf} or milliseconds < 0.0:
    return none(Duration)
  const maxMilliseconds = int64.high - 1_000'i64
  let rounded =
    if classify(milliseconds) == fcInf or
        milliseconds >= maxMilliseconds.float:
      maxMilliseconds
    else:
      int64(round(milliseconds))
  some(initDuration(milliseconds = rounded))

proc progressData(bar: ProgressBar): ProgressRenderData =
  ProgressRenderData(
    label: bar.label,
    unit: bar.unit,
    mode: bar.mode,
    state: bar.state,
    completed: bar.completed,
    total: bar.total,
    startedAt: bar.startedAt,
    finishedAt: bar.finishedAt
  )

proc progressData(task: ProgressTaskSnapshot): ProgressRenderData =
  ProgressRenderData(
    label: task.label,
    unit: task.unit,
    mode: task.mode,
    state: task.state,
    completed: task.completed,
    total: task.total,
    startedAt: task.startedAt,
    finishedAt: task.finishedAt
  )

proc progressBarSegment(data: ProgressRenderData; innerWidth: int;
                        markerSet: StatusMarkers;
                        options: RenderOptions; now: MonoTime): string =
  var filled = 0
  if data.mode == progressDeterminate:
    if data.state == statusSucceeded:
      filled = innerWidth
    else:
      filled = int(floor(data.completed.float * innerWidth.float /
        data.total.get.float))
      filled = clamp(filled, 0, innerWidth)
  elif data.state == statusSucceeded:
    filled = innerWidth
  else:
    let pulseWidth = max(1, min(3, innerWidth))
    let travel = innerWidth - pulseWidth
    var position = 0
    if travel > 0:
      let tick = data.elapsed(now).inMilliseconds div
        int64(options.indeterminateIntervalMs)
      let cycle = int64(2 * travel)
      let offset = int(tick mod cycle)
      position = if offset <= travel: offset else: 2 * travel - offset
    let before = markerSet.barRemaining.repeat(position)
    let pulse = markerSet.barComplete.repeat(pulseWidth)
    let after = markerSet.barRemaining.repeat(
      innerWidth - position - pulseWidth)
    return markerSet.barStart &
      paint(before, options.theme.remainingBarStyle, options) &
      paint(pulse, options.theme.completeBarStyle, options) &
      paint(after, options.theme.remainingBarStyle, options) &
      markerSet.barEnd

  markerSet.barStart &
    paint(markerSet.barComplete.repeat(filled),
      options.theme.completeBarStyle, options) &
    paint(markerSet.barRemaining.repeat(innerWidth - filled),
      options.theme.remainingBarStyle, options) &
    markerSet.barEnd

proc rowWidthWithoutLabel(segments: seq[string]): int =
  ## `segments` includes an empty label at index one.
  for segment in segments:
    result += displayWidth(segment)
  result += max(0, segments.len - 1)

proc renderProgress(data: ProgressRenderData; options: RenderOptions;
                    now: MonoTime): string =
  let
    markerSet = options.markers
    marker = paint(markerFor(data.state, markerSet),
      styleFor(data.state, options.theme), options)
    label = paint(normalizeText(data.label), options.theme.labelStyle, options)
    unit = normalizeText(data.unit)

  var
    innerWidth = options.barWidth
    includeBar = true
    includePercent = data.mode == progressDeterminate
    count = ""
    rateToken = ""
    etaToken = ""
    elapsedToken = ""

  if data.mode == progressDeterminate:
    if options.showCount:
      count = $data.completed & "/" & $data.total.get
      if displayWidth(unit) > 0:
        count.add " " & unit
    if options.showRate:
      let average = data.rate(now)
      if average.isSome:
        rateToken = formatFloat(average.get, ffDecimal, 1) &
          (if displayWidth(unit) > 0: " " & unit & "/s" else: "/s")
    if options.showEta:
      let remaining = data.eta(now)
      if remaining.isSome:
        etaToken = "ETA " & formatEta(remaining.get)
  if options.showElapsed:
    elapsedToken = "elapsed " & formatElapsed(data.elapsed(now))

  count = paint(count, options.theme.metadataStyle, options)
  rateToken = paint(rateToken, options.theme.metadataStyle, options)
  etaToken = paint(etaToken, options.theme.metadataStyle, options)
  elapsedToken = paint(elapsedToken, options.theme.metadataStyle, options)

  proc percentage(): string =
    let value = clamp(int(floor(data.completed.float * 100.0 /
      data.total.get.float)), 0, 100)
    paint(strutils.align($value, 3) & "%", options.theme.metadataStyle, options)

  proc assemble(labelValue: string): seq[string] =
    result = @[marker, labelValue]
    if includeBar:
      result.add progressBarSegment(data, innerWidth, markerSet, options, now)
    if includePercent:
      result.add percentage()
    for token in [count, rateToken, etaToken, elapsedToken]:
      if token.len > 0:
        result.add token

  if options.width == 0:
    return assemble(label).join(" ")

  proc minimumWidth(): int =
    let parts = assemble("")
    parts.rowWidthWithoutLabel + 1

  template removeUntilFits(token: untyped) =
    if minimumWidth() > options.width:
      token.setLen(0)

  removeUntilFits(elapsedToken)
  removeUntilFits(rateToken)
  removeUntilFits(etaToken)
  removeUntilFits(count)
  while minimumWidth() > options.width and includeBar and innerWidth > 4:
    dec innerWidth
  if minimumWidth() > options.width:
    includePercent = false
  if minimumWidth() > options.width:
    includeBar = false

  let withoutLabel = assemble("").rowWidthWithoutLabel
  let labelBudget = max(0, options.width - withoutLabel)
  let fittedLabel = truncateAnsi(label, labelBudget, options.suffix)
  assemble(fittedLabel).join(" ").bounded(options)

proc render*(spinner: Spinner; options = defaultRenderOptions();
             now = getMonoTime()): string =
  ## Renders one spinner row without I/O or model mutation.
  ##
  ## Running spinners use `now` to select a frame; terminal spinners use their
  ## semantic marker. Invalid options raise `ValueError`. Caller text is
  ## normalized to one safe row, and a positive width is a cell-width maximum.
  options.validate()
  let
    markerSet = options.markers
    glyph = if spinner.state == statusRunning:
      paint(spinner.frame(options.characters == statusAscii, now),
        options.theme.spinnerStyle, options)
    else:
      paint(markerFor(spinner.state, markerSet),
        styleFor(spinner.state, options.theme), options)
    label = paint(normalizeText(spinner.label), options.theme.labelStyle, options)

  if options.width == 0:
    return glyph & " " & label
  let labelBudget = max(0, options.width - displayWidth(glyph) - 1)
  (glyph & " " & truncateAnsi(label, labelBudget, options.suffix)).bounded(options)

proc render*(bar: ProgressBar; options = defaultRenderOptions();
             now = getMonoTime()): string =
  ## Renders one determinate or indeterminate progress row without I/O.
  ##
  ## Metrics and animation use the supplied `now` consistently. Responsive
  ## reduction removes metadata in the documented order, then shrinks/removes
  ## the bar and percentage before truncating the label. The model is unchanged.
  options.validate()
  renderProgress(bar.progressData, options, now)

proc render*(multi: MultiProgress; options = defaultRenderOptions();
             now = getMonoTime()): string =
  ## Renders progress tasks in insertion order, separated only by newlines.
  ##
  ## Empty collections return an empty string. One `now` value is shared by
  ## every row, each positive-width bound is applied independently, no final
  ## newline is appended, and rendering does not mutate the collection.
  options.validate()
  var rows = newSeqOfCap[string](multi.len)
  for task in multi.tasks:
    rows.add renderProgress(task.progressData, options, now)
  rows.join("\n")

proc render*(tracker: StepTracker; options = defaultRenderOptions();
             now = getMonoTime()): string =
  ## Renders an optional title followed by one safe row per ordered step.
  ##
  ## A running step uses the time-derived pulse preset. Under a positive width,
  ## detail yields before its label and every line remains within the terminal-
  ## cell maximum. The tracker and its timestamps are never mutated.
  options.validate()
  let markerSet = options.markers
  var rows = newSeqOfCap[string](tracker.len + 1)
  if tracker.title.len > 0:
    rows.add paint(normalizeText(tracker.title), options.theme.labelStyle,
      options).bounded(options)

  let pulse = pulseSpinner()
  let pulseFrames =
    if options.characters == statusAscii: pulse.asciiFrames else: pulse.frames
  for step in tracker.steps:
    let marker =
      if step.state == statusRunning:
        let elapsedMilliseconds = elapsedDuration(
          step.startedAt.get, step.finishedAt, now).inMilliseconds
        let index = int((elapsedMilliseconds div int64(pulse.intervalMs)) mod
          int64(pulseFrames.len))
        paint(pulseFrames[index], options.theme.spinnerStyle, options)
      else:
        paint(markerFor(step.state, markerSet),
          styleFor(step.state, options.theme), options)
    let
      label = paint(normalizeText(step.label), options.theme.labelStyle, options)
      detail = paint(normalizeText(step.detail), options.theme.detailStyle, options)
      separator = markerSet.detailSeparator

    if options.width == 0:
      rows.add marker & " " & label &
        (if displayWidth(detail) > 0: separator & detail else: "")
      continue

    let labelBudget = max(0, options.width - displayWidth(marker) - 1)
    var fittedLabel = label
    var fittedDetail = ""
    if displayWidth(detail) > 0:
      let detailBudget = options.width - displayWidth(marker) - 1 -
        displayWidth(label) - displayWidth(separator)
      if detailBudget > 0:
        fittedDetail = truncateAnsi(detail, detailBudget, options.suffix)
    if fittedDetail.len == 0:
      fittedLabel = truncateAnsi(label, labelBudget, options.suffix)
    let row = marker & " " & fittedLabel &
      (if fittedDetail.len > 0: separator & fittedDetail else: "")
    rows.add row.bounded(options)

  rows.join("\n")
