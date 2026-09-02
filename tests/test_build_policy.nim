import std/[os, strutils, unittest]

let repositoryDir = currentSourcePath().parentDir.parentDir
let buildDir = repositoryDir / "build"

proc isWithin(path, parent: string): bool =
  let relative = relativePath(path.absolutePath, parent.absolutePath)
  relative != ".." and not relative.startsWith(".." & $DirSep)

proc isCompilerArtifact(path: string): bool =
  const generatedExtensions = [".dll", ".dylib", ".exe", ".o", ".obj", ".so"]
  let (directory, name, extension) = path.splitFile
  extension.toLowerAscii in generatedExtensions or
    path.endsWith(".nim.c") or
    (extension.len == 0 and fileExists(directory / (name & ".nim"))) or
    (DirSep & "nimcache" & DirSep) in path

proc compilerArtifactsOutsideBuild(): seq[string] =
  for kind, path in walkDir(repositoryDir):
    if kind in {pcFile, pcLinkToFile} and path.isCompilerArtifact:
      result.add relativePath(path, repositoryDir)

  for sourceDir in ["src", "tests", "examples", "docs"]:
    let absoluteSourceDir = repositoryDir / sourceDir
    if not dirExists(absoluteSourceDir):
      continue
    for path in walkDirRec(absoluteSourceDir):
      if path.isCompilerArtifact:
        result.add relativePath(path, repositoryDir)

suite "repository build policy":
  test "test executables are emitted beneath build":
    check getAppFilename().isWithin(buildDir)

  test "compiler products do not leak into the repository root or sources":
    check compilerArtifactsOutsideBuild() == newSeq[string]()

  test "root and test compiler configurations target build":
    let rootConfig = readFile(repositoryDir / "config.nims")
    let testConfig = readFile(repositoryDir / "tests" / "config.nims")
    check "switch(\"outDir\", buildDir)" in rootConfig
    check "buildDir / \"nimcache\" / (\"nim-\" & NimVersion)" in rootConfig
    check "switch(\"outDir\", testBuildDir)" in testConfig
    check "testBuildDir / \"nimcache\" / (\"nim-\" & NimVersion)" in testConfig

  test "Git and Nimble exclude generated and planning directories":
    let ignoreRules = readFile(repositoryDir / ".gitignore").splitLines
    let packageMetadata = readFile(repositoryDir / "terminal_status.nimble")
    check "/build/" in ignoreRules
    check "skipDirs      = @[\"build\", \"PLANS\", \"specs\"]" in packageMetadata

  test "package constraints match the Phase 0 contract":
    let packageMetadata = readFile(repositoryDir / "terminal_status.nimble")
    check "requires \"nim >= 2.2.10\"" in packageMetadata
    check "requires \"https://github.com/titanomachy/terminal-screen.git >= 0.1.1\"" in packageMetadata
    check "requires \"terminal_style >= 0.1.1\"" in packageMetadata

  test "documentation output stays beneath build":
    let packageMetadata = readFile(repositoryDir / "terminal_status.nimble")
    check "--outdir:build/docs" in packageMetadata
    check not dirExists(repositoryDir / "htmldocs")
