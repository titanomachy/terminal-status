import std/[monotimes, options, sequtils, times, unittest]

import terminal_status/progress
import terminal_status/types

let baseTime = getMonoTime()

proc at(milliseconds: int64): MonoTime =
  baseTime + initDuration(milliseconds = milliseconds)

suite "multi-progress":
  test "empty collection allocates stable insertion-ordered IDs":
    var multi = initMultiProgress()
    check multi.len == 0
    check multi.isEmpty
    check multi.taskIds == newSeq[TaskId]()
    check multi.tasks == newSeq[ProgressTaskSnapshot]()

    let first = multi.addTask("First", 4, now = at(0))
    let second = multi.addIndeterminateTask("Second", now = at(10))
    let third = multi.addTask("Third", 2, "files", at(20))
    check [first, second, third] == [TaskId(1), TaskId(2), TaskId(3)]
    check multi.taskIds == @[first, second, third]
    check multi.tasks.mapIt(it.label) == @["First", "Second", "Third"]

    multi.removeTask(second)
    let fourth = multi.addTask("Fourth", 1, now = at(30))
    check fourth == TaskId(4)
    check multi.taskIds == @[first, third, fourth]

  test "snapshots and returned sequences cannot mutate the collection":
    var multi = initMultiProgress()
    let id = multi.addTask("Download", 10, "files", at(0))
    var snapshots = multi.tasks
    var ids = multi.taskIds
    var single = multi.task(id)

    snapshots[0].label[0] = 'd'
    snapshots.add snapshots[0]
    ids[0] = TaskId(99)
    ids.add TaskId(100)
    single.unit = "changed"

    check multi.len == 1
    check multi.taskIds == @[id]
    check multi.task(id).label == "Download"
    check multi.task(id).unit == "files"

  test "delegated operations preserve single-bar semantics":
    var multi = initMultiProgress()
    let
      determinate = multi.addTask("Compile", 5, now = at(0))
      indeterminate = multi.addIndeterminateTask("Upload", now = at(0))

    multi.setLabel(determinate, "Build")
    multi.setUnit(determinate, "files")
    multi.advance(determinate, 2, at(100))
    multi.setCompleted(determinate, 4, at(200))
    check multi.task(determinate).label == "Build"
    check multi.task(determinate).unit == "files"
    check multi.task(determinate).completed == 4
    multi.complete(determinate, at(300))
    check multi.task(determinate).state == statusSucceeded
    check multi.task(determinate).finishedAt == some(at(300))

    expect StatusStateError:
      multi.advance(indeterminate, now = at(100))
    multi.fail(indeterminate, at(400))
    check multi.task(indeterminate).state == statusFailed

    let cancelled = multi.addTask("Cancel", 2, now = at(0))
    multi.cancel(cancelled, at(500))
    check multi.task(cancelled).state == statusCancelled

  test "unknown IDs never mutate collection state":
    var multi = initMultiProgress()
    let id = multi.addTask("Known", 3, now = at(0))
    let before = multi.tasks
    let missing = TaskId(999)

    for operation in 0 .. 8:
      expect UnknownTaskError:
        case operation
        of 0: discard multi.task(missing)
        of 1: multi.removeTask(missing)
        of 2: multi.setLabel(missing, "No")
        of 3: multi.setUnit(missing, "No")
        of 4: multi.advance(missing, now = at(10))
        of 5: multi.setCompleted(missing, 1, at(10))
        of 6: multi.complete(missing, at(10))
        of 7: multi.fail(missing, at(10))
        else: multi.cancel(missing, at(10))
      check multi.tasks == before
      check multi.taskIds == @[id]

  test "rejected task construction does not consume IDs":
    var multi = initMultiProgress()
    expect ValueError:
      discard multi.addTask("Bad", 0, now = at(0))
    expect ValueError:
      discard multi.addIndeterminateTask("  ", now = at(0))
    check multi.addTask("Good", 1, now = at(0)) == TaskId(1)

  test "new tasks may follow terminal tasks":
    var multi = initMultiProgress()
    let first = multi.addTask("First", 1, now = at(0))
    multi.advance(first, now = at(100))
    let second = multi.addIndeterminateTask("Second", now = at(200))
    check multi.task(first).state == statusSucceeded
    check multi.task(second).state == statusRunning
