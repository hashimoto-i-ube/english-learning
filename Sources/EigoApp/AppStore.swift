import EigoCore
import Foundation
import Observation

/// アプリ全体の状態（コンテンツ・進捗・設定・更新）
@MainActor
@Observable
final class AppStore {
    private(set) var dataDirectory: URL
    private(set) var library = ContentLibrary()
    var progress = LearnerProgress()
    var statusMessage: String?
    var isUpdating = false
    var availableRelease: AppUpdateChecker.Release?
    var lastSaveError: String?

    private var progressFile: ProgressFile
    private var sessionStart = Date()

    init() {
        let dir = DataLocation.resolve()
        dataDirectory = dir
        progressFile = ProgressFile(directory: dir)
        try? DataLocation.ensure(dir)
        progress = progressFile.load()
        reloadContent()
    }

    // MARK: - 情報

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var planner: StudyPlanner { StudyPlanner(library: library, progress: progress) }

    var downloadedContentDirectory: URL { dataDirectory.appendingPathComponent("content/packs", isDirectory: true) }

    /// アプリ同梱のコンテンツ。開発中（swift run）はリポジトリの Content/packs を探す。
    var bundledContentDirectory: URL? {
        if let env = ProcessInfo.processInfo.environment["EIGO_CONTENT_DIR"] {
            return URL(fileURLWithPath: env).appendingPathComponent("packs")
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Content/packs"),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("Content/packs")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    var contentBaseURL: URL? {
        let s = progress.settings.contentBaseURL.isEmpty
            ? (Bundle.main.object(forInfoDictionaryKey: "EigoContentBaseURL") as? String ?? "")
            : progress.settings.contentBaseURL
        return s.isEmpty ? nil : URL(string: s)
    }

    var githubRepository: String {
        progress.settings.githubRepository.isEmpty
            ? (Bundle.main.object(forInfoDictionaryKey: "EigoGitHubRepository") as? String ?? "")
            : progress.settings.githubRepository
    }

    // MARK: - コンテンツ

    func reloadContent() {
        var dirs: [URL] = []
        if let b = bundledContentDirectory { dirs.append(b) }
        dirs.append(downloadedContentDirectory)
        library = ContentLibrary(directories: dirs)
    }

    func updateContent() async {
        guard let base = contentBaseURL else {
            statusMessage = "コンテンツ配信元URLが未設定です（設定 > 更新）。"
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        let installed = Dictionary(library.packs.map { ($0.id, $0.revision) }, uniquingKeysWith: max)
        let updater = ContentUpdater(baseURL: base, destination: downloadedContentDirectory, appVersion: appVersion)
        do {
            let r = try await updater.update(installed: installed)
            reloadContent()
            if r.updated.isEmpty {
                statusMessage = "コンテンツは最新です（配信 \(r.manifestDate.prefix(10))）。"
            } else {
                statusMessage = "\(r.updated.count) 件のコンテンツを更新しました: " + r.updated.joined(separator: "、")
            }
            if !r.skippedIncompatible.isEmpty {
                statusMessage! += "（アプリ更新が必要な項目: \(r.skippedIncompatible.count) 件）"
            }
        } catch {
            statusMessage = "更新に失敗しました: \(error.localizedDescription)"
        }
    }

    func checkAppUpdate() async {
        let repo = githubRepository
        guard !repo.isEmpty else { return }
        availableRelease = try? await AppUpdateChecker(repository: repo).check(currentVersion: appVersion)
    }

    /// 起動時：1日1回だけ自動でコンテンツとアプリの更新を確認
    func startupChecks() async {
        let key = "lastAutoUpdateCheck"
        let today = LearnerProgress.dayKey()
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        if contentBaseURL != nil { await updateContent() }
        await checkAppUpdate()
    }

    // MARK: - 記録

    func record(_ item: StudyItem, grade: ReviewGrade) {
        progress.record(key: item.key, grade: grade, skill: item.skill)
        save()
    }

    func markUnitCompleted(_ id: String) {
        progress.completedUnits.insert(id)
        save()
    }

    func toggleBookmark(_ key: String) {
        if progress.bookmarks.contains(key) { progress.bookmarks.remove(key) } else { progress.bookmarks.insert(key) }
        save()
    }

    func addComposition(_ a: CompositionAttempt) {
        progress.compositions.append(a)
        save()
    }

    func updateComposition(_ a: CompositionAttempt) {
        if let i = progress.compositions.firstIndex(where: { $0.id == a.id }) { progress.compositions[i] = a } else { progress.compositions.append(a) }
        save()
    }

    func addReading(_ r: ReadingRecord) {
        progress.readings.append(r)
        save()
    }

    /// 学習時間を記録（セッション終了時に呼ぶ）
    func flushStudyTime() {
        let minutes = Date().timeIntervalSince(sessionStart) / 60
        if minutes > 0.2 && minutes < 240 { progress.addMinutes(minutes) }
        sessionStart = Date()
        save()
    }

    func beginStudy() { sessionStart = Date() }

    func save() {
        do {
            try progressFile.save(progress)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    // MARK: - 設定

    func setDataDirectory(_ url: URL) {
        // 現在の進捗を新しい場所へ書き出してから切り替える
        UserDefaults.standard.set(url.path, forKey: DataLocation.defaultsKey)
        dataDirectory = url
        progressFile = ProgressFile(directory: url)
        try? DataLocation.ensure(url)
        let existing = progressFile.load()
        if existing.cards.isEmpty && existing.daily.isEmpty { save() } else { progress = existing }
        reloadContent()
    }

    var apiKey: String {
        get { KeychainStore.load(account: "anthropic") ?? "" }
        set { KeychainStore.save(newValue, account: "anthropic") }
    }
}
