## Keep compiler-generated products beneath the package build directory.
import std/os

let buildDir = thisDir() / "build"
let isNimDocHelper = getCommand() == "js" and projectName() == "dochack"

if not isNimDocHelper:
  # Some Nim 2.x documentation commands compile this internal helper beside
  # its source. Public documentation tasks must still select build/docs.
  switch("outDir", buildDir)
  switch("nimcache", buildDir / "nimcache" / ("nim-" & NimVersion))

# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
