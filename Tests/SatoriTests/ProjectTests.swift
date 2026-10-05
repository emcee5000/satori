import XCTest
@testable import Satori

@MainActor
final class ProjectTests: XCTestCase {
    private func project(with titles: [String], in store: Store) -> (UUID, [UUID]) {
        let pid = store.addProject("Kitchen shelves")
        return (pid, titles.map { store.addTask($0, to: .project(pid)) })
    }

    func testCompletingAProjectCompletesItsOpenToDos() {
        let store = makeStore()
        let (pid, ids) = project(with: ["Measure the wall", "Buy brackets"], in: store)
        store.completeProject(pid)
        XCTAssertNotNil(store.project(pid)?.completedAt)
        XCTAssertTrue(ids.allSatisfy { store.task($0)!.isDone })
    }

    func testCompletingAProjectIsOneUndoStep() {
        let store = makeStore()
        let (pid, ids) = project(with: ["Measure the wall", "Buy brackets"], in: store)
        Thread.sleep(forTimeInterval: UndoHistory.coalesceWindow + 0.1)
        store.completeProject(pid)
        store.undoLastChange()
        XCTAssertNil(store.project(pid)?.completedAt)
        XCTAssertTrue(ids.allSatisfy { !store.task($0)!.isDone })
    }

    func testAsksBeforeCompletingAProjectWithOpenToDos() {
        let store = makeStore()
        let (pid, _) = project(with: ["Measure the wall"], in: store)
        store.requestCompleteProject(pid)
        XCTAssertEqual(store.confirmCompleteProjectID, pid)
        XCTAssertNil(store.project(pid)?.completedAt, "nothing changes until confirmed")
    }

    func testCompletesAnEmptyProjectWithoutAsking() {
        let store = makeStore()
        let pid = store.addProject("Plan garden")
        store.requestCompleteProject(pid)
        XCTAssertNil(store.confirmCompleteProjectID)
        XCTAssertNotNil(store.project(pid)?.completedAt)
    }

    func testFinishingTheLastToDoAsksWhatsNext() {
        let store = makeStore()
        let (pid, ids) = project(with: ["Measure the wall", "Buy brackets"], in: store)
        store.toggleComplete(ids[0])
        XCTAssertNil(store.finishedProjectID, "one to-do is still open")
        store.toggleComplete(ids[1])
        XCTAssertEqual(store.finishedProjectID, pid)
    }

    func testReopeningDoesNotPrompt() {
        let store = makeStore()
        let (pid, ids) = project(with: ["Measure the wall"], in: store)
        store.toggleComplete(ids[0])
        store.finishedProjectID = nil
        store.toggleComplete(ids[0]) // mark incomplete again
        XCTAssertNil(store.finishedProjectID)
        store.reopenProject(pid)
        XCTAssertNil(store.project(pid)?.completedAt)
    }

    func testARepeatingLastToDoKeepsTheProjectGoing() {
        let store = makeStore()
        let (_, ids) = project(with: ["Water the fig tree"], in: store)
        store.update(ids[0]) { $0.repeatRule = .weekly }
        store.toggleComplete(ids[0])
        XCTAssertNil(store.finishedProjectID, "the next occurrence is still open")
    }

    func testKeyboardToggleCompletesThenReopens() {
        let store = makeStore()
        let pid = store.addProject("Plan garden")
        store.toggleProjectComplete(pid)
        XCTAssertNotNil(store.project(pid)?.completedAt)
        store.toggleProjectComplete(pid)
        XCTAssertNil(store.project(pid)?.completedAt)
        _ = store.addTask("Buy seeds", to: .project(pid))
        store.toggleProjectComplete(pid)
        XCTAssertEqual(store.confirmCompleteProjectID, pid, "still asks when there are open to-dos")
    }
}
