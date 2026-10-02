import XCTest
@testable import Satori

/// Sync merging decides what survives when the Mac and the phone both change things,
/// so a mistake here silently loses to-dos.
@MainActor
final class MergeTests: XCTestCase {
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)

    func testNewestEditWinsForEachItem() {
        let a = task("Original", updated: old)
        var local = AppData(), remote = AppData()
        var localCopy = a, remoteCopy = a
        localCopy.title = "Edited on Mac"; localCopy.updatedAt = new
        remoteCopy.title = "Edited on phone"; remoteCopy.updatedAt = old
        local.tasks = [localCopy]
        remote.tasks = [remoteCopy]
        XCTAssertEqual(AppData.merge(local: local, remote: remote, base: nil).tasks.map(\.title), ["Edited on Mac"])

        localCopy.updatedAt = old; remoteCopy.updatedAt = new
        local.tasks = [localCopy]; remote.tasks = [remoteCopy]
        XCTAssertEqual(AppData.merge(local: local, remote: remote, base: nil).tasks.map(\.title), ["Edited on phone"])
    }

    func testItemsFromBothSidesAreKept() {
        var local = AppData(), remote = AppData()
        local.tasks = [task("Mac only")]
        remote.tasks = [task("Phone only")]
        let merged = AppData.merge(local: local, remote: remote, base: nil)
        XCTAssertEqual(merged.tasks.map(\.title), ["Mac only", "Phone only"])
    }

    func testDeletionsStickOnBothSides() {
        let gone = task("Deleted on phone")
        var local = AppData(), remote = AppData()
        local.tasks = [gone, task("Kept")]
        remote.deleted = [gone.id.uuidString: Date()]
        let merged = AppData.merge(local: local, remote: remote, base: nil)
        XCTAssertEqual(merged.tasks.map(\.title), ["Kept"])
        XCTAssertNotNil(merged.deleted[gone.id.uuidString])
    }

    func testOldDeletionsAreForgotten() {
        var local = AppData()
        local.deleted = ["recent": Date(), "ancient": Date().addingTimeInterval(-100 * 24 * 3600)]
        let merged = AppData.merge(local: local, remote: AppData(), base: nil)
        XCTAssertEqual(Set(merged.deleted.keys), ["recent"])
    }

    func testSettingsTakeTheSideThatChanged() {
        let base = AppData().meta
        var local = AppData(), remote = AppData()
        remote.contexts = ["@phone-only"]
        XCTAssertEqual(AppData.merge(local: local, remote: remote, base: base).contexts, ["@phone-only"])

        local.contexts = ["@mac-only"]
        XCTAssertEqual(AppData.merge(local: local, remote: remote, base: base).contexts, ["@mac-only"],
                       "when both changed, this Mac wins")
    }

    func testReadsTheWebAppsFormat() throws {
        // Written by the web app: no milliseconds, missing optional fields, a rule from a newer version.
        let json = """
        {"tasks":[
          {"id":"49548E33-173D-48E0-8D8A-4BE905BCC183","title":"From phone","bucket":"inbox","createdAt":"2026-10-02T20:03:25Z","updatedAt":"2026-10-02T20:03:25Z","repeatRule":"weekly"},
          {"id":"59548E33-173D-48E0-8D8A-4BE905BCC183","title":"Millis","createdAt":"2026-10-02T20:03:25.123Z","repeatRule":"fortnightly","someNewField":true}
        ],"projects":[],"deleted":{}}
        """
        let data = try Store.decoder.decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(data.tasks.count, 2)
        XCTAssertEqual(data.tasks[0].repeatRule, .weekly)
        XCTAssertNil(data.tasks[1].repeatRule, "unknown rules are ignored, not an error")
        XCTAssertEqual(data.tasks[1].updatedAt, data.tasks[1].createdAt)
        XCTAssertEqual(data.contexts, AppData().contexts)
    }

    func testRoundTripsThroughJSON() throws {
        var data = AppData.welcome
        data.tasks[0].repeatRule = .monthly
        data.tasks[0].due = day("2026-10-20")
        let decoded = try Store.decoder.decode(AppData.self, from: Store.encoder.encode(data))
        XCTAssertEqual(decoded.tasks.map(\.title), data.tasks.map(\.title))
        XCTAssertEqual(decoded.tasks[0].repeatRule, .monthly)
        XCTAssertEqual(decoded.tasks[0].due, day("2026-10-20"))
    }

    func testCommitSummaryDescribesChanges() {
        var before = AppData()
        let edited = task("Edit me"), done = task("Finish me"), removed = task("Delete me")
        before.tasks = [edited, done, removed]
        var after = before
        after.tasks[0].title = "Edited"
        after.tasks[1].completedAt = Date()
        after.tasks.remove(at: 2)
        after.tasks.append(task("New"))
        XCTAssertEqual(AppData.summary(from: before, to: after), "1 added, 1 completed, 1 edited, 1 deleted")
        XCTAssertEqual(AppData.summary(from: nil, to: after), "3 added")
        XCTAssertEqual(AppData.summary(from: after, to: after), "settings changed")
    }

    func testSetupLinkCarriesRepoAndToken() throws {
        let link = try XCTUnwrap(SyncService.setupLink(repo: "me/satori-data", token: "github_pat_abc+/="))
        XCTAssertTrue(link.absoluteString.hasPrefix("https://emcee5000.github.io/satori/app/#connect="))
        var code = String(link.absoluteString.split(separator: "=", maxSplits: 1)[1])
        XCTAssertFalse(code.contains("+") || code.contains("/") || code.contains("="), "URL-safe base64")
        code = code.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        code += String(repeating: "=", count: (4 - code.count % 4) % 4)
        let decoded = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(Data(base64Encoded: code)))
        XCTAssertEqual(decoded, ["repo": "me/satori-data", "token": "github_pat_abc+/="])
    }
}
