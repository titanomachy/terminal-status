# TerminalStatus

TerminalStatus is a planned pure-Nim library for terminal spinners, single and
multi-progress bars, and ordered task step-trackers. The implementation is
currently in Phase 0: its public API is still the Nimble scaffold while the
repository contract and generated-output policy are established.

The `0.1.x` line requires Nim 2.2.10 or newer and will build on
`terminal_style >= 0.1.1` and `terminal_screen >= 0.1.1`. The normative design
and API contracts live in [`specs/`](specs/).

## Development

Compiler products, caches, test executables, and generated documentation must
remain under `build/`. Hand-written source, tests, examples, and documentation
remain in their normal repository directories.

```sh
nimble check
nim c --path:src src/terminal_status.nim
nimble test
nimble docs
```

The documentation task writes generated API documentation and indexes to
`build/docs/`; it does not create the conventional `htmldocs/` directory.
