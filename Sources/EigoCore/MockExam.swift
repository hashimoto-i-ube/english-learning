import Foundation

// MARK: - 模擬試験の構成

/// 模擬試験の大問
public enum ExamSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case vocabulary, grammar, construction, reading, composition

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .vocabulary: return "語彙"
        case .grammar: return "文法・語法"
        case .construction: return "英文解釈"
        case .reading: return "長文読解"
        case .composition: return "英作文"
        }
    }

    /// 配点（合計100点）
    public var weight: Double {
        switch self {
        case .vocabulary: return 15
        case .grammar: return 20
        case .construction: return 20
        case .reading: return 30
        case .composition: return 15
        }
    }
}

/// 1問（単語問題も Exercise に変換して扱う）
public struct ExamItem: Identifiable, Hashable, Sendable {
    public var id: String          // 試験内で一意
    public var exercise: Exercise
    public var sourceKey: String   // SRS 記録用（word:… / ex:…）
    public var skill: Skill

    public var isAutoGradable: Bool { exercise.isAutoGradable }
}

public struct ExamSection: Identifiable, Hashable, Sendable {
    public var kind: ExamSectionKind
    public var items: [ExamItem]
    public var passage: Passage?
    public var composition: CompositionPrompt?

    public var id: String { kind.rawValue }
}

public struct MockExam: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var level: Level
    public var timeLimitMinutes: Int
    public var sections: [ExamSection]
    public var createdAt: Date

    public var allItems: [ExamItem] { sections.flatMap(\.items) }

    public static func timeLimit(for level: Level) -> Int {
        switch level {
        case .l1: return 40
        case .l2: return 45
        case .l3: return 50
        case .l4: return 60
        case .l5: return 70
        case .l6: return 80
        case .l7: return 90
        }
    }

    /// 合格の目安（得点率）
    public static let passingRate = 0.7
}

// MARK: - 出題

/// 再現可能な乱数（seed が同じなら同じ試験になる）
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

public struct MockExamBuilder {
    public var library: ContentLibrary

    public init(library: ContentLibrary) { self.library = library }

    public func build(level: Level, seed: UInt64 = UInt64.random(in: 1...UInt64.max), now: Date = Date()) -> MockExam {
        var rng = SeededGenerator(seed: seed)
        var sections: [ExamSection] = []

        // 語彙：そのレベルの単語・熟語から意味の4択
        let vocabCount = level <= .l3 ? 15 : 20
        let words = pick(library.words.filter { $0.level == level }, count: vocabCount, using: &rng)
        let vocabItems = words.enumerated().map { i, w in
            ExamItem(id: "v\(i)", exercise: wordExercise(w, using: &rng), sourceKey: ItemKey.word(w.id), skill: .vocabulary)
        }
        if !vocabItems.isEmpty { sections.append(ExamSection(kind: .vocabulary, items: vocabItems)) }

        // 文法：自動採点できる問題（当該レベル優先、不足分は1つ下のレベル）
        let grammarItems = exercises(skill: .grammar, level: level, count: 10, autoOnly: true, prefix: "g", using: &rng)
        if !grammarItems.isEmpty { sections.append(ExamSection(kind: .grammar, items: grammarItems)) }

        // 英文解釈：構文（Lv1 は単元がないので基礎知識で代替）＋和訳1問
        var conItems = exercises(skill: .construction, level: level, count: 5, autoOnly: true, prefix: "c", using: &rng)
        if conItems.isEmpty {
            conItems = exercises(skill: .knowledge, level: level, count: 5, autoOnly: true, prefix: "c", using: &rng)
        }
        let translations = candidates(skill: .construction, level: level).filter { $0.type == .translateToJa }
        if let t = pick(translations, count: 1, using: &rng).first {
            conItems.append(ExamItem(id: "c-tr", exercise: t, sourceKey: ItemKey.exercise(t.id), skill: .construction))
        }
        if !conItems.isEmpty { sections.append(ExamSection(kind: .construction, items: conItems)) }

        // 長文：そのレベルの長文1題（設問すべて）
        let passages = library.passages.filter { $0.level == level }
        if let p = pick(passages.isEmpty ? library.passages.filter { $0.level <= level } : passages, count: 1, using: &rng).first {
            let items = p.questions.enumerated().map { i, q in
                ExamItem(id: "r\(i)", exercise: q, sourceKey: ItemKey.exercise(q.id), skill: .reading)
            }
            sections.append(ExamSection(kind: .reading, items: items, passage: p))
        }

        // 英作文：そのレベルの1題
        let prompts = library.compositions.filter { $0.level == level }
        if let c = pick(prompts.isEmpty ? library.compositions.filter { $0.level <= level } : prompts, count: 1, using: &rng).first {
            sections.append(ExamSection(kind: .composition, items: [], composition: c))
        }

        return MockExam(id: UUID(), level: level, timeLimitMinutes: MockExam.timeLimit(for: level), sections: sections, createdAt: now)
    }

