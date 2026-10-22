import Foundation

public enum ContentError: Error, LocalizedError {
    case unsupportedSchema(String, Int)
    case duplicateID(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(id, v): return "パック \(id) のスキーマ v\(v) はこのアプリでは未対応です。アプリを更新してください。"
        case let .duplicateID(id): return "IDが重複しています: \(id)"
        case let .invalid(msg): return msg
        }
    }
}

/// 読み込み済みの全コンテンツ。
/// 同梱パックとダウンロード済みパックを統合し、同じIDなら revision の大きい方を採用する。
public struct ContentLibrary: Sendable {
    public private(set) var packs: [ContentPack] = []
    public private(set) var loadErrors: [String] = []

    public private(set) var words: [Word] = []
    public private(set) var units: [Skill: [StudyUnit]] = [:]
    public private(set) var compositions: [CompositionPrompt] = []
    public private(set) var passages: [Passage] = []
    public private(set) var notices: [Notice] = []

    private var exerciseIndex: [String: Exercise] = [:]
    private var wordIndex: [String: Word] = [:]

    public init() {}

    public init(directories: [URL]) {
        var best: [String: ContentPack] = [:]
        var errors: [String] = []
        for dir in directories {
            for url in Self.packFiles(in: dir) {
                do {
                    let pack = try Self.decodePack(at: url)
                    if let existing = best[pack.id], existing.revision >= pack.revision { continue }
                    best[pack.id] = pack
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        self.init(packs: best.values.sorted { $0.id < $1.id }, errors: errors)
    }

    public init(packs: [ContentPack], errors: [String] = []) {
        self.packs = packs
        self.loadErrors = errors
        for p in packs {
            words += p.words ?? []
            if let u = p.units { units[p.skill, default: []] += u }
            compositions += p.compositions ?? []
            passages += p.passages ?? []
            notices += p.notices ?? []
        }
        words.sort { $0.level == $1.level ? $0.headword.lowercased() < $1.headword.lowercased() : $0.level < $1.level }
        for k in units.keys { units[k]?.sort { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level } }
        compositions.sort { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
        passages.sort { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }
        notices.sort { $0.date > $1.date }

        for w in words { wordIndex[w.id] = w }
        for list in units.values { for u in list { for e in u.exercises { exerciseIndex[e.id] = e } } }
        for p in passages { for q in p.questions { exerciseIndex[q.id] = q } }
    }

    public static func packFiles(in dir: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public static func decodePack(at url: URL) throws -> ContentPack {
        try decodePack(data: Data(contentsOf: url))
    }

    public static func decodePack(data: Data) throws -> ContentPack {
        let pack = try JSONDecoder().decode(ContentPack.self, from: data)
        guard pack.schemaVersion <= ContentPack.supportedSchemaVersion else {
            throw ContentError.unsupportedSchema(pack.id, pack.schemaVersion)
        }
        return pack
    }

    // MARK: 参照

    public func word(id: String) -> Word? { wordIndex[id] }
    public func exercise(id: String) -> Exercise? { exerciseIndex[id] }

    public func units(for skill: Skill) -> [StudyUnit] { units[skill] ?? [] }

    public func words(upTo level: Level) -> [Word] { words.filter { $0.level <= level } }

    /// 単元・長文に含まれる全演習
    public var allExercises: [Exercise] { Array(exerciseIndex.values) }

    public func unit(containingExercise id: String) -> StudyUnit? {
        for list in units.values { if let u = list.first(where: { $0.exercises.contains { $0.id == id } }) { return u } }
        return nil
    }

    /// 全IDの重複・形式チェック（eigo-tool validate とテストで使用）
    public func validate() -> [String] {
        var problems: [String] = []
        var seen: Set<String> = []
        func check(_ id: String) {
            if !seen.insert(id).inserted { problems.append("ID重複: \(id)") }
        }
        for w in words {
            check("word:\(w.id)")
            if w.meanings.isEmpty { problems.append("意味が空: \(w.id)") }
        }
        let allUnits = units.values.flatMap { $0 }
        for u in allUnits {
            check("unit:\(u.id)")
            for e in u.exercises { check("ex:\(e.id)"); problems += Self.validate(e) }
        }
        for c in compositions {
            check("comp:\(c.id)")
            if c.modelAnswers.isEmpty { problems.append("模範解答なし: \(c.id)") }
        }
        for p in passages {
            check("passage:\(p.id)")
            for q in p.questions { check("ex:\(q.id)"); problems += Self.validate(q) }
            if let t = p.translation, t.count != p.paragraphs.count {
                problems.append("訳の段落数が本文と不一致: \(p.id)")
            }
        }
        return problems
    }

    static func validate(_ e: Exercise) -> [String] {
        var p: [String] = []
        if e.answers.isEmpty { p.append("正解なし: \(e.id)") }
        switch e.type {
        case .choice:
            guard let ch = e.choices, ch.count >= 2 else { p.append("選択肢不足: \(e.id)"); break }
            if !e.answers.allSatisfy({ ch.contains($0) }) { p.append("正解が選択肢にない: \(e.id)") }
        case .reorder:
            guard let ch = e.choices else { p.append("並べ替え語句なし: \(e.id)"); break }
            let pieces = ch.map { AnswerChecker.normalize($0) }.sorted()
            let ans = AnswerChecker.normalize(e.answers[0]).split(separator: " ").map(String.init)
            let joined = AnswerChecker.normalize(ch.joined(separator: " ")).split(separator: " ").map(String.init).sorted()
            if joined != ans.sorted() { p.append("並べ替え語句と正解の語が一致しない: \(e.id) \(pieces)") }
        case .fill:
            if e.sentence?.contains("___") != true { p.append("空所(___)がない: \(e.id)") }
        default: break
        }
        return p
    }
}
