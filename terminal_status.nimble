import std/[algorithm, os, sequtils, strutils]

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

task compilePackage, "Compile the public facade":
  exec "nim c --path:src src/terminal_status.nim"

proc runTests(memoryManager = "") =
  var testFiles: seq[string]
  for testFile in listFiles("tests"):
    let name = testFile.extractFilename
    if name.startsWith("test_") and name.endsWith(".nim"):
      testFiles.add testFile
  testFiles.sort()

  let memoryManagerFlag =
    if memoryManager.len == 0: ""
    else: " --mm:" & memoryManager
  for testFile in testFiles:
    exec "nim c -r -d:terminalStatusTest" & memoryManagerFlag & " " &
      quoteShell(testFile)

task test, "Run the complete terminal_status test suite":
  runTests()

task testArc, "Run the complete test suite with ARC":
  runTests("arc")

task testOrc, "Run the complete test suite with ORC":
  runTests("orc")

task examples, "Check every standalone finite example":
  var exampleFiles: seq[string]
  for exampleFile in listFiles("examples"):
    if exampleFile.endsWith(".nim") and
        exampleFile.extractFilename != "interoperability.nim":
      exampleFiles.add exampleFile
  exampleFiles.sort()

  for exampleFile in exampleFiles:
    exec "nim check --path:src " & quoteShell(exampleFile)
  exec "nim check --path:src -d:focusedImports examples/api_facade.nim"

task suiteIntegration, "Run sibling-source and suite composition checks":
  exec "nim c -r tests/test_suite_integration.nim"
  let siblingDir = getCurrentDir().parentDir
  let integrationPaths = [
    siblingDir / "terminal-styles" / "src",
    siblingDir / "terminal-layout" / "src",
    siblingDir / "terminal-tables" / "src"
  ]
  if integrationPaths.allIt(dirExists(it)):
    exec "nim check --path:src --path:../terminal-styles/src" &
      " --path:../terminal-layout/src --path:../terminal-tables/src" &
      " examples/interoperability.nim"

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

task artifactPolicy, "Verify generated products remain beneath build":
  exec "nim c -r -d:terminalStatusTest tests/test_build_policy.nim"

task releaseCheck, "Run all standalone release-readiness checks":
  exec "nimble check"
  exec "nimble compilePackage"
  exec "nimble test"
  exec "nimble testArc"
  exec "nimble testOrc"
  exec "nimble examples"
  exec "nimble docs"
  exec "nimble artifactPolicy"
