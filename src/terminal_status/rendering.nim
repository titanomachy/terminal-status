## Shared options for TerminalStatus's pure rendering layer.
##
## Component renderers are introduced separately. Keeping their configuration
## in this focused module establishes explicit, per-call character and color
## choices without global terminal state or capability detection.

import ./themes

type
  RenderOptions* = object
    ## Per-call presentation and metadata choices for pure renderers.
    ##
    ## `width == 0` means unbounded output. Positive widths are maximums rather
    ## than padding targets. Renderers validate the positive interval and bar
    ## width fields before use. `useColor` controls both theme styling and safe
    ## caller-supplied ANSI; disabling it yields plain output.
    width*: int
    barWidth*: int
    characters*: StatusCharacters
    useColor*: bool
    showCount*: bool
    showElapsed*: bool
    showRate*: bool
    showEta*: bool
    indeterminateIntervalMs*: int
    theme*: StatusTheme

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
