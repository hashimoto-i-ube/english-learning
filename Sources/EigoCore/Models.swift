import Foundation

// MARK: - 技能（モジュール）

/// 学習モジュールの種類。リスニング・スピーキングは将来拡張用に予約済み。
public enum Skill: String, Codable, CaseIterable, Identifiable, Sendable {
    case vocabulary     // 英単語・熟語
    case grammar        // 文法・語法
    case construction   // 英文解釈・構文
    case composition    // 英作文
    case reading        // 長文読解
    case knowledge      // 発音・アクセント・会話表現など基礎知識
    case listening      // 将来実装
    case speaking       // 将来実装

    public var id: String { rawValue }

    /// 現バージョンで利用可能か
    public var isAvailable: Bool {
        switch self {
        case .listening, .speaking: return false
        default: return true
        }
    }

    public var displayName: String {
        switch self {
        case .vocabulary: return "英単語・熟語"
        case .grammar: return "文法・語法"
        case .construction: return "英文解釈・構文"
        case .composition: return "英作文"
        case .reading: return "長文読解"
        case .knowledge: return "基礎知識"
        case .listening: return "リスニング"
        case .speaking: return "スピーキング"
        }
    }

    public var systemImage: String {
        switch self {
        case .vocabulary: return "character.book.closed"
        case .grammar: return "text.badge.checkmark"
        case .construction: return "text.magnifyingglass"
        case .composition: return "pencil.and.outline"
        case .reading: return "book"
        case .knowledge: return "lightbulb"
        case .listening: return "headphones"
        case .speaking: return "mic"
        }
    }
}

// MARK: - レベル

/// 高校入学（1）から最難関（7）までの到達段階。
public enum Level: Int, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case l1 = 1, l2, l3, l4, l5, l6, l7

    public var id: Int { rawValue }

    public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .l1: return "Lv1 中学総復習・高校入門"
        case .l2: return "Lv2 高1標準"
        case .l3: return "Lv3 高2標準・共通テスト基礎"
        case .l4: return "Lv4 共通テスト・中堅大"
        case .l5: return "Lv5 地方国公立・GMARCH"
        case .l6: return "Lv6 旧帝大・早慶"
        case .l7: return "Lv7 東大・京大・医学部"
        }
    }

    public var shortTitle: String { "Lv\(rawValue)" }

    /// 語彙数の目安（累計）
    public var cumulativeVocabularyTarget: Int {
        switch self {
        case .l1: return 1200
        case .l2: return 2000
        case .l3: return 3000
        case .l4: return 4000
        case .l5: return 5000
        case .l6: return 6500
        case .l7: return 8000
        }
    }
}

// MARK: - 共通部品

public struct ExampleSentence: Codable, Hashable, Sendable {
    public var en: String
    public var ja: String
    public var note: String?

    public init(en: String, ja: String, note: String? = nil) {
        self.en = en; self.ja = ja; self.note = note
    }
}

/// 将来のリスニング・スピーキング用。音声ファイル等の参照（現在は未使用）。
public struct MediaRef: Codable, Hashable, Sendable {
    public var kind: String      // "audio" など
    public var url: String       // 相対パス or URL
    public var transcript: String?
}

// MARK: - 単語

public struct Word: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var headword: String
    public var pos: String                 // 品詞（名・動・形・副・熟 など）
    public var meanings: [String]
    public var level: Level
    public var ipa: String?
    public var accentNote: String?         // アクセント注意など
    public var example: ExampleSentence?
    public var derivatives: [String]?
    public var synonyms: [String]?
    public var antonyms: [String]?
    public var collocations: [String]?
    public var note: String?               // 語法・頻出ポイント
    public var tags: [String]?
    public var media: [MediaRef]?

    public var primaryMeaning: String { meanings.first ?? "" }

    /// 熟語・イディオムか（熟語パックの項目、または品詞が「熟」）
    public var isIdiom: Bool { pos == "熟" || tags?.contains("idiom") == true }
}

// MARK: - 演習問題

