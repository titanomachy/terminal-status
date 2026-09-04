## Pure-Nim terminal status models, component renderers, and live output.
##
## The façade exposes shared contracts, component models, semantic themes,
## marker presets, pure renderers, and explicit live-output strategies.
## Importing it performs no output, terminal detection, or background work;
## live capability detection is deferred until a display is opened.
##
## Import this module for the complete public API:
##
## .. code-block:: nim
##
##   import terminal_status
##
##   var progress = initProgressBar("Download", 100, "MB")
##   progress.advance(25)
##   echo progress.render()
##
## Applications that only need part of the library may instead import one or
## more focused modules: `types`, `spinners`, `progress`, `steps`, `themes`,
## `rendering`, and `live`. Focused model imports do not pull in rendering or
## live output. Every import is initialization-safe: the library defines no
## mutable global status state, reads no environment variables, queries no
## terminal, starts no timer or thread, and writes nothing during import.

import terminal_status/[live, progress, rendering, spinners, steps, themes, types]

export live, progress, rendering, spinners, steps, themes, types
