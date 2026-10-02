import AppKit
import Foundation
import Observation
import Security

// MARK: - Merging

/// Settings that aren't individual items. They're merged three ways against the
/// copy from the last successful sync, so a change on either device wins.
struct SyncMeta: Codable, Equatable {
    var contexts: [String]
    var lastReview: Date?
    var reviewChecks: [String]
}

protocol SyncItem: Identifiable where ID == UUID {
    var updatedAt: Date { get set }
}

extension TaskItem: SyncItem {}
extension Project: SyncItem {}

extension AppData {
    var meta: SyncMeta { SyncMeta(contexts: contexts, lastReview: lastReview, reviewChecks: reviewChecks) }

    /// Combines two copies of the data:
    /// - each task or project keeps whichever copy was edited most recently,
    /// - anything deleted on either side stays deleted,
    /// - settings take the side that changed since `base` (local wins if both did).
    static func merge(local: AppData, remote: AppData, base: SyncMeta?) -> AppData {
        var out = local
        out.deleted = local.deleted.merging(remote.deleted) { max($0, $1) }
        // Forget deletions after 90 days to keep the file small.
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        out.deleted = out.deleted.filter { $0.value > cutoff }

        out.tasks = mergeItems(local.tasks, remote.tasks, deleted: out.deleted)
        out.projects = mergeItems(local.projects, remote.projects, deleted: out.deleted)

        let meta = (base == nil || local.meta != base) ? local.meta : remote.meta
        out.contexts = meta.contexts
        out.lastReview = meta.lastReview
        out.reviewChecks = meta.reviewChecks
        return out
    }

    /// What changed between two copies, for the sync commit message,
    /// e.g. "1 added, 2 completed". The web app's `summary` in core.js matches this.
    static func summary(from old: AppData?, to new: AppData) -> String {
        let before = Dictionary((old?.tasks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0, completed = 0, trashed = 0, edited = 0
        for t in new.tasks {
            guard let was = before[t.id] else { added += 1; continue }
            if t == was { continue }
            if was.completedAt == nil && t.completedAt != nil { completed += 1 }
            else if was.trashedAt == nil && t.trashedAt != nil { trashed += 1 }
            else { edited += 1 }
        }
        let newIDs = Set(new.tasks.map(\.id))
        let deleted = before.keys.filter { !newIDs.contains($0) }.count
        let oldProjects = Dictionary((old?.projects ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let projects = new.projects.filter { oldProjects[$0.id] != $0 }.count
        let parts = [(added, "added"), (completed, "completed"), (edited, "edited"), (trashed, "trashed"),
                     (deleted, "deleted")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
            + (projects > 0 ? ["\(projects) project\(projects == 1 ? "" : "s") changed"] : [])
        return parts.isEmpty ? "settings changed" : parts.joined(separator: ", ")
    }

    private static func mergeItems<T: SyncItem>(_ local: [T], _ remote: [T], deleted: [String: Date]) -> [T] {
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let localIDs = Set(local.map(\.id))
        // Keep local order, then add items that only exist remotely.
        var merged = local.map { item in
            if let other = remoteByID[item.id], other.updatedAt > item.updatedAt { return other }
            return item
        }
        merged += remote.filter { !localIDs.contains($0.id) }
        return merged.filter { deleted[$0.id.uuidString] == nil }
    }
}

// MARK: - Token storage

enum Keychain {
    private static let service = "Satori Sync"
    private static let account = "github-token"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Sync with a private GitHub repo

/// Keeps `data.json` in a private GitHub repository in step with this Mac.
/// The web app on the phone syncs with the same file.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case off
        case syncing
        case synced(Date)
        case failed(String)
    }

    var status: Status = .off
    var enabled: Bool { didSet { if allowed { defaults.set(enabled, forKey: "syncEnabled") }; restart() } }
    var repo: String { didSet { if allowed { defaults.set(repo, forKey: "syncRepo") }; remoteCache = nil } }
    var token: String { didSet { if allowed { Keychain.write(token) }; remoteCache = nil } }
    /// False when using a separate data folder (SATORI_DATA_DIR): sync never runs there.
    @ObservationIgnored let allowed: Bool

    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pending: DispatchWorkItem?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    /// The last copy fetched from GitHub. Checking it with its ETag is free when nothing changed,
    /// which is what makes polling every few seconds affordable.
    @ObservationIgnored private var remoteCache: (etag: String, data: AppData, sha: String)?

    private var baseMeta: SyncMeta? {
        get { defaults.data(forKey: "syncBaseMeta").flatMap { try? Store.decoder.decode(SyncMeta.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? Store.encoder.encode($0) }, forKey: "syncBaseMeta") }
    }

    var isConfigured: Bool { allowed && enabled && repo.contains("/") && !token.isEmpty }

    nonisolated static let webAppURL = "https://emcee5000.github.io/satori/app/"

    /// Opens the phone app with this repo and token filled in. They travel in the
    /// URL fragment, which browsers never send to the server.
    var setupLink: URL? { isConfigured ? Self.setupLink(repo: repo, token: token) : nil }

    nonisolated static func setupLink(repo: String, token: String) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let json = try? encoder.encode(["repo": repo, "token": token]) else { return nil }
        let code = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: Self.webAppURL + "#connect=" + code)
    }

    init(allowed: Bool = true) {
        self.allowed = allowed
        enabled = allowed && UserDefaults.standard.bool(forKey: "syncEnabled")
        repo = allowed ? UserDefaults.standard.string(forKey: "syncRepo") ?? "" : ""
        token = allowed ? Keychain.read() ?? "" : ""
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(after: 0.5) }
        }
    }

