import Foundation
import Observation

/// Undo for changes made on this Mac.
///
/// Each step remembers the previous version of only the to-dos and projects that
/// changed, not a snapshot of everything. Undoing therefore never rolls back
/// changes that arrived from the phone in the meantime, and the restored items
/// get a fresh edit time so sync carries the undo to the other device too.
@MainActor
@Observable
final class UndoHistory {
    struct Step {
        /// Previous versions by ID; `nil` means the item didn't exist before.
        var tasks: [UUID: TaskItem?] = [:]
        var projects: [UUID: Project?] = [:]
        var meta: SyncMeta?
        var at = Date()

        var isEmpty: Bool { tasks.isEmpty && projects.isEmpty && meta == nil }

        /// Changes between two copies of the data, as the steps needed to go back.
        static func between(_ old: AppData, _ new: AppData) -> Step {
            var step = Step()
            step.tasks = changes(old.tasks, new.tasks)
            step.projects = changes(old.projects, new.projects)
            if old.meta != new.meta { step.meta = old.meta }
            return step
        }

        private static func changes<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) -> [UUID: T?] where T.ID == UUID {
            let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var out: [UUID: T?] = [:]
            for id in Set(before.keys).union(after.keys) where before[id] != after[id] {
                out.updateValue(before[id], forKey: id)
            }
            return out
        }

        /// Folds a later step into this one, keeping the oldest version of each item.
        mutating func absorb(_ later: Step) {
            for (id, old) in later.tasks where tasks.index(forKey: id) == nil { tasks.updateValue(old, forKey: id) }
            for (id, old) in later.projects where projects.index(forKey: id) == nil { projects.updateValue(old, forKey: id) }
            if meta == nil { meta = later.meta }
            at = later.at
        }

        /// Restores the remembered versions and returns the step that reverses this.
        func apply(to data: inout AppData, now: Date = Date()) -> Step {
            var inverse = Step()
            inverse.tasks = Self.restore(tasks, in: &data.tasks, deleted: &data.deleted, now: now)
            inverse.projects = Self.restore(projects, in: &data.projects, deleted: &data.deleted, now: now)
            if let meta {
                inverse.meta = data.meta
                data.contexts = meta.contexts
                data.lastReview = meta.lastReview
                data.reviewChecks = meta.reviewChecks
            }
            return inverse
        }

        private static func restore<T: SyncItem & Equatable>(
            _ versions: [UUID: T?], in items: inout [T], deleted: inout [String: Date], now: Date
        ) -> [UUID: T?] {
            var inverse: [UUID: T?] = [:]
            for (id, old) in versions {
                let index = items.firstIndex { $0.id == id }
                inverse.updateValue(index.map { items[$0] }, forKey: id)
                if var old {
                    old.updatedAt = now
                    if let index { items[index] = old } else { items.append(old) }
                    deleted.removeValue(forKey: id.uuidString)
                } else if let index {
                    // Undoing an addition: delete it everywhere, so sync doesn't bring it back.
                    items.remove(at: index)
                    deleted[id.uuidString] = now
                }
            }
            return inverse
        }
    }

    /// Changes within this many seconds count as one step, so typing a title is one undo.
    static let coalesceWindow: TimeInterval = 1

    @ObservationIgnored private var undoStack: [Step] = []
    @ObservationIgnored private var redoStack: [Step] = []
    private(set) var canUndo = false
    private(set) var canRedo = false
    private let limit = 100

    func record(from old: AppData, to new: AppData, now: Date = Date()) {
        var step = Step.between(old, new)
        guard !step.isEmpty else { return }
        step.at = now
        if var last = undoStack.last, now.timeIntervalSince(last.at) < Self.coalesceWindow {
            last.absorb(step)
            undoStack[undoStack.count - 1] = last
        } else {
            undoStack.append(step)
            if undoStack.count > limit { undoStack.removeFirst() }
        }
        redoStack.removeAll()
        refresh()
    }

    func popUndo() -> Step? { defer { refresh() }; return undoStack.popLast() }
    func popRedo() -> Step? { defer { refresh() }; return redoStack.popLast() }

    func pushUndo(_ step: Step) {
        var step = step
        step.at = .distantPast // never coalesce with what comes next
        undoStack.append(step)
        refresh()
    }

    func pushRedo(_ step: Step) {
        redoStack.append(step)
        refresh()
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        refresh()
    }

    private func refresh() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
