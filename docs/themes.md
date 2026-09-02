# Themes, markers, and render options

`terminal_status/themes` defines presentation values without performing I/O,
querying terminal capabilities, or changing global state. The built-in theme
uses `TerminalStyle` values rather than embedded escape strings, while marker
presets give Unicode and printable-ASCII versions of each semantic role.

```nim
import terminal_style
import terminal_status

var options = defaultRenderOptions()
options.characters = statusAscii
options.useColor = false
options.theme.successStyle = initTerminalStyle(
  foreground = colorMagenta,
  attributes = {taBold}
)

doAssert asciiStatusMarkers().succeeded == "+"
doAssert unicodeStatusMarkers().succeeded == "✓"
```

## Marker presets

| Meaning | Unicode | ASCII |
| --- | --- | --- |
| Pending | `○` | `o` |
| Running | `●` | `>` |
| Succeeded | `✓` | `+` |
| Failed | `✗` | `x` |
| Cancelled | `–` | `-` |
| Complete bar | `█` | `#` |
| Remaining bar | `░` | `-` |
| Detail separator | ` — ` | ` - ` |

The shared bar delimiters are `[` and `]`. Every built-in marker and bar
character occupies exactly one terminal cell. The detail separators include
intentional surrounding spaces. `StatusMarkers` fields are public so an
application can substitute its own characters; pure renderers remain
responsible for respecting their configured output width.

## Default semantic theme

`defaultStatusTheme()` returns a fresh `StatusTheme` value on every call:

| Semantic role | Default presentation |
| --- | --- |
| Spinner and running | Cyan |
| Success and complete bar | Green |
| Failure | Red |
| Cancellation | Yellow |
| Pending, detail, remaining bar, metadata | Dim bright black |
| Label | Terminal default/no-op style |

All fields are `TerminalStyle` values. Construct custom colors and attributes
with `initTerminalStyle`; do not store raw SGR strings in a theme. Since themes
are ordinary values, changing a returned theme cannot affect future defaults
or another renderer.

## Explicit character and color choices

`defaultRenderOptions()` selects Unicode characters and enables color, but it
does not inspect a terminal. Applications explicitly set `characters` and
`useColor` for their destination. The options also carry the requested width,
inner bar width, metadata switches, pulse interval, and theme.

TerminalStyle's disabled application path removes both theme styling and safe
ANSI already present in caller text:

```nim
var options = defaultRenderOptions()
options.useColor = false

let callerText = "\e[1;35mready\e[0m"
let plain = applyStyle(
  callerText,
  options.theme.successStyle,
  enabled = options.useColor
)
doAssert plain == "ready"
```

The component renderers that consume this contract are the next Phase 2 slice.
Until then, the finite [`customization.nim`](../examples/customization.nim)
example previews the exact semantic styles, both marker sets, and a custom
spinner preset. Run it with `--ascii`, `--no-color`, or `--once` to see each
fallback independently.
