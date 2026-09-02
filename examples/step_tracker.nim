## A finite ordered step-tracker lifecycle with explicit timestamps.

import std/[monotimes, options, times]

import terminal_status

let started = getMonoTime()
var release = initStepTracker(
  ["Build package", "Run tests", "Publish archive"],
  title = "Release")

release.start(started)
release.setCurrentDetail("release mode")
release.advance(started + initDuration(milliseconds = 100))
release.advance(started + initDuration(milliseconds = 250))
release.setCurrentDetail("registry upload")
release.advance(started + initDuration(milliseconds = 400))

doAssert release.state == statusSucceeded
doAssert release.currentIndex.get == release.len - 1
doAssert release.elapsed(started + initDuration(seconds = 2)).inMilliseconds == 400

echo release.title, ": ", release.state
for step in release.steps:
  echo "- ", step.label, ": ", step.state,
    (if step.detail.len > 0: " (" & step.detail & ")" else: "")
