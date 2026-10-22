import Foundation

/// 復習時の自己評価
public enum ReviewGrade: Int, Codable, CaseIterable, Sendable {
    case again = 0   // 不正解・忘れた
    case hard = 1    // 正解したが自信なし
    case good = 2    // 正解
    case easy = 3    // 簡単

    public var label: String {
        switch self {
        case .again: return "もう一度"
        case .hard: return "難しい"
        case .good: return "正解"
        case .easy: return "簡単"
        }
    }

    public var isCorrect: Bool { self != .again }
}

/// 1項目（単語・問題）の記憶状態
public struct SRSCard: Codable, Hashable, Sendable {
    public var ease: Double = 2.5
    public var intervalDays: Double = 0
    public var reps: Int = 0
    public var lapses: Int = 0
    public var due: Date
    public var lastReviewed: Date?
    public var correctCount: Int = 0
    public var totalCount: Int = 0

    public init(due: Date) { self.due = due }

    /// 定着済みとみなす（間隔21日以上）
    public var isMastered: Bool { intervalDays >= 21 }
    /// 学習中で不安定（直近に間違えた or 間隔が短い）
    public var isWeak: Bool { lapses > 0 && intervalDays < 7 }
}

/// SM-2 を簡略化した間隔反復スケジューラ
public enum Scheduler {
    public static func review(_ card: SRSCard?, grade: ReviewGrade, now: Date = Date()) -> SRSCard {
        var c = card ?? SRSCard(due: now)
        c.totalCount += 1
        c.lastReviewed = now

        switch grade {
        case .again:
            c.lapses += (c.reps > 0 ? 1 : 0)
            c.reps = 0
            c.ease = max(1.3, c.ease - 0.2)
            c.intervalDays = 0
            // 10分後に再出題
            c.due = now.addingTimeInterval(10 * 60)
            return c
        case .hard:
            c.ease = max(1.3, c.ease - 0.15)
        case .good:
            break
        case .easy:
            c.ease += 0.15
        }

        c.correctCount += 1
        c.reps += 1

        let next: Double
        switch c.reps {
        case 1: next = grade == .easy ? 3 : 1
        case 2: next = grade == .easy ? 7 : (grade == .hard ? 2 : 3)
        default:
            let factor = grade == .hard ? 1.2 : (grade == .easy ? c.ease * 1.3 : c.ease)
            next = max(c.intervalDays + 1, (c.intervalDays * factor).rounded())
        }
        c.intervalDays = min(next, 365)
        c.due = Calendar.current.startOfDay(for: now).addingTimeInterval(c.intervalDays * 86_400 + 4 * 3600)
        return c
    }
}
