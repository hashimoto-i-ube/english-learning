import CryptoKit
import Foundation

/// GitHub 上の Content/manifest.json を参照し、新しい revision のパックだけをダウンロードする。
/// アプリ本体を更新しなくても、単語・問題・入試情報を最新に保てる。
public struct ContentUpdater: Sendable {
    public struct Result: Sendable {
        public var updated: [String]
        public var skippedIncompatible: [String]
        public var manifestDate: String
    }

    public enum UpdateError: Error, LocalizedError {
        case http(Int, String)
        case checksumMismatch(String)
        case appTooOld(String)

        public var errorDescription: String? {
            switch self {
            case let .http(code, url): return "ダウンロードに失敗しました (HTTP \(code)): \(url)"
            case let .checksumMismatch(id): return "チェックサム不一致のため破棄しました: \(id)"
            case let .appTooOld(v): return "最新コンテンツにはアプリ v\(v) 以上が必要です。アプリを更新してください。"
            }
        }
    }

    /// 例: https://raw.githubusercontent.com/<owner>/<repo>/main/Content
    public var baseURL: URL
    /// ダウンロード先（データディレクトリ/content/packs）
    public var destination: URL
    public var appVersion: String
    public var session: URLSession

    public init(baseURL: URL, destination: URL, appVersion: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.destination = destination
        self.appVersion = appVersion
        self.session = session
    }

    public func fetchManifest() async throws -> ContentManifest {
        let url = baseURL.appendingPathComponent("manifest.json")
        let data = try await get(url)
        return try JSONDecoder().decode(ContentManifest.self, from: data)
    }

    /// installed: パックID → 現在の revision（同梱・ダウンロード済みの最大値）
    public func update(installed: [String: Int]) async throws -> Result {
        let manifest = try await fetchManifest()
        if let min = manifest.minAppVersion, Self.compareVersions(appVersion, min) == .orderedAscending {
            throw UpdateError.appTooOld(min)
        }
        try DataLocation.ensure(destination)
        var updated: [String] = []
        var skipped: [String] = []
        for entry in manifest.packs where (installed[entry.id] ?? -1) < entry.revision {
            let data = try await get(baseURL.appendingPathComponent(entry.file))
            guard Self.sha256(data) == entry.sha256.lowercased() else {
                throw UpdateError.checksumMismatch(entry.id)
            }
            do {
                let pack = try ContentLibrary.decodePack(data: data)
                let out = destination.appendingPathComponent("\(pack.id).json")
                try data.write(to: out, options: .atomic)
                updated.append(entry.title)
            } catch {
                skipped.append(entry.id)
            }
        }
        return Result(updated: updated, skippedIncompatible: skipped, manifestDate: manifest.generatedAt)
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 30
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw UpdateError.http(code, url.absoluteString) }
        return data
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

/// GitHub Releases の最新版を確認する（アプリ本体の更新通知）
public struct AppUpdateChecker: Sendable {
    public struct Release: Decodable, Sendable {
        public var tag_name: String
        public var html_url: String
        public var body: String?
    }

    public var repository: String  // "owner/repo"

    public init(repository: String) { self.repository = repository }

    /// 新しいリリースがあれば返す
    public func check(currentVersion: String) async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }  // リリース未作成
        guard (200..<300).contains(code) else { throw ContentUpdater.UpdateError.http(code, url.absoluteString) }
        let rel = try JSONDecoder().decode(Release.self, from: data)
        return ContentUpdater.compareVersions(currentVersion, rel.tag_name) == .orderedAscending ? rel : nil
    }
}
