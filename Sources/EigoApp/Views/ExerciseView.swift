import EigoCore
import SwiftUI

/// 1問の演習（形式に応じて UI を切り替える）
struct ExerciseView: View {
    let exercise: Exercise
    var onGrade: (ReviewGrade) -> Void

    @State private var picked: String?
    @State private var typed = ""
    @State private var built: [Int] = []          // reorder: 選んだ語句の index
    @State private var pieces: [String] = []
    @State private var checked: Bool?             // 自動採点の結果
    @State private var revealed = false           // 自己採点問題の解答表示

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(typeLabel).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.blue.opacity(0.12), in: Capsule())
                if let lv = exercise.level { Text(lv.shortTitle).font(.caption).foregroundStyle(.secondary) }
            }
            Text(exercise.prompt).font(.headline)
            if let s = exercise.sentence {
                Text(s).font(.title3).textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            switch exercise.type {
            case .choice: choiceBody
            case .fill: fillBody
            case .reorder: reorderBody
            case .translateToEn, .translateToJa, .shortAnswer: freeBody
            }
        }
        .onAppear {
            pieces = (exercise.choices ?? []).shuffled()
        }
    }

    private var typeLabel: String {
        switch exercise.type {
        case .choice: return "選択"
        case .fill: return "空所補充"
        case .reorder: return "整序"
        case .translateToJa: return "英文和訳"
        case .translateToEn: return "和文英訳"
        case .shortAnswer: return "記述"
        }
    }

    // MARK: 選択

    private var choiceBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((exercise.choices ?? []).enumerated()), id: \.offset) { i, c in
                Button {
                    guard checked == nil else { return }
                    picked = c
                    checked = exercise.answers.contains(c)
                } label: {
                    HStack {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(c)
                        Spacer()
                        if checked != nil && exercise.answers.contains(c) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        if picked == c && checked == false { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            autoResult
        }
    }

    // MARK: 空所補充

    private var fillBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let h = exercise.hint { Label(h, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary) }
            TextField("空所に入る語句", text: $typed)
                .textFieldStyle(.roundedBorder).font(.title3)
                .disabled(checked != nil)
                .onSubmit(checkTyped)
            if checked == nil {
                HStack {
                    Button("答え合わせ", action: checkTyped).buttonStyle(.borderedProminent)
                    Button("わからない") { checked = false }
                }
            }
            autoResult
        }
    }

    // MARK: 整序

    private var reorderBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(built.map { pieces[$0] }.joined(separator: " ").ifEmpty("（下の語句をクリックして並べてください）"))
                .font(.title3)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            FlowLayout(spacing: 8) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { i, p in
                    Button(p) { if checked == nil, !built.contains(i) { built.append(i) } }
                        .buttonStyle(.bordered)
                        .disabled(built.contains(i))
                }
            }
            if checked == nil {
                HStack {
                    Button("1つ戻す") { _ = built.popLast() }.disabled(built.isEmpty)
                    Button("クリア") { built = [] }.disabled(built.isEmpty)
                    Spacer()
                    Button("答え合わせ") {
                        checked = AnswerChecker.isCorrect(built.map { pieces[$0] }.joined(separator: " "), answers: exercise.answers)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(built.count != pieces.count)
                }
            }
            autoResult
        }
    }

    // MARK: 記述（自己採点）

    private var freeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $typed)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .disabled(revealed)
            if !revealed {
                Button("解答・解説を見る") {
                    revealed = true
                    if exercise.type == .translateToEn, AnswerChecker.isCorrect(typed, answers: exercise.answers) {
                        checked = true
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                if checked == true { Label("模範解答と一致しました！", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                answerBox
                if let kp = exercise.keyPoints, !kp.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("採点ポイント").font(.caption.bold())
                        ForEach(kp, id: \.self) { Label($0, systemImage: "checkmark.square").font(.callout) }
                    }
                }
                Text("自分の解答を採点ポイントと照らして自己評価してください。").font(.caption).foregroundStyle(.secondary)
                GradeButtons(onGrade: onGrade)
            }
        }
    }

    // MARK: 共通

    @ViewBuilder
    private var autoResult: some View {
        if let ok = checked {
            Label(ok ? "正解！" : "不正解", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(ok ? .green : .red)
            answerBox
            if ok {
                GradeButtons(allowAgain: false, onGrade: onGrade)
            } else {
                Button("次へ") { onGrade(.again) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var answerBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正解").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(exercise.answers, id: \.self) { Text($0).font(.body.bold()).textSelection(.enabled) }
            Divider()
            Text(.init(exercise.explanation)).font(.callout).textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func checkTyped() {
        guard checked == nil else { return }
        checked = AnswerChecker.isCorrect(typed, answers: exercise.answers)
    }
}

extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}

/// 折り返し配置（整序問題の語句ボタン用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
