import EigoCore
import Foundation
import Observation

/// 進行中（または採点中）の模擬試験の状態。画面を移動しても失われないよう AppStore が保持する。
@MainActor
@Observable
final class MockExamSession {
    let exam: MockExam
    let startedAt: Date
    var submittedAt: Date?
    var answers: [String: String] = [:]
    var reorderPieces: [String: [String]] = [:]
    var reorderBuilt: [String: [Int]] = [:]
    var compositionText = ""
    var selfScores: [String: Double] = [:]
    /// 英作文の自己評価（0〜5）
    var compositionSelfScore: Int?
    var aiFeedback: EssayFeedback?
    var saved = false

    init(exam: MockExam, now: Date = Date()) {
        self.exam = exam
        self.startedAt = now
        for item in exam.allItems where item.exercise.type == .reorder {
            reorderPieces[item.id] = (item.exercise.choices ?? []).shuffled()
        }
    }

    var deadline: Date { startedAt.addingTimeInterval(Double(exam.timeLimitMinutes) * 60) }
    var isSubmitted: Bool { submittedAt != nil }
    var elapsedSeconds: Double { (submittedAt ?? Date()).timeIntervalSince(startedAt) }

    func remainingSeconds(at now: Date = Date()) -> Int { max(0, Int(deadline.timeIntervalSince(now).rounded(.up))) }

    func isAnswered(_ item: ExamItem) -> Bool {
        !(answers[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var unansweredCount: Int {
        exam.allItems.filter { !isAnswered($0) }.count
            + (exam.sections.contains { $0.kind == .composition } && compositionText.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 0)
    }

    func submit(now: Date = Date()) {
        guard submittedAt == nil else { return }
        submittedAt = min(now, deadline)
    }

    // MARK: 採点

    /// 英作文の得点率（AI 添削があればその目安、なければ自己評価）
    var compositionRate: Double? {
        if let f = aiFeedback { return Double(f.estimatedScore) / 100 }
        if let s = compositionSelfScore { return Double(s) / 5 }
        return nil
    }

    func sectionScore(_ s: ExamSection) -> Double {
        if s.kind == .composition, compositionText.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        return MockExamScorer.sectionScore(s, answers: answers, selfScores: selfScores, compositionScore: compositionRate)
    }

    var totalScore: Double { exam.sections.reduce(0) { $0 + sectionScore($1) } }
    var maxScore: Double { MockExamScorer.maxScore(exam) }

    /// 自己採点が必要で、まだ採点していない問題
    var pendingSelfGrading: [ExamItem] {
        exam.allItems.filter {
            MockExamScorer.autoGrade($0.exercise, answer: answers[$0.id] ?? "") == nil && isAnswered($0) && selfScores[$0.id] == nil
        }
    }

    var compositionPending: Bool {
        exam.sections.contains { $0.kind == .composition }
            && !compositionText.trimmingCharacters(in: .whitespaces).isEmpty
            && compositionRate == nil
    }

    func result() -> MockExamResult {
        let items = exam.allItems
        let correct = items.filter { MockExamScorer.points($0, answer: answers[$0.id], selfScore: selfScores[$0.id]) >= 1 }.count
        return MockExamResult(date: submittedAt ?? Date(), level: exam.level, seconds: elapsedSeconds,
                              timeLimitMinutes: exam.timeLimitMinutes, score: totalScore, maxScore: maxScore,
                              sectionScores: Dictionary(uniqueKeysWithValues: exam.sections.map { ($0.kind.rawValue, sectionScore($0)) }),
                              correctCount: correct, questionCount: items.count)
    }

    /// 復習スケジュールに反映する評価
    func reviewGrades() -> [(key: String, skill: Skill, grade: ReviewGrade)] {
        exam.allItems.map { item in
            let p = MockExamScorer.points(item, answer: answers[item.id], selfScore: selfScores[item.id])
            let grade: ReviewGrade = p >= 1 ? .good : (p > 0 ? .hard : .again)
            return (item.sourceKey, item.skill, grade)
        }
    }
}
