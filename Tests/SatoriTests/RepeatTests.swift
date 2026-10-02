import XCTest
@testable import Satori

@MainActor
final class RepeatTests: XCTestCase {
    func testNextDateMatchesSharedCases() throws {
        for c in try fixture("recurrence")["nextDate"] as! [[String: String]] {
            let rule = try XCTUnwrap(RepeatRule(rawValue: c["rule"]!))
            XCTAssertEqual(dayString(rule.next(after: day(c["from"]!))), c["next"], "\(c)")
        }
    }

    func testNextOccurrenceMatchesSharedCases() throws {
        for c in try fixture("recurrence")["nextOccurrence"] as! [[String: String]] {
            let name = c["name"]!
            let now = day(c["today"]!).addingTimeInterval(12 * 3600)
            let t = task("Repeat") {
                $0.repeatRule = RepeatRule(rawValue: c["rule"]!)
                $0.due = c["due"].map(day)
                $0.deferUntil = c["start"].map(day)
            }
            let next = try XCTUnwrap(t.nextOccurrence(now: now), name)
            XCTAssertEqual(dayString(next.due), c["nextDue"], name)
            XCTAssertEqual(dayString(next.deferUntil), c["nextStart"], name)
            XCTAssertNil(next.completedAt)
            XCTAssertNotEqual(next.id, t.id)
            XCTAssertEqual(next.repeatRule, t.repeatRule)
        }
    }

    func testNoRuleMeansNoNextOccurrence() {
        XCTAssertNil(task("Once").nextOccurrence())
    }

    func testCompletingARepeatingToDoAddsTheNextOne() {
        let store = makeStore()
        let id = store.addTask("Water plants", to: .next)
        store.update(id) { $0.repeatRule = .weekly; $0.due = .startOfToday }
        store.toggleComplete(id)
        let open = store.data.tasks.filter { $0.title == "Water plants" && !$0.isDone }
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.due, RepeatRule.weekly.next(after: .startOfToday))
        XCTAssertTrue(store.task(id)!.isDone)
    }
}

/// A store backed by a throwaway folder, so tests never touch real data.
@MainActor
func makeStore() -> Store {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("satori-tests-\(UUID().uuidString)")
    setenv("SATORI_DATA_DIR", dir.path, 1)
    let store = Store()
    store.data = AppData()
    store.undo.clear()
    return store
}
