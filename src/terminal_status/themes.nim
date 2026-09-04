## Semantic characters and reusable styles for TerminalStatus renderers.
##
## Presets are returned by value, contain no mutable global state, and perform
## no terminal detection or output. Applications may replace any public field
## to build a custom presentation while retaining the renderer's semantics.

import terminal_style

type
  StatusCharacters* = enum
    ## Selects the preferred character repertoire for status output.
    statusUnicode ## Use the built-in Unicode markers and spinner frames.
    statusAscii ## Use printable-ASCII fallbacks.

  StatusMarkers* = object
    ## Semantic markers and bar characters used by pure status renderers.
    ##
    ## The built-in presets give every field except `detailSeparator` exactly
    ## one terminal cell. Custom values are public so applications can define
    ## their own visual language; renderers remain responsible for width.
    pending*: string
      ## Marker for work that has not started.
    running*: string
      ## Marker for active determinate work.
    succeeded*: string
      ## Marker for successfully completed work.
    failed*: string
      ## Marker for failed work.
    cancelled*: string
      ## Marker for cancelled work.
    barStart*: string
      ## Opening delimiter for progress bars.
    barEnd*: string
      ## Closing delimiter for progress bars.
    barComplete*: string
      ## Repeated cell representing completed progress.
    barRemaining*: string
      ## Repeated cell representing remaining progress.
    detailSeparator*: string
      ## Separator inserted between a step label and non-empty detail.

  StatusTheme* = object
    ## Semantic TerminalStyle values applied by pure status renderers.
    ##
    ## A theme contains presentation only: it does not enable color globally,
    ## query terminal capabilities, or emit ANSI. Render options decide whether
    ## these styles are enabled for each render call.
    spinnerStyle*: TerminalStyle
      ## Style for animated spinner and pulse glyphs.
    runningStyle*: TerminalStyle
      ## Style for active semantic markers.
    successStyle*: TerminalStyle
      ## Style for successful semantic markers.
    failureStyle*: TerminalStyle
      ## Style for failed semantic markers.
    cancelledStyle*: TerminalStyle
      ## Style for cancelled semantic markers.
    pendingStyle*: TerminalStyle
      ## Style for pending semantic markers.
    labelStyle*: TerminalStyle
      ## Style for component labels and step-tracker titles.
    detailStyle*: TerminalStyle
      ## Style for optional step detail.
    completeBarStyle*: TerminalStyle
      ## Style for completed progress-bar cells.
    remainingBarStyle*: TerminalStyle
      ## Style for remaining progress-bar cells.
    metadataStyle*: TerminalStyle
      ## Style for counts, percentages, rates, elapsed time, and ETA.

proc unicodeStatusMarkers*(): StatusMarkers =
  ## Returns the Unicode status marker and progress-bar preset.
  ##
  ## Every marker and bar character occupies one terminal cell. The em-dash
  ## detail separator includes its intentional surrounding spaces.
  StatusMarkers(
    pending: "○",
    running: "●",
    succeeded: "✓",
    failed: "✗",
    cancelled: "–",
    barStart: "[",
    barEnd: "]",
    barComplete: "█",
    barRemaining: "░",
    detailSeparator: " — "
  )

proc asciiStatusMarkers*(): StatusMarkers =
  ## Returns the printable-ASCII status marker and progress-bar preset.
  ##
  ## Every marker and bar character occupies one terminal cell. The hyphen
  ## detail separator includes its intentional surrounding spaces.
  StatusMarkers(
    pending: "o",
    running: ">",
    succeeded: "+",
    failed: "x",
    cancelled: "-",
    barStart: "[",
    barEnd: "]",
    barComplete: "#",
    barRemaining: "-",
    detailSeparator: " - "
  )

proc defaultStatusTheme*(): StatusTheme =
  ## Returns the default semantic status theme built only from TerminalStyle.
  ##
  ## Calling this procedure has no side effects. Mutating the returned value
  ## cannot alter later defaults because each call constructs a fresh value.
  let subdued = initTerminalStyle(
    foreground = colorBrightBlack,
    attributes = {taDim}
  )

  StatusTheme(
    spinnerStyle: initTerminalStyle(foreground = colorCyan),
    runningStyle: initTerminalStyle(foreground = colorCyan),
    successStyle: initTerminalStyle(foreground = colorGreen),
    failureStyle: initTerminalStyle(foreground = colorRed),
    cancelledStyle: initTerminalStyle(foreground = colorYellow),
    pendingStyle: subdued,
    labelStyle: initTerminalStyle(),
    detailStyle: subdued,
    completeBarStyle: initTerminalStyle(foreground = colorGreen),
    remainingBarStyle: subdued,
    metadataStyle: subdued
  )
