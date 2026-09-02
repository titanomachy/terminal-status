## Test projects select this nearest config, so repeat the repository's build
## policy explicitly rather than relying on the parent config being loaded.
import std/os

let repositoryDir = thisDir() / ".."
let testBuildDir = repositoryDir / "build"

switch("path", repositoryDir / "src")
switch("outDir", testBuildDir)
switch("nimcache", testBuildDir / "nimcache" / ("nim-" & NimVersion))
