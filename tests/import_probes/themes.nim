## Process-isolated focused import probe for themes and character presets.
import terminal_status/themes

static:
  doAssert compiles(unicodeStatusMarkers())
  doAssert compiles(defaultStatusTheme())
