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

task docs, "Generate terminal_status API documentation":
  exec "nim doc --skipParentCfg:on --project --index:on --outdir:build/docs --path:src src/terminal_status.nim"
