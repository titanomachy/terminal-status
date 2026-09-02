## Pure-Nim terminal status models and rendering foundations.
##
## The façade exposes shared contracts, component models, semantic themes,
## marker presets, and render options. Importing it performs no output,
## terminal detection, or background work.

import terminal_status/[progress, rendering, spinners, steps, themes, types]

export progress, rendering, spinners, steps, themes, types