public enum ExerciseType: String, Codable, Sendable {
    case choice          // 4択など
    case fill            // 空所補充（記述）
    case reorder         // 整序（語句並べ替え）
    case translateToJa   // 英文和訳（自己採点）
    case translateToEn   // 和文英訳（自動判定＋自己採点）
    case shortAnswer     // 内容説明など記述（自己採点）
}

public struct Exercise: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var type: ExerciseType
    /// 設問文（日本語の指示など）
    public var prompt: String
    /// 問題英文（空所は ___ ）
    public var sentence: String?
    /// 選択肢（choice）または並べ替え語句（reorder）
    public var choices: [String]?
    /// 正解（複数許容）。choice は正解の選択肢テキスト。
    public var answers: [String]
    public var explanation: String
    public var hint: String?
    /// 自己採点問題の採点ポイント
    public var keyPoints: [String]?
    public var level: Level?
    public var tags: [String]?
    public var media: [MediaRef]?

    /// 自動採点できる形式か
    public var isAutoGradable: Bool {
        switch type {
        case .choice, .fill, .reorder: return true
        case .translateToEn, .translateToJa, .shortAnswer: return false
        }
    }
}

// MARK: - 学習単元（文法・構文・基礎知識）

public struct StudyUnit: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var level: Level
    public var category: String?           // 「時制」「関係詞」など
    public var summary: String
    /// Markdown 形式の解説
    public var explanation: String
    public var examples: [ExampleSentence]
    public var exercises: [Exercise]
    public var tags: [String]?
}

// MARK: - 英作文

public enum CompositionKind: String, Codable, Sendable {
    case jaToEn      // 和文英訳
    case free        // 自由英作文（意見論述など）
    case summary     // 要約
    case graph       // 図表描写

    public var displayName: String {
        switch self {
        case .jaToEn: return "和文英訳"
        case .free: return "自由英作文"
        case .summary: return "要約"
        case .graph: return "図表・資料"
        }
    }
}

public struct CompositionPrompt: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: CompositionKind
    public var title: String
    public var level: Level
    public var promptJa: String
    public var conditions: String?
    public var minWords: Int?
    public var maxWords: Int?
    public var modelAnswers: [String]
    public var keyPoints: [String]
    public var usefulExpressions: [ExampleSentence]?
    public var tags: [String]?
}

// MARK: - 長文

public struct GlossaryItem: Codable, Hashable, Sendable {
    public var term: String
    public var meaning: String
}

public struct Passage: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var level: Level
    public var topic: String
    public var paragraphs: [String]
    public var translation: [String]?
    public var glossary: [GlossaryItem]?
    public var questions: [Exercise]
    public var targetMinutes: Int?
    public var tags: [String]?
    public var media: [MediaRef]?

    public var wordCount: Int {
        paragraphs.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count }
    }
}

// MARK: - お知らせ（入試情報など）

public struct Notice: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var date: String
    public var title: String
    public var body: String
}

// MARK: - コンテンツパック

/// 1ファイル = 1パック。リモート更新の単位。
public struct ContentPack: Codable, Identifiable, Sendable {
    public static let supportedSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var revision: Int
    public var skill: Skill
    public var title: String
    public var description: String?
    public var words: [Word]?
    public var units: [StudyUnit]?
    public var compositions: [CompositionPrompt]?
    public var passages: [Passage]?
    public var notices: [Notice]?
}

public struct ManifestEntry: Codable, Hashable, Sendable {
    public var id: String
    public var file: String
    public var revision: Int
    public var sha256: String
    public var skill: Skill
    public var title: String

    public init(id: String, file: String, revision: Int, sha256: String, skill: Skill, title: String) {
        self.id = id; self.file = file; self.revision = revision; self.sha256 = sha256; self.skill = skill; self.title = title
    }
}

public struct ContentManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: String
    public var minAppVersion: String?
    public var packs: [ManifestEntry]

    public init(schemaVersion: Int, generatedAt: String, minAppVersion: String?, packs: [ManifestEntry]) {
        self.schemaVersion = schemaVersion; self.generatedAt = generatedAt; self.minAppVersion = minAppVersion; self.packs = packs
    }
}
