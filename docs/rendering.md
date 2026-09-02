# Pure component rendering

`terminal_status/rendering` turns spinners, determinate and indeterminate
progress bars, insertion-ordered multi-progress collections, and step trackers
into strings. Rendering never writes output, queries a terminal, sleeps, starts
a worker, or changes its model.

```nim
import std/[monotimes, times]
import terminal_status

let started = getMonoTime()
var download = initProgressBar("Download", 100, "MB", started)
download.advance(50, started + initDuration(seconds = 2))

var options = defaultRenderOptions()
options.characters = statusAscii
options.useColor = false
options.barWidth = 10

doAssert download.render(
  options,
  started + initDuration(seconds = 2)
) == "> Download [#####-----]  50% 50/100 MB 25.0 MB/s ETA 2s"
```

Every overload accepts the same options and one monotonic `now` value:

```nim
let spinnerRow = spinner.render(options, now)
let progressRow = progressBar.render(options, now)
let progressRows = multiProgress.render(options, now)
let stepRows = stepTracker.render(options, now)
```

Multi-progress and tracker output uses `\n` only between logical rows. No
renderer appends a final newline. An empty multi-progress collection returns an
empty string.

## Metrics and animation

Determinate percentages and filled cells round down. Counts use
`completed/total`, optionally followed by the unit. Lifetime average rates use
one decimal place; ETA appears only for a running determinate bar with a finite
positive rate. Elapsed seconds round down, while a positive ETA rounds up.

Indeterminate bars derive a three-cell-or-smaller bouncing pulse from
`now - startedAt` and `indeterminateIntervalMs`. Spinner and running-step frames
are selected the same way. Terminal transitions freeze all time-derived output,
so repeated rendering later produces the same final frame.

## Width and responsive reduction

`width = 0` means unbounded output. A positive width is a maximum in terminal
cells, not a padding target. TerminalStyle measures CJK, emoji, combining marks,
and ANSI-bearing text, and truncation never slices a wide or combined grapheme.

For a narrow progress row, the renderer first removes elapsed, rate, ETA, and
count metadata in that order. It then shrinks the inner bar to four cells,
removes percentage, removes the whole bar, and finally truncates the label.
Unicode output uses `…`; ASCII output uses `...`. Step details yield before
their labels.

## Text and color safety

Labels, units, titles, and details are normalized to one terminal row. Newline,
carriage-return, and tab boundaries become one space. Cursor movement, erasure,
terminal-title, clipboard, device-control, and other executable controls are
dropped. Safe SGR styling and OSC-8 hyperlinks remain when `useColor = true`
and are closed before the segment or truncated row ends.

Set `useColor = false` for redirected output or any plain-text destination. It
removes both theme styling and safe ANSI supplied by the caller:

```nim
var plain = defaultRenderOptions()
plain.useColor = false
plain.characters = statusAscii
plain.width = 60

let logLine = progressBar.render(plain, now)
doAssert '\e' notin logLine
```

See the finite [`renderers.nim`](../examples/renderers.nim) dashboard and the
focused [`test_rendering.nim`](../tests/test_rendering.nim) contract tests.
