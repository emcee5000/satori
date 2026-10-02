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
    var updatedAt: Date { get }
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
    var enabled: Bool { didSet { defaults.set(enabled, forKey: "syncEnabled"); restart() } }
    var repo: String { didSet { defaults.set(repo, forKey: "syncRepo") } }
    var token: String { didSet { Keychain.write(token) } }

    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pending: DispatchWorkItem?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false

    private var baseMeta: SyncMeta? {
        get { defaults.data(forKey: "syncBaseMeta").flatMap { try? Store.decoder.decode(SyncMeta.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? Store.encoder.encode($0) }, forKey: "syncBaseMeta") }
    }

    var isConfigured: Bool { enabled && repo.contains("/") && !token.isEmpty }

    init() {
        enabled = UserDefaults.standard.bool(forKey: "syncEnabled")
        repo = UserDefaults.standard.string(forKey: "syncRepo") ?? ""
        token = Keychain.read() ?? ""
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
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(after: 0) }
        }
        schedule(after: 0.5)
    }

    /// Syncs shortly after local changes settle.
    func schedule(after delay: TimeInterval = 3) {
        guard isConfigured else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.syncNow() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func syncNow() async {
        guard isConfigured, let store else { return }
        if running { again = true; return }
        running = true
        status = .syncing
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
                        try await push(merged, sha: sha)
                    } catch SyncError.conflict {
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
        let (data, response) = try await URLSession.shared.data(for: request("GET"))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return (nil, nil) } // first sync: nothing there yet
        try check(code)
        struct File: Decodable { let sha: String; let content: String }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard let raw = Data(base64Encoded: file.content.replacingOccurrences(of: "\n", with: "")) else {
            throw SyncError.message("Couldn't read data.json from GitHub.")
        }
        do {
            return (try Store.decoder.decode(AppData.self, from: raw), file.sha)
        } catch {
            throw SyncError.message("data.json on GitHub isn't valid Satori data.")
        }
    }

    private func push(_ appData: AppData, sha: String?) async throws {
        struct Body: Encodable { let message: String; let content: String; let sha: String? }
        let host = Host.current().localizedName ?? "Mac"
        let body = Body(message: "Sync from \(host)", content: try Store.encoder.encode(appData).base64EncodedString(), sha: sha)
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
