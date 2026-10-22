import EigoCore
import SwiftUI

enum WordMode: String, CaseIterable, Identifiable {
    case flashcard = "英→日 カード"
    case choice = "英→日 4択"
    case spelling = "日→英 スペル"
    var id: String { rawValue }
}

/// 単語・演習を順に出題し、結果を SRS に記録する共通セッション
struct StudySessionView: View {
    @Environment(AppStore.self) private var store
    let title: String
    let items: [StudyItem]
    var wordMode: WordMode = .flashcard
    var onFinish: (() -> Void)?

    @State private var index = 0
    @State private var results: [String: ReviewGrade] = [:]
    @State private var queue: [StudyItem] = []

    var body: some View {
        VStack(spacing: 0) {
            if queue.isEmpty && results.isEmpty {
                ContentUnavailableView("出題できる項目がありません", systemImage: "checkmark.seal", description: Text("復習期限の来た項目はありません。新しい単元に進みましょう。"))
            } else if index < queue.count {
                VStack(spacing: 4) {
                    ProgressView(value: Double(index), total: Double(queue.count))
                    HStack {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(index + 1) / \(queue.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .padding([.horizontal, .top])

                ScrollView {
                    Group {
                        switch queue[index] {
                        case let .word(w):
                            WordQuizView(word: w, mode: wordMode, distractors: distractors(for: w)) { grade(queue[index], $0) }
                        case let .exercise(e, _):
                            ExerciseView(exercise: e) { grade(queue[index], $0) }
                        }
                    }
                    .id(queue[index].key + "#\(index)")
                    .padding(24)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            } else {
                SessionSummaryView(results: results, items: items) {
                    reset()
                } onClose: {
                    onFinish?()
                }
            }
        }
        .onAppear {
            reset()
            store.beginStudy()
        }
        .onDisappear { store.flushStudyTime() }
    }

    private func reset() {
        queue = items
        index = 0
        results = [:]
    }

    private func grade(_ item: StudyItem, _ g: ReviewGrade) {
        store.record(item, grade: g)
        if results[item.key] == nil { results[item.key] = g }
        // 間違えた項目はセッション末尾で再出題（1回まで）
        if g == .again, queue[(index + 1)...].contains(where: { $0.key == item.key }) == false,
           queue.filter({ $0.key == item.key }).count < 2 {
            queue.append(item)
        }
        index += 1
        if index >= queue.count { store.flushStudyTime() }
    }

    private func distractors(for w: Word) -> [String] {
        let pool = store.library.words.filter { $0.id != w.id && $0.pos == w.pos }
        let base = pool.isEmpty ? store.library.words.filter { $0.id != w.id } : pool
        return Array(base.shuffled().prefix(3)).map(\.primaryMeaning)
    }
}

struct SessionSummaryView: View {
    let results: [String: ReviewGrade]
    let items: [StudyItem]
    var onRetry: () -> Void
    var onClose: () -> Void

    var body: some View {
        let correct = results.values.filter(\.isCorrect).count
        VStack(spacing: 16) {
            Image(systemName: "party.popper").font(.system(size: 48)).foregroundStyle(.orange)
            Text("おつかれさまでした！").font(.title.bold())
            Text("\(results.count) 問中 \(correct) 問正解（初回解答）").font(.title3)
            Text("間違えた項目は自動的に復習スケジュールに入りました。").foregroundStyle(.secondary)
            HStack {
                Button("もう一度", action: onRetry)
                Button("終了", action: onClose).buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 自己評価ボタン
struct GradeButtons: View {
    var allowAgain = true
    var onGrade: (ReviewGrade) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if allowAgain {
                Button { onGrade(.again) } label: { Text("もう一度").frame(minWidth: 80) }
                    .tint(.red).keyboardShortcut("1", modifiers: [])
            }
            Button { onGrade(.hard) } label: { Text("難しい").frame(minWidth: 80) }
                .tint(.orange).keyboardShortcut("2", modifiers: [])
            Button { onGrade(.good) } label: { Text("正解").frame(minWidth: 80) }
                .tint(.green).keyboardShortcut("3", modifiers: [])
            Button { onGrade(.easy) } label: { Text("簡単").frame(minWidth: 80) }
                .tint(.blue).keyboardShortcut("4", modifiers: [])
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// MARK: - 単語

struct WordQuizView: View {
    let word: Word
    let mode: WordMode
    let distractors: [String]
    var onGrade: (ReviewGrade) -> Void

    @State private var revealed = false
    @State private var choices: [String] = []
    @State private var picked: String?
    @State private var typed = ""
    @State private var typedCorrect: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch mode {
            case .flashcard:
                headword
                if revealed {
                    WordDetailView(word: word)
                    GradeButtons(onGrade: onGrade)
                } else {
                    Button { revealed = true } label: { Text("答えを見る").frame(minWidth: 200) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.space, modifiers: [])
                }

            case .choice:
                headword
                ForEach(choices, id: \.self) { c in
                    Button {
                        guard picked == nil else { return }
                        picked = c
                    } label: {
                        HStack {
                            Text(c)
                            Spacer()
                            if picked != nil && c == word.primaryMeaning { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            if picked == c && c != word.primaryMeaning { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                if let p = picked {
                    WordDetailView(word: word)
                    if p == word.primaryMeaning {
                        GradeButtons(allowAgain: false, onGrade: onGrade)
                    } else {
                        Button("次へ") { onGrade(.again) }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [])
                    }
                }

            case .spelling:
                Text(word.meanings.joined(separator: "；")).font(.title.bold())
                Text("（\(word.pos)）英語で入力").foregroundStyle(.secondary)
                if let ex = word.example {
                    Text(ex.ja).foregroundStyle(.secondary)
                }
                TextField("英単語を入力", text: $typed)
                    .textFieldStyle(.roundedBorder).font(.title2)
                    .disabled(typedCorrect != nil)
                    .onSubmit(check)
                if let ok = typedCorrect {
                    Label(ok ? "正解！" : "正解は \(word.headword)", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? .green : .red).font(.title3.bold())
                    WordDetailView(word: word)
                    if ok { GradeButtons(allowAgain: false, onGrade: onGrade) } else {
                        Button("次へ") { onGrade(.again) }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [])
                    }
                } else {
                    HStack {
                        Button("答え合わせ", action: check).buttonStyle(.borderedProminent)
                        Button("わからない") { typedCorrect = false }
                    }
                }
            }
        }
        .onAppear { choices = ([word.primaryMeaning] + distractors).shuffled() }
    }

    private var headword: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(word.headword).font(.system(size: 40, weight: .bold, design: .serif))
            HStack {
                Text(word.pos).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                if let ipa = word.ipa { Text(ipa).foregroundStyle(.secondary) }
                Text(word.level.shortTitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func check() {
        guard typedCorrect == nil else { return }
        typedCorrect = AnswerChecker.isCorrect(typed, answers: [word.headword])
    }
}

struct WordDetailView: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.meanings.joined(separator: "；")).font(.title2.bold())
            if let a = word.accentNote { Label(a, systemImage: "waveform").font(.callout).foregroundStyle(.purple) }
            if let ex = word.example {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.en).font(.body.italic())
                    Text(ex.ja).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            infoRow("派生", word.derivatives)
            infoRow("類義", word.synonyms)
            infoRow("反意", word.antonyms)
            infoRow("コロケーション", word.collocations)
            if let n = word.note { Label(n, systemImage: "info.circle").font(.callout) }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ values: [String]?) -> some View {
        if let v = values, !v.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.caption.bold()).frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                Text(v.joined(separator: ", ")).font(.callout)
            }
        }
    }
}
