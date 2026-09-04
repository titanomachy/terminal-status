# Third-party notices

`terminal_status` contains original Nim code and incorporates no third-party
source code. Its built-in spinner frame sequences are common terminal animation
patterns implemented independently for this package.

The package uses the Nim standard library and these separately licensed MIT
packages:

- `terminal_style` for ANSI styling, safe control-sequence handling, grapheme
  truncation, and visible-cell measurement;
- `terminal_screen` for output capability detection and cursor command
  builders.

TerminalLayout and TerminalTable appear only in development-time composition
checks and are not runtime dependencies.

When adding incorporated or adapted third-party material, include its
copyright, license text, source URL, and affected files here.
