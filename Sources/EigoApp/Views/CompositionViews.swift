import EigoCore
import SwiftUI

struct CompositionListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            ForEach(Level.allCases) { lv in
                let list = store.library.compositions.filter { $0.level == lv }
                if !list.isEmpty {
                    Section(lv.title) {
                        ForEach(list) { c in
                            NavigationLink(value: c) {
                                HStack {
                                    let attempts = store.progress.compositions.filter { $0.promptID == c.id }
                                    Image(systemName: attempts.isEmpty ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(attempts.isEmpty ? Color.secondary : Color.green)
                                    Text(c.kind.displayName).font(.caption).foregroundStyle(.blue)
                                    Text(c.title).bold()
                                    Spacer()
                                    if let best = attempts.compactMap(\.selfScore).max() { Text("自己評価 \(best)/5").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("英作文")
        .navigationDestination(for: CompositionPrompt.self) { CompositionDetailView(prompt: $0) }
    }
}

struct CompositionDetailView: View {
    @Environment(AppStore.self) private var store
    let prompt: CompositionPrompt

    @State private var text = ""
    @State private var attempt: CompositionAttempt?
    @State private var grading = false
    @State private var gradeError: String?

    var body: some View {
        let words = AnswerChecker.wordCount(text)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(prompt.level.title)・\(prompt.kind.displayName)").font(.caption).foregroundStyle(.secondary)
                Text(prompt.title).font(.largeTitle.bold())
                Text(prompt.promptJa).font(.title3).textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                if let cond = prompt.conditions { Label(cond, systemImage: "list.bullet.clipboard").foregroundStyle(.secondary) }

                TextEditor(text: $text)
                    .font(.system(.body, design: .serif))
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .disabled(attempt != nil)
                HStack {
                    Text("\(words) 語").monospacedDigit().foregroundStyle(wordCountColor(words))
                    if let mn = prompt.minWords, let mx = prompt.maxWords { Text("（目安 \(mn)〜\(mx) 語）").foregroundStyle(.secondary) }
                    Spacer()
                    if attempt == nil {
                        Button("提出して模範解答を見る") {
                            let a = CompositionAttempt(promptID: prompt.id, date: Date(), text: text)
                            attempt = a
                            store.addComposition(a)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(words == 0)
                    } else {
                        Button("書き直す") { attempt = nil }
                    }
                }

                if let a = attempt { review(a) }

                let past = store.progress.compositions.filter { $0.promptID == prompt.id && $0.id != attempt?.id }.sorted { $0.date > $1.date }
                if !past.isEmpty {
                    DisclosureGroup("過去の答案（\(past.count)）") {
                        ForEach(past) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                Text(p.text).textSelection(.enabled)
                                if let f = p.aiFeedback { Text("AI評価 \(f.estimatedScore) 点：\(f.overall)").font(.caption) }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(prompt.title)
    }

    private func wordCountColor(_ n: Int) -> Color {
        guard let mn = prompt.minWords else { return .primary }
        if n < mn { return .orange }
        if let mx = prompt.maxWords, n > mx { return .red }
        return .green
    }

    @ViewBuilder
    private func review(_ a: CompositionAttempt) -> some View {
        GroupBox("模範解答") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(prompt.modelAnswers.enumerated()), id: \.offset) { i, m in
                    VStack(alignment: .leading, spacing: 2) {
                        if prompt.modelAnswers.count > 1 { Text("例\(i + 1)").font(.caption.bold()) }
                        Text(m).font(.system(.body, design: .serif)).textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        GroupBox("採点ポイント（自己チェック）") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(prompt.keyPoints, id: \.self) { Label($0, systemImage: "checkmark.square") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let ex = prompt.usefulExpressions, !ex.isEmpty {
            GroupBox("使える表現") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ex, id: \.self) { e in
                        VStack(alignment: .leading) {
                            Text(e.en).bold()
                            Text(e.ja).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        HStack {
            Text("自己評価")
            Picker("自己評価", selection: Binding(get: { attempt?.selfScore ?? -1 }, set: { v in
                attempt?.selfScore = v
                if let a = attempt { store.updateComposition(a) }
            })) {
                Text("未評価").tag(-1)
                ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
        }

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI 添削（Claude）", systemImage: "sparkles").font(.headline)
                    Spacer()
                    if grading { ProgressView().controlSize(.small) }
                    Button("添削を依頼") { Task { await requestGrade() } }
                        .disabled(grading || !store.progress.settings.aiEnabled || store.apiKey.isEmpty)
                }
                if !store.progress.settings.aiEnabled || store.apiKey.isEmpty {
                    Text("設定で API キーを登録し AI 添削を有効にすると、答案の添削・書き直し例・得点目安を受け取れます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let e = gradeError { Text(e).foregroundStyle(.red).font(.callout) }
                if let f = attempt?.aiFeedback { FeedbackView(feedback: f) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func requestGrade() async {
        guard let a = attempt else { return }
        grading = true
        gradeError = nil
        defer { grading = false }
        do {
            let grader = EssayGrader(apiKey: store.apiKey, model: store.progress.settings.aiModel)
            let f = try await grader.grade(prompt: prompt, answer: a.text)
            attempt?.aiFeedback = f
            if let a = attempt { store.updateComposition(a) }
        } catch {
            gradeError = error.localizedDescription
        }
    }
}

struct FeedbackView: View {
    let feedback: EssayFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("得点目安 \(feedback.estimatedScore) / 100").font(.title3.bold())
                score("内容", feedback.content)
                score("構成", feedback.organization)
                score("語彙", feedback.vocabulary)
                score("文法", feedback.grammar)
            }
            Text(feedback.overall)
            if !feedback.corrections.isEmpty {
                Text("修正箇所").font(.headline)
                ForEach(feedback.corrections, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(c.original).strikethrough().foregroundStyle(.red)
                            Image(systemName: "arrow.right")
                            Text(c.corrected).foregroundStyle(.green).bold()
                        }
                        Text(c.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("書き直し例").font(.headline)
            Text(feedback.revisedText).font(.system(.body, design: .serif)).textSelection(.enabled)
            if !feedback.advice.isEmpty {
                Text("アドバイス").font(.headline)
                ForEach(feedback.advice, id: \.self) { Label($0, systemImage: "lightbulb") }
            }
        }
    }

    private func score(_ label: String, _ v: Int) -> some View {
        VStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(v)/5").bold().monospacedDigit()
        }
    }
}
