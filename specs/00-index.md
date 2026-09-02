# TerminalStatus specification index

These files are the implementation contract for TerminalStatus `0.1.x`. They
are intentionally more explicit than `PLANS/PLAN1.md` so the coding work can be
handed to a smaller implementation model without requiring it to redesign the
library.

Read and implement them in this order:

1. [`01-architecture.md`](01-architecture.md) — package boundary, module graph,
   dependency rules, and cross-cutting invariants.
2. [`02-models-and-api.md`](02-models-and-api.md) — normative public types,
   procedures, state machines, timing, and validation.
3. [`03-rendering.md`](03-rendering.md) — themes, exact textual forms, width
   behavior, ANSI safety, and responsive reduction.
4. [`04-live-output.md`](04-live-output.md) — terminal detection, redraw bytes,
   redirected output, cleanup, and scoped use.
5. [`05-quality-and-delivery.md`](05-quality-and-delivery.md) — required tests,
   examples, documentation, Nimble tasks, and definition of done.
6. [`06-build-policy.md`](06-build-policy.md) — generated-output locations and
   commands that must obey the repository build policy.

## Normative language

`MUST`, `MUST NOT`, `SHOULD`, and `MAY` are requirements in descending order.
Examples illustrate those requirements; they do not override them.

If two documents conflict, the more specific document wins. If they are equally
specific, the later-numbered document wins. Any implementation-driven change
to a public name, state transition, output rule, or build path must update the
affected spec and tests in the same change.

## Version and compatibility target

- Package line: `0.1.x`.
- Nim lower bound: preserve the repository's current `nim >= 2.2.10`.
- Required suite APIs: `terminal_style >= 0.1.1` and
  `terminal_screen >= 0.1.1`.
- Platforms: the same POSIX and Windows targets supported by TerminalScreen.
- Compiler mode: the package MUST compile without `--threads:on`.

## Scope shorthand

The phrase “component model” means `Spinner`, `ProgressBar`, `MultiProgress`,
or `StepTracker`. “Frame” means one or more `\n`-separated logical rows returned
by a pure renderer. “Terminal state” means a finite model state, not the
operating system's terminal input mode.

