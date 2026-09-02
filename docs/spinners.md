# Spinner model

`terminal_status/spinners` provides validated spinner presets and a pure state
model. It never writes to a stream, queries terminal capabilities, sleeps, or
starts background work. Callers choose when to sample a frame and when to send
rendered output to their display layer.

```nim
import std/[monotimes, times]
import terminal_status

let started = getMonoTime()
var spinner = initSpinner("Indexing files", arcSpinner(), started)

# Animation is derived from a timestamp; this query does not mutate spinner.
let later = started + initDuration(milliseconds = 200)
doAssert spinner.frame(now = later) == "◝"
echo spinner.render(now = later)

spinner.setLabel("Index complete")
spinner.succeed(later)
doAssert spinner.state == statusSucceeded
```

## Presets and custom styles

The built-in `dotsSpinner`, `lineSpinner`, `arcSpinner`, and `pulseSpinner`
presets each include Unicode frames and printable-ASCII fallbacks. Select the
fallback with `spinner.frame(asciiOnly = true)`.

Create a custom preset with `initSpinnerStyle`. Preferred frames must be
non-empty, control-free single-line strings with one consistent terminal-cell
width. The interval must be positive. An explicit ASCII fallback must have the
same frame count and be printable ASCII, but its cell width may differ from the
preferred set.

```nim
let arrows = initSpinnerStyle(
  frames = ["←", "↑", "→", "↓"],
  intervalMs = 100,
  asciiFrames = ["<", "^", ">", "v"]
)
```

Frame getters return copied sequence storage. A `Spinner` also owns its style,
label, start time, state, and optional finish time; it never retains a pointer
to a caller-owned model.

## Time and transitions

The current index is
`floor(max(now - startedAt, 0) / intervalMs) mod frameCount`. Passing explicit
`MonoTime` values makes application simulations and tests deterministic.

Calling `succeed`, `fail`, or `cancel` records the first terminal timestamp and
freezes elapsed time and frame selection. Repeating the same transition is an
idempotent no-op. Trying a different terminal transition raises
`StatusStateError`. Labels may still be replaced after termination so the
caller can attach a final message.

The renderer substitutes a semantic success, failure, or cancellation marker
for terminal states and supports explicit Unicode/ASCII, color, and cell-width
choices. See [pure component rendering](rendering.md) for the shared contract.
