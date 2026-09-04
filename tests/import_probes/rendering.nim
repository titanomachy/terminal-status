## Process-isolated focused import probe for pure rendering options.
import terminal_status/rendering

static:
  doAssert compiles(defaultRenderOptions())
  doAssert compiles(block:
    var options: RenderOptions
    discard options
  )