    private func candidates(skill: Skill, level: Level) -> [Exercise] {
        library.units(for: skill).filter { $0.level == level }.flatMap(\.exercises)
    }

    private func exercises(skill: Skill, level: Level, count: Int, autoOnly: Bool, prefix: String,
                           using rng: inout SeededGenerator) -> [ExamItem] {
        func pool(_ lv: Level) -> [Exercise] {
            library.units(for: skill).filter { $0.level == lv }.flatMap(\.exercises)
                .filter { !autoOnly || $0.isAutoGradable }
        }
        var chosen = pick(pool(level), count: count, using: &rng)
        if chosen.count < count, let lower = Level(rawValue: level.rawValue - 1) {
            chosen += pick(pool(lower), count: count - chosen.count, using: &rng)
        }
        return chosen.enumerated().map { i, e in
            ExamItem(id: "\(prefix)\(i)", exercise: e, sourceKey: ItemKey.exercise(e.id), skill: skill)
        }
    }

    /// 単語を「意味として最も適切なもの」の4択問題に変換
    func wordExercise(_ w: Word, using rng: inout SeededGenerator) -> Exercise {
        let samePos = library.words.filter { $0.id != w.id && $0.pos == w.pos && $0.primaryMeaning != w.primaryMeaning }
        let pool = samePos.count >= 3 ? samePos : library.words.filter { $0.id != w.id && $0.primaryMeaning != w.primaryMeaning }
        var distractors: [String] = []
        for d in pool.shuffled(using: &rng) where !distractors.contains(d.primaryMeaning) {
            distractors.append(d.primaryMeaning)
            if distractors.count == 3 { break }
        }
        let choices = ([w.primaryMeaning] + distractors).shuffled(using: &rng)
        var explanation = "\(w.headword)：\(w.meanings.joined(separator: "；"))"
        if let ex = w.example { explanation += "\n例：\(ex.en)（\(ex.ja)）" }
        return Exercise(id: "exam-word-\(w.id)", type: .choice, prompt: "意味として最も適切なものを選びなさい。",
                        sentence: w.headword, choices: choices, answers: [w.primaryMeaning],
                        explanation: explanation, hint: nil, keyPoints: nil, level: w.level, tags: nil, media: nil)
    }

    private func pick<T>(_ items: [T], count: Int, using rng: inout SeededGenerator) -> [T] {
        Array(items.shuffled(using: &rng).prefix(count))
    }
}

// MARK: - 採点

public enum MockExamScorer {
    /// 自動採点（自己採点の問題は nil）
    public static func autoGrade(_ e: Exercise, answer: String) -> Bool? {
        switch e.type {
        case .choice: return e.answers.contains(answer)
        case .fill, .reorder: return AnswerChecker.isCorrect(answer, answers: e.answers)
        case .translateToEn: return AnswerChecker.isCorrect(answer, answers: e.answers) ? true : nil
        case .translateToJa, .shortAnswer: return nil
        }
    }

    /// 1問の得点（0〜1）。自己採点の問題は selfScores（0, 0.5, 1）を使い、未採点は0。
    public static func points(_ item: ExamItem, answer: String?, selfScore: Double?) -> Double {
        let a = answer ?? ""
        if let auto = autoGrade(item.exercise, answer: a) { return auto ? 1 : 0 }
        if a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        return min(max(selfScore ?? 0, 0), 1)
    }

    /// 大問ごとの得点（配点換算）
    public static func sectionScore(_ section: ExamSection, answers: [String: String], selfScores: [String: Double],
                                    compositionScore: Double?) -> Double {
        if section.kind == .composition {
            return section.kind.weight * min(max(compositionScore ?? 0, 0), 1)
        }
        guard !section.items.isEmpty else { return 0 }
        let total = section.items.reduce(0) { $0 + points($1, answer: answers[$1.id], selfScore: selfScores[$1.id]) }
        return section.kind.weight * total / Double(section.items.count)
    }

    /// 試験の満点（含まれる大問の配点合計）
    public static func maxScore(_ exam: MockExam) -> Double {
        exam.sections.reduce(0) { $0 + $1.kind.weight }
    }
}

// MARK: - 記録

public struct MockExamResult: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var level: Level
    public var seconds: Double
    public var timeLimitMinutes: Int
    public var score: Double
    public var maxScore: Double
    /// 大問ごとの得点（rawValue → 点）
    public var sectionScores: [String: Double]
    public var correctCount: Int
    public var questionCount: Int

    public init(id: UUID = UUID(), date: Date, level: Level, seconds: Double, timeLimitMinutes: Int, score: Double,
                maxScore: Double, sectionScores: [String: Double], correctCount: Int, questionCount: Int) {
        self.id = id; self.date = date; self.level = level; self.seconds = seconds; self.timeLimitMinutes = timeLimitMinutes
        self.score = score; self.maxScore = maxScore; self.sectionScores = sectionScores
        self.correctCount = correctCount; self.questionCount = questionCount
    }

    public var rate: Double { maxScore > 0 ? score / maxScore : 0 }
    public var passed: Bool { rate >= MockExam.passingRate }
}
