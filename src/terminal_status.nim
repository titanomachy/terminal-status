## Pure-Nim terminal status models and component renderers.
##
## The façade exposes shared contracts, component models, semantic themes,
## marker presets, pure renderers, and explicit live-output strategies.
## Importing it performs no output, terminal detection, or background work;
## live capability detection is deferred until a display is opened.

import terminal_status/[live, progress, rendering, spinners, steps, themes, types]

export live, progress, rendering, spinners, steps, themes, types
