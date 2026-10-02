import XCTest
@testable import Satori

@MainActor
final class UndoTests: XCTestCase {
    func testUndoAndRedoAChange() {
        let store = makeStore()
        let id = store.addTask("Buy milk", to: .inbox)
        Thread.sleep(forTimeInterval: UndoHistory.coalesceWindow + 0.1)

        store.toggleComplete(id)
        XCTAssertTrue(store.task(id)!.isDone)
        store.undoLastChange()
        XCTAssertFalse(store.task(id)!.isDone)
        XCTAssertTrue(store.undo.canRedo)
        store.redoLastChange()
        XCTAssertTrue(store.task(id)!.isDone)
    }

    func testUndoingAnAdditionDeletesItEverywhere() {
        let store = makeStore()
        let id = store.addTask("Oops", to: .inbox)
        store.undoLastChange()
        XCTAssertNil(store.task(id))
        XCTAssertNotNil(store.data.deleted[id.uuidString], "so sync doesn't bring it back")
        store.redoLastChange()
        XCTAssertNotNil(store.task(id))
        XCTAssertNil(store.data.deleted[id.uuidString])
    }

    func testUndoLeavesChangesFromTheOtherDeviceAlone() {
        let store = makeStore()
        let mine = store.addTask("Mine", to: .inbox)
        // A change arrives from the phone after the local change.
        var synced = store.data
        synced.tasks.append(task("From phone"))
        store.applySynced(synced)

        store.undoLastChange()
        XCTAssertNil(store.task(mine))
        XCTAssertEqual(store.data.tasks.map(\.title), ["From phone"])
    }

    func testUndoGetsAFreshEditTimeSoItSyncs() {
        let store = makeStore()
        let id = store.addTask("Title", to: .inbox)
        Thread.sleep(forTimeInterval: UndoHistory.coalesceWindow + 0.1)
        store.update(id) { $0.title = "Renamed" }
        let renamedAt = store.task(id)!.updatedAt
        store.undoLastChange()
        XCTAssertEqual(store.task(id)!.title, "Title")
        XCTAssertGreaterThanOrEqual(store.task(id)!.updatedAt, renamedAt,
                                    "otherwise the newer copy on the phone would win and redo the rename")
    }

    func testQuickChangesAreOneStep() {
        let history = UndoHistory()
        var data = AppData()
        let start = Date()
        for (i, title) in ["H", "He", "Hello"].enumerated() {
            let old = data
            if data.tasks.isEmpty { data.tasks = [task(title)] } else { data.tasks[0].title = title }
            history.record(from: old, to: data, now: start.addingTimeInterval(Double(i) * 0.3))
        }
        var undone = data
        _ = history.popUndo()!.apply(to: &undone)
        XCTAssertTrue(undone.tasks.isEmpty, "typing a title quickly undoes in one go")
        XCTAssertFalse(history.canUndo)
    }

    func testCompletingARepeatingToDoUndoesInOneStep() {
        let store = makeStore()
        let id = store.addTask("Weekly review", to: .next)
        store.update(id) { $0.repeatRule = .weekly }
        Thread.sleep(forTimeInterval: UndoHistory.coalesceWindow + 0.1)
        store.toggleComplete(id)
        XCTAssertEqual(store.data.tasks.count, 2)
        store.undoLastChange()
        XCTAssertEqual(store.data.tasks.count, 1)
        XCTAssertFalse(store.task(id)!.isDone)
    }

    func testSearchFindsTitlesAndNotes() {
        let store = makeStore()
        let a = store.addTask("Call Bob about the lease", to: .next)
        let b = store.addTask("Groceries", to: .inbox)
        store.update(b) { $0.notes = "oat milk, bread" }
        store.toggleComplete(a)
        XCTAssertEqual(store.search("milk").tasks.map(\.id), [b])
        XCTAssertEqual(store.search("bob lease").tasks.map(\.id), [a])
        XCTAssertEqual(store.home(of: store.task(a)!), .logbook)
        XCTAssertTrue(store.search("  ").tasks.isEmpty)
    }

    func testRemindersArePlannedForOpenToDosDueLater() {
        var data = AppData()
        let now = day("2026-10-02").addingTimeInterval(8 * 3600) // 8 am
        data.tasks = [
            task("Due today") { $0.due = day("2026-10-02") },
            task("Due tomorrow") { $0.due = day("2026-10-03") },
            task("Overdue") { $0.due = day("2026-10-01") },
            task("Done") { $0.due = day("2026-10-03"); $0.completedAt = now },
            task("No date"),
        ]
        XCTAssertEqual(Reminders.plan(for: data, hour: 9, now: now).map(\.title), ["Due today", "Due tomorrow"])
        XCTAssertEqual(Reminders.plan(for: data, hour: 7, now: now).map(\.title), ["Due tomorrow"],
                       "today's 7 am reminder has already passed")
    }
}
