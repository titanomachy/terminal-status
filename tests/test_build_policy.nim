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

  test "package constraints match the compatibility contract":
    let packageMetadata = readFile(repositoryDir / "terminal_status.nimble")
    check "requires \"nim >= 2.0.0\"" in packageMetadata
    check "requires \"terminal_screen >= 0.1.1\"" in packageMetadata
    check "requires \"terminal_style >= 0.1.1\"" in packageMetadata

  test "GitHub CI covers the supported compilers and operating systems":
    let workflowPath = repositoryDir / ".github" / "workflows" / "ci.yml"
    check fileExists(workflowPath)
    if fileExists(workflowPath):
      let workflow = readFile(workflowPath)
      for operatingSystem in [
        "ubuntu-latest", "macos-latest", "windows-latest"
      ]:
        check operatingSystem in workflow
      for compiler in ["2.0.0", "2.2.x", "stable"]:
        check compiler in workflow
      check "nimble install --depsOnly -y" in workflow
      check "nimble check -y" in workflow
      check "nimble test -y" in workflow
      check "nimble testArc -y" in workflow
      check "nimble testOrc -y" in workflow

  test "documentation output stays beneath build":
    let packageMetadata = readFile(repositoryDir / "terminal_status.nimble")
    check "--outdir:build/docs" in packageMetadata
    check not dirExists(repositoryDir / "htmldocs")

  test "required finite examples and documentation links remain present":
    const requiredExamples = [
      "spinner.nim",
      "progress_bar.nim",
      "indeterminate_bar.nim",
      "multi_progress.nim",
      "step_tracker.nim",
      "live_status.nim",
      "customization.nim",
      "redirected_output.nim"
    ]
    let readme = readFile(repositoryDir / "README.md")
    for exampleName in requiredExamples:
      check fileExists(repositoryDir / "examples" / exampleName)
      check ("examples/" & exampleName) in readme

    let liveExample = readFile(repositoryDir / "examples" / "live_status.nim")
    check "withLiveDisplay" in liveExample
    check ".update(" in liveExample
    check "plainFinalOnly" in
      readFile(repositoryDir / "examples" / "redirected_output.nim")

  test "the required focused test layout and memory-manager tasks remain present":
    for relativePath in [
      "tests/fixtures.nim",
      "tests/test_types.nim",
      "tests/test_spinners.nim",
      "tests/test_progress.nim",
      "tests/test_multi_progress.nim",
      "tests/test_steps.nim",
      "tests/test_rendering.nim",
      "tests/test_live_output.nim",
      "tests/test_imports.nim",
      "tests/test_suite_integration.nim",
      "tests/test_build_policy.nim"
    ]:
      check fileExists(repositoryDir / relativePath)

    let packageMetadata = readFile(repositoryDir / "terminal_status.nimble")
    check "-d:terminalStatusTest" in packageMetadata
    check "task test," in packageMetadata
    check "task testArc," in packageMetadata
    check "runTests(\"arc\")" in packageMetadata
    check "task testOrc," in packageMetadata
    check "runTests(\"orc\")" in packageMetadata

  test "release tasks and handoff documents remain complete":
    let packageMetadata = readFile(repositoryDir / "terminal_status.nimble")
    for taskName in [
      "compilePackage", "test", "testArc", "testOrc", "examples",
      "suiteIntegration", "docs", "artifactPolicy", "releaseCheck"
    ]:
      check ("task " & taskName & ",") in packageMetadata

    for releaseStep in [
      "nimble check -y", "nimble compilePackage", "nimble test",
      "nimble testArc", "nimble testOrc", "nimble examples", "nimble docs",
      "nimble artifactPolicy"
    ]:
      check ("exec \"" & releaseStep & "\"") in packageMetadata

    for document in [
      "CONTRIBUTING.md", "THIRD_PARTY_NOTICES.md"
    ]:
      check fileExists(repositoryDir / document)

    let readme = readFile(repositoryDir / "README.md")
    check "nimble releaseCheck" in readme
    check "CONTRIBUTING.md" in readme
    check "THIRD_PARTY_NOTICES.md" in readme

  test "correctness tests contain no timing sleeps":
    let sleepCall = "sl" & "eep"
    for testFile in walkFiles(repositoryDir / "tests" / "test_*.nim"):
      let source = readFile(testFile).toLowerAscii
      check sleepCall & "(" notin source
      check sleepCall & " (" notin source
