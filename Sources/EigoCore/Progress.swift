import Foundation

/// SRS 項目のキー。種類ごとに名前空間を分ける。
public enum ItemKey {
    public static func word(_ id: String) -> String { "word:\(id)" }
    public static func exercise(_ id: String) -> String { "ex:\(id)" }

    public static func parse(_ key: String) -> (kind: String, id: String) {
        guard let i = key.firstIndex(of: ":") else { return ("", key) }
        return (String(key[..<i]), String(key[key.index(after: i)...]))
    }
}

public struct DailyStat: Codable, Hashable, Sendable {
    public var date: String          // yyyy-MM-dd
    public var reviews: Int = 0
    public var correct: Int = 0
    public var newItems: Int = 0
    public var minutes: Double = 0
    public var bySkill: [String: Int] = [:]

    public init(date: String) { self.date = date }
}

public struct CompositionAttempt: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var promptID: String
    public var date: Date
    public var text: String
    public var selfScore: Int?           // 0〜5
    public var aiFeedback: EssayFeedback?

    public init(promptID: String, date: Date, text: String, selfScore: Int? = nil, aiFeedback: EssayFeedback? = nil) {
        self.promptID = promptID; self.date = date; self.text = text; self.selfScore = selfScore; self.aiFeedback = aiFeedback
    }
}

public struct ReadingRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var passageID: String
    public var date: Date
    public var seconds: Double
    public var wordsPerMinute: Int
    public var correct: Int
    public var total: Int

    public init(passageID: String, date: Date, seconds: Double, wordsPerMinute: Int, correct: Int, total: Int) {
        self.passageID = passageID; self.date = date; self.seconds = seconds
        self.wordsPerMinute = wordsPerMinute; self.correct = correct; self.total = total
    }
}

public struct LearnerSettings: Codable, Hashable, Sendable {
    public var targetLevel: Level = .l7
    public var currentLevel: Level = .l1
    public var dailyNewWords: Int = 20
    public var dailyNewExercises: Int = 10
    public var contentBaseURL: String = ""
    public var githubRepository: String = ""
    public var aiModel: String = "claude-opus-5-5"
    public var aiEnabled: Bool = false
}

/// 学習者のすべての記録。JSON 1ファイルに保存（小さく、バックアップ・移行が容易）。
public struct LearnerProgress: Codable, Sendable {
    public var version: Int = 1
    public var cards: [String: SRSCard] = [:]
    public var daily: [String: DailyStat] = [:]
    public var compositions: [CompositionAttempt] = []
    public var readings: [ReadingRecord] = []
    public var completedUnits: Set<String> = []
    public var bookmarks: Set<String> = []
    public var settings = LearnerSettings()

    public init() {}

    public static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: 記録

    public mutating func record(key: String, grade: ReviewGrade, skill: Skill, now: Date = Date()) {
        let isNew = cards[key] == nil
        cards[key] = Scheduler.review(cards[key], grade: grade, now: now)
        let d = Self.dayKey(now)
        var s = daily[d] ?? DailyStat(date: d)
        s.reviews += 1
        if grade.isCorrect { s.correct += 1 }
        if isNew { s.newItems += 1 }
        s.bySkill[skill.rawValue, default: 0] += 1
        daily[d] = s
    }

    public mutating func addMinutes(_ minutes: Double, now: Date = Date()) {
        let d = Self.dayKey(now)
        var s = daily[d] ?? DailyStat(date: d)
        s.minutes += minutes
        daily[d] = s
    }

    // MARK: 集計

    public func dueKeys(now: Date = Date()) -> [String] {
        cards.filter { $0.value.due <= now }.sorted { $0.value.due < $1.value.due }.map(\.key)
    }

    public func newItemsToday(now: Date = Date()) -> Int { daily[Self.dayKey(now)]?.newItems ?? 0 }

    /// 連続学習日数
    public func streak(now: Date = Date()) -> Int {
        var count = 0
        var day = now
        let cal = Calendar.current
        // 今日まだ学習していなくても昨日まで続いていれば継続扱い
        if (daily[Self.dayKey(day)]?.reviews ?? 0) == 0 { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while (daily[Self.dayKey(day)]?.reviews ?? 0) > 0 {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    public func mastered(keys: [String]) -> Int { keys.filter { cards[$0]?.isMastered == true }.count }
    public func seen(keys: [String]) -> Int { keys.filter { cards[$0] != nil }.count }

    /// 間違いノート：直近で間違えた or 正答率の低い項目
    public func weakKeys() -> [String] {
        cards.filter { $0.value.isWeak || ($0.value.totalCount >= 3 && Double($0.value.correctCount) / Double($0.value.totalCount) < 0.6) }
            .sorted { $0.value.due < $1.value.due }
            .map(\.key)
    }
}

/// JSON ファイルへの保存・読み込み
public struct ProgressFile: Sendable {
    public var url: URL

    public init(directory: URL) { url = directory.appendingPathComponent("progress.json") }

    public func load() -> LearnerProgress {
        guard let data = try? Data(contentsOf: url) else { return LearnerProgress() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(LearnerProgress.self, from: data)
        } catch {
            // 読めないファイルは上書きせず退避しておく
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: aside)
            return LearnerProgress()
        }
    }

    public func save(_ p: LearnerProgress) throws {
        try DataLocation.ensure(url.deletingLastPathComponent())
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        // 上書き前に1世代バックアップ
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.deletingPathExtension().appendingPathExtension("backup.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        try enc.encode(p).write(to: url, options: .atomic)
    }
}

// MARK: - 前方互換デコード（項目追加時に既存データを失わないよう、欠けているキーは既定値）

extension LearnerSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LearnerSettings()
        targetLevel = try c.decodeIfPresent(Level.self, forKey: .targetLevel) ?? d.targetLevel
        currentLevel = try c.decodeIfPresent(Level.self, forKey: .currentLevel) ?? d.currentLevel
        dailyNewWords = try c.decodeIfPresent(Int.self, forKey: .dailyNewWords) ?? d.dailyNewWords
        dailyNewExercises = try c.decodeIfPresent(Int.self, forKey: .dailyNewExercises) ?? d.dailyNewExercises
        contentBaseURL = try c.decodeIfPresent(String.self, forKey: .contentBaseURL) ?? d.contentBaseURL
        githubRepository = try c.decodeIfPresent(String.self, forKey: .githubRepository) ?? d.githubRepository
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? d.aiModel
        aiEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? d.aiEnabled
    }
}

extension LearnerProgress {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        cards = try c.decodeIfPresent([String: SRSCard].self, forKey: .cards) ?? [:]
        daily = try c.decodeIfPresent([String: DailyStat].self, forKey: .daily) ?? [:]
        compositions = try c.decodeIfPresent([CompositionAttempt].self, forKey: .compositions) ?? []
        readings = try c.decodeIfPresent([ReadingRecord].self, forKey: .readings) ?? []
        completedUnits = try c.decodeIfPresent(Set<String>.self, forKey: .completedUnits) ?? []
        bookmarks = try c.decodeIfPresent(Set<String>.self, forKey: .bookmarks) ?? []
        settings = try c.decodeIfPresent(LearnerSettings.self, forKey: .settings) ?? LearnerSettings()
    }
}
