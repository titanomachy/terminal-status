# Contributing

Contributions are welcome through focused issues and pull requests.

## Development setup

TerminalStatus requires Nim 2.0.0 or newer, `terminal_style` 0.1.1 or newer,
and `terminal_screen` 0.1.1 or newer. Install the dependencies with Nimble, or
use sibling `terminal-styles` and `terminal-screen` checkouts while developing
the terminal suite.

From the package root, run the complete standalone gate:

```sh
nimble releaseCheck
```

This validates the package, compiles the public façade, runs the full test
suite under the default memory manager plus ARC and ORC, checks every
standalone finite example, generates API documentation beneath `build/docs/`,
and verifies that generated artifacts remain beneath `build/`.

When sibling TerminalLayout and TerminalTable repositories are available,
also run:

```sh
nimble suiteIntegration
```

## Change requirements

Keep models and renderers deterministic for caller-supplied monotonic times.
Models must not perform terminal I/O, and live output must remain explicitly
refreshed, single-thread owned, and safe for a borrowed stream. Use
TerminalStyle for ANSI/text width behavior and TerminalScreen for terminal
capability and cursor operations instead of duplicating either dependency.

New or changed public behavior needs:

- Nim `##` documentation covering validation, exceptions, time semantics,
  mutation, side effects, and ownership where relevant;
- deterministic focused tests with injected `MonoTime` values and isolated
  output captures;
- Unicode, ASCII, ANSI-disabled, hostile-control, and narrow-width cases when
  rendering is affected;
- a finite example plus corresponding README or hand-written guide updates;
  and
- an entry under `Unreleased` in `CHANGELOG.md`.

Keep all compiler, test-capture, and generated-documentation output under
`build/`. Correctness tests must not sleep or access the developer terminal.

By contributing, you agree that your contribution is licensed under the MIT
license in `LICENSE`. Do not submit code whose license is unknown or
incompatible. Record incorporated or adapted third-party material in
`THIRD_PARTY_NOTICES.md`.
