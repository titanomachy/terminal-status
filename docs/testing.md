# Deterministic testing

TerminalStatus separates model mutation, pure rendering, and borrowed-stream
output so each layer can be tested without a real terminal. The focused
modules under `tests/` follow the behavior matrix in
[`specs/05-quality-and-delivery.md`](../specs/05-quality-and-delivery.md).

## Time-driven models

Correctness tests import [`tests/fixtures.nim`](../tests/fixtures.nim) and pass
exact `MonoTime` offsets to constructors, mutations, metric queries, and
renderers. They never wait for a clock or assert elapsed-time ranges. A typical
test follows this shape:

```nim
let started = at(0)
var bar = initProgressBar("Compile", 10, now = started)
bar.setCompleted(4, at(2_000))

check bar.ratePerSecond(at(2_000)) == some(2.0)
check bar.eta(at(2_000)).get.inMilliseconds == 3_000
```

The finite [`deterministic_testing.nim`](../examples/deterministic_testing.nim)
example shows the same pattern using an application-owned monotonic base.

## Output isolation

Live-output tests borrow unique files beneath `build/test-tmp/`. Forced modes
avoid host capability assumptions, while the auto-mode case deliberately uses
a redirected file. Assertions compare exact bytes for redraw, row clearing,
plain-output coalescing, cursor ownership, finalization, invalid lifecycle
operations, and exception cleanup. The borrowed stream is never the developer's
terminal and remains usable after display close.

Import probes run in isolated processes and require empty output. Build-policy
tests also guard test discovery, generated-output placement, dependency bounds,
the absence of correctness sleeps, and the ARC/ORC task definitions.

## Commands

```sh
nimble test
nimble testArc
nimble testOrc
nimble suiteIntegration
```

All test executables, caches, nested probe binaries, and temporary captures are
written beneath `build/`. The default, ARC, and ORC tasks execute the same
sorted set of focused `test_*.nim` modules.
