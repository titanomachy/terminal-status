# Build-output policy

All compiler-generated and documentation-generated products MUST live beneath
the repository's `build/` directory.

## Source versus generated files

Generated products include:

- compiled executables and libraries;
- C/JavaScript intermediates and Nim cache data;
- test and example executables;
- coverage data/reports;
- generated Nim API documentation and indexes;
- benchmark executables and temporary test captures.

Hand-written source, specs, plans, README content, examples, tests, and doc
sources are not build products and remain in their normal repository folders.
Nimble's dependency/develop metadata (`nimble.paths`, `nimble.develop`, and
`nimbledeps/`) is package-manager state rather than a compiler product; it is
ignored but is not redirected by compiler configuration.

## Repository configuration

The root `config.nims` is authoritative for direct package/example commands:

- `outDir = <repository>/build`;
- `nimcache = <repository>/build/nimcache/nim-<NimVersion>`;
- Nimble's generated `nimble.paths` include remains supported;
- Nim's internal `dochack` JavaScript helper is exempted from `outDir`
  redirection because some Nim 2.x doc commands require its output next to the
  helper source. The public generated documentation still uses an explicit
  `build/docs` destination.

`tests/config.nims` MUST independently set:

- source path to `<repository>/src`;
- output directory to `<repository>/build`;
- Nim cache to the same versioned cache directory beneath `build/`.

The independent test settings are required because a project-local tests
configuration can become the nearest configuration selected by Nim.

## Nimble package policy

The `.nimble` file MUST list `build`, `PLANS`, and `specs` in `skipDirs` so
generated output and development-only handoff documents are not installed as
runtime package contents. Future tasks MUST NOT use an output directory such as
`htmldocs`, repository root, `src`, `tests`, or `examples`.

Expected future destinations:

| Product | Destination |
| --- | --- |
| package/test/example binary | `build/` |
| Nim cache | `build/nimcache/nim-<NimVersion>/` |
| generated API docs | `build/docs/` |
| coverage raw data | `build/coverage/raw/` |
| coverage HTML/badge | `build/coverage/` |
| test captures | `build/test-tmp/` |

## Required verification

The configuration change is verified with:

```sh
nimble check
nim c --path:src src/terminal_status.nim
nimble test
```

Afterward:

- expected binaries/cache files are beneath `build/`;
- no `nimcache/`, executable, object, C intermediate, or generated docs exist
  in repository root, `src/`, `tests/`, `examples/`, or `docs/`;
- `git status --short --ignored` shows generated compiler output ignored only
  because it is beneath `build/`, not because broad extension globs conceal
  leaked artifacts.

The current scaffold test may be used only to verify output placement. Replacing
it with the implementation test suite is Phase 5 work from `PLAN1.md`.

## Future documentation command

When point-5 implementation/documentation work begins, use an explicit command
equivalent to:

```sh
nim doc --skipParentCfg:on --project --index:on \
  --outdir:build/docs --path:src src/terminal_status.nim
```

Focused modules may require additional `nim doc` calls with the same outdir,
followed by `nim buildIndex` writing into `build/docs/`. The `--skipParentCfg`
flag prevents root outdir settings from interfering with Nim's internal doc
helper; it does not authorize output outside `build/docs/`.

