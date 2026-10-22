import Foundation

/// 学習セッションで出題する1項目
public enum StudyItem: Identifiable, Hashable, Sendable {
    case word(Word)
    case exercise(Exercise, skill: Skill)

    public var id: String { key }

    public var key: String {
        switch self {
        case let .word(w): return ItemKey.word(w.id)
        case let .exercise(e, _): return ItemKey.exercise(e.id)
        }
    }

    public var skill: Skill {
        switch self {
        case .word: return .vocabulary
        case let .exercise(_, s): return s
        }
    }
}

/// 「今日の学習」を組み立てる
public struct StudyPlanner {
    public var library: ContentLibrary
    public var progress: LearnerProgress

    public init(library: ContentLibrary, progress: LearnerProgress) {
        self.library = library
        self.progress = progress
    }

    /// キーから出題項目を復元（コンテンツ更新で消えた項目は除外）
    public func item(for key: String) -> StudyItem? {
        let (kind, id) = ItemKey.parse(key)
        switch kind {
        case "word": return library.word(id: id).map { .word($0) }
        case "ex":
            guard let e = library.exercise(id: id) else { return nil }
            return .exercise(e, skill: skill(ofExercise: id))
        default: return nil
        }
    }

    public func skill(ofExercise id: String) -> Skill {
        if let u = library.unit(containingExercise: id) {
            for (s, list) in library.units where list.contains(where: { $0.id == u.id }) { return s }
        }
        return .reading
    }

    /// 期限が来た復習項目
    public func dueItems(now: Date = Date(), skill: Skill? = nil) -> [StudyItem] {
        progress.dueKeys(now: now).compactMap(item(for:)).filter { skill == nil || $0.skill == skill }
    }

    /// 未学習の単語（現在レベル以下を優先し、レベル順）
    public func newWords(limit: Int, maxLevel: Level? = nil) -> [Word] {
        let lv = maxLevel ?? progress.settings.currentLevel
        return Array(library.words(upTo: lv).filter { progress.cards[ItemKey.word($0.id)] == nil }.prefix(limit))
    }

    /// 単元の未学習演習（自動採点できるもの優先）
    public func newExercises(skill: Skill, limit: Int) -> [StudyItem] {
        let lv = progress.settings.currentLevel
        var out: [StudyItem] = []
        for u in library.units(for: skill) where u.level <= lv {
            for e in u.exercises where progress.cards[ItemKey.exercise(e.id)] == nil {
                out.append(.exercise(e, skill: skill))
                if out.count >= limit { return out }
            }
        }
        return out
    }

    /// 今日のおすすめセッション：復習 → 新出単語 → 新出文法・構文
    public func todaysSession(now: Date = Date()) -> [StudyItem] {
        let s = progress.settings
        var items = dueItems(now: now)
        let remainingNew = max(0, s.dailyNewWords - progress.newItemsToday(now: now))
        items += newWords(limit: remainingNew).map { .word($0) }
        // 文法と構文を半分ずつ。現在レベルに単元がない分野の枠は他分野で埋める
        let perSkill = max(1, s.dailyNewExercises / 2)
        var exercises = newExercises(skill: .grammar, limit: perSkill)
        exercises += newExercises(skill: .construction, limit: s.dailyNewExercises - perSkill)
        for skill in [Skill.grammar, .construction, .knowledge] where exercises.count < s.dailyNewExercises {
            let have = Set(exercises.map(\.key))
            exercises += newExercises(skill: skill, limit: s.dailyNewExercises)
                .filter { !have.contains($0.key) }
                .prefix(s.dailyNewExercises - exercises.count)
        }
        items += exercises
        var seen = Set<String>()
        return items.filter { seen.insert($0.key).inserted }
    }

    /// 技能別の進捗（学習済み数・定着数・総数）
    public func coverage(skill: Skill) -> (seen: Int, mastered: Int, total: Int) {
        let keys: [String]
        switch skill {
        case .vocabulary: keys = library.words.map { ItemKey.word($0.id) }
        case .grammar, .construction, .knowledge:
            keys = library.units(for: skill).flatMap { $0.exercises }.map { ItemKey.exercise($0.id) }
        case .reading: keys = library.passages.flatMap { $0.questions }.map { ItemKey.exercise($0.id) }
        case .composition:
            let done = Set(progress.compositions.map(\.promptID))
            return (done.count, done.count, library.compositions.count)
        case .listening, .speaking: return (0, 0, 0)
        }
        return (progress.seen(keys: keys), progress.mastered(keys: keys), keys.count)
    }
}
