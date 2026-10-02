import Foundation
@testable import Satori

/// Local midnight on a "yyyy-MM-dd" day.
func day(_ text: String) -> Date {
    let parts = text.split(separator: "-").map { Int($0)! }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
}

func dayString(_ date: Date?) -> String? {
    guard let date else { return nil }
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

/// The cases shared with the web app's tests, in Tests/fixtures.
func fixture(_ name: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/\(name).json")
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}

func task(_ title: String, updated: Date = Date(timeIntervalSince1970: 1_000), _ change: (inout TaskItem) -> Void = { _ in }) -> TaskItem {
    var t = TaskItem(title: title)
    t.createdAt = updated
    t.updatedAt = updated
    change(&t)
    return t
}
