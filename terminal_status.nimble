# Package

version       = "0.1.0"
author        = "titanomachy"
description   = "Pure-Nim terminal spinners, single & multi-progress bars, task step-trackers."
license       = "MIT"
srcDir        = "src"
skipDirs      = @["build", "PLANS", "specs"]


# Dependencies

requires "nim >= 2.2.10"
requires "https://github.com/titanomachy/terminal-screen.git >= 0.1.1"
requires "terminal_style >= 0.1.1"


# Tasks

task suiteIntegration, "Run sibling-source and suite composition checks":
  exec "nim c -r tests/test_suite_integration.nim"

task docs, "Generate public API and focused module documentation":
  exec "nim doc --skipParentCfg:on --project --index:on --outdir:build/docs --path:src src/terminal_status.nim"
  exec "nim doc --skipParentCfg:on --index:on --outdir:build/docs --path:src src/terminal_status/types.nim"
  exec "nim doc --skipParentCfg:on --index:on --outdir:build/docs --path:src src/terminal_status/spinners.nim"
  exec "nim doc --skipParentCfg:on --index:on --outdir:build/docs --path:src src/terminal_status/progress.nim"
  exec "nim doc --skipParentCfg:on --index:on --outdir:build/docs --path:src src/terminal_status/steps.nim"
  exec "nim doc --skipParentCfg:on --index:on --outdir:build/docs --path:src src/terminal_status/themes.nim"
  exec "nim doc --skipParentCfg:on --index:on --outdir:build/docs --path:src src/terminal_status/rendering.nim"
  exec "nim doc --skipParentCfg:on --index:on --outdir:build/docs --path:src src/terminal_status/live.nim"
  exec "nim buildIndex --skipParentCfg:on --out:build/docs/theindex.html build/docs"
