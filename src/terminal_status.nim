## Pure-Nim terminal status models and rendering.
##
## Phase 1 exposes shared model contracts and the pure spinner model. Importing
## this façade performs no output, terminal detection, or background work.

import terminal_status/[spinners, types]

export spinners, types