    /// Starts polling once the store is attached.
    func restart() {
        timer?.invalidate()
        timer = nil
        guard isConfigured else { status = .off; return }
        // Check for changes from the phone every few seconds. Unchanged checks cost nothing.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        schedule(after: 0.5)
    }

    private func poll() {
        // Leave a pending upload of local changes to run on its own schedule.
        guard pending == nil || pending!.isCancelled else { return }
        Task { await syncNow() }
    }

    /// Syncs shortly after local changes settle.
    func schedule(after delay: TimeInterval = 1) {
        guard isConfigured else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.pending = nil
                await self?.syncNow()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func syncNow() async {
        guard isConfigured, let store else { return }
        if running { again = true; return }
        running = true
        // Only show "syncing…" until the first success, so quiet checks don't flicker.
        if case .synced = status {} else { status = .syncing }
        defer {
            running = false
            if again { again = false; schedule(after: 1) }
        }

        do {
            for _ in 0..<3 {
                let (remote, sha) = try await fetch()
                let merged = remote.map { AppData.merge(local: store.data, remote: $0, base: baseMeta) } ?? store.data
                if merged != store.data { store.applySynced(merged) }

                if remote == nil || canonical(merged) != canonical(remote!) {
                    do {
                        try await push(merged, sha: sha, summary: AppData.summary(from: remote, to: merged))
                        remoteCache = nil
                    } catch SyncError.conflict {
                        remoteCache = nil
                        continue // someone else wrote first; fetch and merge again
                    }
                }
                baseMeta = merged.meta
                status = .synced(Date())
                return
            }
            throw SyncError.message("Kept conflicting with another device. Try again.")
        } catch {
            status = .failed((error as? SyncError)?.description ?? error.localizedDescription)
        }
    }

    // MARK: GitHub contents API

    private enum SyncError: Error, CustomStringConvertible {
        case conflict
        case message(String)
        var description: String {
            switch self {
            case .conflict: "Conflict"
            case .message(let m): m
            }
        }
    }

    private var fileURL: URL {
        URL(string: "https://api.github.com/repos/\(repo.trimmingCharacters(in: .whitespaces))/contents/data.json")!
    }

    private func request(_ method: String, body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: fileURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        r.httpMethod = method
        r.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.httpBody = body
        return r
    }

    private func fetch() async throws -> (AppData?, String?) {
        var get = request("GET")
        if let cached = remoteCache { get.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await URLSession.shared.data(for: get)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if code == 304, let cached = remoteCache { return (cached.data, cached.sha) }
        remoteCache = nil
        if code == 404 { return (nil, nil) } // first sync: nothing there yet
        try check(code)
        struct File: Decodable { let sha: String; let content: String }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard let raw = Data(base64Encoded: file.content.replacingOccurrences(of: "\n", with: "")) else {
            throw SyncError.message("Couldn't read data.json from GitHub.")
        }
        do {
            let decoded = try Store.decoder.decode(AppData.self, from: raw)
            if let etag = http?.value(forHTTPHeaderField: "ETag") { remoteCache = (etag, decoded, file.sha) }
            return (decoded, file.sha)
        } catch {
            throw SyncError.message("data.json on GitHub isn't valid Satori data.")
        }
    }

    private func push(_ appData: AppData, sha: String?, summary: String) async throws {
        struct Body: Encodable { let message: String; let content: String; let sha: String? }
        let host = Host.current().localizedName ?? "Mac"
        let body = Body(message: "Sync from \(host): \(summary)", content: try Store.encoder.encode(appData).base64EncodedString(), sha: sha)
        let (_, response) = try await URLSession.shared.data(for: request("PUT", body: try JSONEncoder().encode(body)))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 409 || code == 422 { throw SyncError.conflict }
        try check(code)
    }

    private func check(_ code: Int) throws {
        switch code {
        case 200...299: return
        case 401: throw SyncError.message("GitHub rejected the token. Check it in Settings.")
        case 403: throw SyncError.message("The token can't write to this repo. It needs Contents: read and write.")
        case 404: throw SyncError.message("Repo not found. Check the name and the token's repo access.")
        default: throw SyncError.message("GitHub returned an error (\(code)).")
        }
    }

    private func canonical(_ d: AppData) -> Data { (try? Store.encoder.encode(d)) ?? Data() }
}
