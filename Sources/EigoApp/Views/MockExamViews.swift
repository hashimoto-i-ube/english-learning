import Charts
import EigoCore
import SwiftUI

// MARK: - ホーム（レベル選択・履歴）

struct MockExamHomeView: View {
    @Environment(AppStore.self) private var store
    @State private var level: Level = .l1

    var body: some View {
        Group {
            if let session = store.mockSession {
                if session.isSubmitted {
                    MockExamResultView(session: session)
                } else {
                    MockExamTakingView(session: session)
                }
            } else {
                home
            }
        }
        .navigationTitle("模擬試験")
        .onAppear { level = store.progress.settings.currentLevel }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("模擬試験").font(.largeTitle.bold())
                    Text("語彙・文法・英文解釈・長文・英作文の総合問題を、時間制限付きで解きます。問題は収録コンテンツから毎回組み直されます。")
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("レベル", selection: $level) {
                            ForEach(Level.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(maxWidth: 420)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            ForEach(ExamSectionKind.allCases) { k in
                                GridRow {
                                    Text(k.title).bold()
                                    Text("\(Int(k.weight)) 点").monospacedDigit().foregroundStyle(.secondary)
                                    Text(sectionNote(k)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack {
                            Label("制限時間 \(MockExam.timeLimit(for: level)) 分", systemImage: "timer")
                            Text("・合格目安 \(Int(MockExam.passingRate * 100)) 点").foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.startMockExam(level: level)
                            } label: {
                                Label("試験を開始", systemImage: "play.fill").padding(.horizontal, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    .padding(6)
                }

                history
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionNote(_ k: ExamSectionKind) -> String {
        switch k {
        case .vocabulary: return "意味の4択 \(level <= .l3 ? 15 : 20) 問"
        case .grammar: return "選択・空所補充・整序 10 問"
        case .construction: return "構文の選択問題＋英文和訳"
        case .reading: return "長文1題（内容一致・記述）"
        case .composition: return "1題（自己採点またはAI添削）"
        }
    }

    @ViewBuilder
    private var history: some View {
        let results = store.progress.mockExams.sorted { $0.date > $1.date }
        if !results.isEmpty {
            Text("受験履歴").font(.title3.bold())
            let levelResults = store.progress.mockExams.filter { $0.level == level }.sorted { $0.date < $1.date }
            if levelResults.count >= 2 {
                GroupBox("\(level.shortTitle) の得点推移") {
                    Chart(Array(levelResults.enumerated()), id: \.offset) { i, r in
                        LineMark(x: .value("回", i + 1), y: .value("得点", r.score))
                        PointMark(x: .value("回", i + 1), y: .value("得点", r.score))
                        RuleMark(y: .value("合格目安", MockExam.passingRate * 100))
                            .foregroundStyle(.green.opacity(0.4))
                            .lineStyle(StrokeStyle(dash: [4]))
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 160)
                }
            }
            ForEach(results) { r in
                HStack {
                    Image(systemName: r.passed ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(r.passed ? .green : .orange)
                    Text(r.level.shortTitle).bold()
                    Text(r.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(r.score.rounded())) / \(Int(r.maxScore)) 点").font(.headline.monospacedDigit())
                    Text("\(Int(r.seconds / 60))分").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - 受験中

struct MockExamTakingView: View {
    @Environment(AppStore.self) private var store
    let session: MockExamSession
    @State private var section: ExamSectionKind = .vocabulary
    @State private var confirmSubmit = false
    @State private var confirmQuit = false

    var body: some View {
        HSplitView {
            List(selection: Binding(get: { section }, set: { if let s = $0 { section = s } })) {
                Section("大問") {
                    ForEach(session.exam.sections) { s in
                        HStack {
                            Text(s.kind.title)
                            Spacer()
                            Text(progressText(s)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .tag(s.kind)
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

            if let s = session.exam.sections.first(where: { $0.kind == section }) {
                sectionView(s).frame(minWidth: 520)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { timer }
            ToolbarItemGroup {
                Button("中断して破棄", role: .destructive) { confirmQuit = true }
                Button {
                    confirmSubmit = true
                } label: { Label("提出する", systemImage: "paperplane.fill") }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { section = session.exam.sections.first?.kind ?? .vocabulary }
        .task {
            // 時間切れで自動提出
            while !session.isSubmitted {
                if session.remainingSeconds() == 0 {
                    session.submit()
                    store.statusMessage = "時間切れです。答案を提出しました。"
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("答案を提出しますか？", isPresented: $confirmSubmit) {
            Button("提出する") { session.submit() }
            Button("見直す", role: .cancel) {}
        } message: {
            Text(session.unansweredCount > 0 ? "未解答が \(session.unansweredCount) 問あります。" : "すべての問題に解答しています。")
        }
        .confirmationDialog("この試験を破棄しますか？", isPresented: $confirmQuit) {
            Button("破棄する", role: .destructive) { store.mockSession = nil }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("解答と経過時間は保存されません。")
        }
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = session.remainingSeconds(at: ctx.date)
            Label(String(format: "残り %d:%02d", s / 60, s % 60), systemImage: "timer")
                .labelStyle(.titleAndIcon)
                .font(.headline.monospacedDigit())
                .foregroundStyle(s < 300 ? .red : .primary)
        }
    }

    private func progressText(_ s: ExamSection) -> String {
        if s.kind == .composition {
            return session.compositionText.trimmingCharacters(in: .whitespaces).isEmpty ? "未" : "済"
        }
        return "\(s.items.filter(session.isAnswered).count)/\(s.items.count)"
    }

    @ViewBuilder
    private func sectionView(_ s: ExamSection) -> some View {
        switch s.kind {
        case .reading:
            HSplitView {
                ScrollView {
                    if let p = s.passage {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(p.title).font(.title2.bold())
                            ForEach(Array(p.paragraphs.enumerated()), id: \.offset) { i, para in
                                (Text("[\(i + 1)] ").font(.caption.bold()).foregroundStyle(.secondary) + Text(para))
                                    .font(.system(size: 15, design: .serif))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(minWidth: 320)
                questionList(s).frame(minWidth: 320)
            }
        case .composition:
            if let c = s.composition { CompositionAnswerView(prompt: c, session: session) }
        default:
            questionList(s)
        }
    }

    private func questionList(_ s: ExamSection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("\(s.kind.title)（\(Int(s.kind.weight))点）").font(.title2.bold())
                ForEach(Array(s.items.enumerated()), id: \.element.id) { i, item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("問\(i + 1)　\(item.exercise.prompt)").font(.headline)
                        if let sentence = item.exercise.sentence {
                            Text(sentence).font(.title3).textSelection(.enabled)
                        }
                        ExamItemInput(item: item, session: session)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
        }
    }
}

/// 解答の入力（採点・解説は表示しない）
struct ExamItemInput: View {
    let item: ExamItem
    @Bindable var session: MockExamSession

    var body: some View {
        let answer = Binding(get: { session.answers[item.id] ?? "" }, set: { session.answers[item.id] = $0 })
        switch item.exercise.type {
        case .choice:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array((item.exercise.choices ?? []).enumerated()), id: \.offset) { i, c in
                    Button {
                        session.answers[item.id] = c
                    } label: {
                        HStack {
                            Image(systemName: answer.wrappedValue == c ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(answer.wrappedValue == c ? Color.accentColor : .secondary)
                            Text("\(i + 1). \(c)")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .fill:
            TextField("解答", text: answer).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
        case .reorder:
            reorder
        case .translateToEn, .translateToJa, .shortAnswer:
            TextEditor(text: answer)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private var reorder: some View {
        let pieces = session.reorderPieces[item.id] ?? []
        let built = session.reorderBuilt[item.id] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text(built.map { pieces[$0] }.joined(separator: " ").ifEmpty("（語句をクリックして並べてください）"))
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            FlowLayout(spacing: 6) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { i, p in
                    Button(p) { add(i, pieces: pieces) }
                        .buttonStyle(.bordered)
                        .disabled(built.contains(i))
                }
            }
            HStack {
                Button("1つ戻す") { update(Array(built.dropLast()), pieces: pieces) }.disabled(built.isEmpty)
                Button("クリア") { update([], pieces: pieces) }.disabled(built.isEmpty)
            }
            .controlSize(.small)
        }
    }

    private func add(_ i: Int, pieces: [String]) {
        update((session.reorderBuilt[item.id] ?? []) + [i], pieces: pieces)
    }

    private func update(_ built: [Int], pieces: [String]) {
        session.reorderBuilt[item.id] = built
        session.answers[item.id] = built.count == pieces.count ? built.map { pieces[$0] }.joined(separator: " ") : ""
    }
}

struct CompositionAnswerView: View {
    let prompt: CompositionPrompt
    @Bindable var session: MockExamSession

    var body: some View {
        let words = AnswerChecker.wordCount(session.compositionText)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("英作文（\(Int(ExamSectionKind.composition.weight))点）・\(prompt.kind.displayName)").font(.title2.bold())
                Text(prompt.promptJa)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                if let cond = prompt.conditions { Label(cond, systemImage: "list.bullet.clipboard").foregroundStyle(.secondary) }
                TextEditor(text: $session.compositionText)
                    .font(.system(.body, design: .serif))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("\(words) 語\(prompt.minWords.map { mn in prompt.maxWords.map { "（目安 \(mn)〜\($0) 語）" } ?? "" } ?? "")")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }
}

// MARK: - 採点・結果

struct MockExamResultView: View {
    @Environment(AppStore.self) private var store
    @Bindable var session: MockExamSession
    @State private var grading = false
    @State private var gradeError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                if !session.pendingSelfGrading.isEmpty || session.compositionPending {
                    Label("記述問題 \(session.pendingSelfGrading.count + (session.compositionPending ? 1 : 0)) 件が未採点です。解答例と見比べて自己採点してください（未採点は0点）。",
                          systemImage: "pencil.and.list.clipboard")
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(session.exam.sections) { s in
                    DisclosureGroup {
                        if s.kind == .composition, let c = s.composition {
                            compositionReview(c)
                        } else {
                            ForEach(Array(s.items.enumerated()), id: \.element.id) { i, item in
                                itemReview(i, item)
                            }
                        }
                    } label: {
                        HStack {
                            Text(s.kind.title).font(.headline)
                            Spacer()
                            Text(String(format: "%.1f / %.0f 点", session.sectionScore(s), s.kind.weight)).monospacedDigit()
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                if session.saved {
                    Button("模擬試験トップへ") { store.mockSession = nil }.buttonStyle(.borderedProminent)
                } else {
                    Button("保存せずに閉じる", role: .destructive) { store.mockSession = nil }
                    Button {
                        store.saveMockExam(session)
                        store.statusMessage = "結果を保存し、間違えた問題を復習に追加しました。"
                    } label: { Label("結果を保存", systemImage: "square.and.arrow.down") }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var summary: some View {
        let score = session.totalScore, max = session.maxScore
        let passed = max > 0 && score / max >= MockExam.passingRate
        return GroupBox {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(session.exam.level.title) 模擬試験").font(.headline)
                    Text(String(format: "%.0f", score)).font(.system(size: 56, weight: .bold).monospacedDigit())
                        + Text(" / \(Int(max)) 点").font(.title2).foregroundColor(.secondary)
                    Label(passed ? "合格目安に到達" : "合格目安（\(Int(MockExam.passingRate * 100))点）まであと \(Int((MockExam.passingRate * max - score).rounded(.up))) 点",
                          systemImage: passed ? "checkmark.seal.fill" : "flag")
                        .foregroundStyle(passed ? .green : .orange)
                    Text("解答時間 \(Int(session.elapsedSeconds / 60))分\(Int(session.elapsedSeconds) % 60)秒 / 制限 \(session.exam.timeLimitMinutes)分")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Chart(session.exam.sections) { s in
                    BarMark(x: .value("得点率", session.sectionScore(s) / s.kind.weight * 100), y: .value("大問", s.kind.title))
                        .foregroundStyle(by: .value("大問", s.kind.title))
                }
                .chartXScale(domain: 0...100)
                .chartLegend(.hidden)
                .frame(width: 320, height: 150)
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func itemReview(_ i: Int, _ item: ExamItem) -> some View {
        let answer = session.answers[item.id] ?? ""
        let auto = MockExamScorer.autoGrade(item.exercise, answer: answer)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if let auto {
                        Image(systemName: auto ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(auto ? .green : .red)
                    } else {
                        Image(systemName: "pencil.circle").foregroundStyle(.orange)
                    }
                }
                Text("問\(i + 1)　\(item.exercise.prompt)").bold()
            }
            if let s = item.exercise.sentence { Text(s).textSelection(.enabled) }
            Text("あなたの解答：\(answer.isEmpty ? "（無解答）" : answer)").foregroundStyle(.secondary).textSelection(.enabled)
            Text("正解・解答例：\(item.exercise.answers.joined(separator: " / "))").bold().textSelection(.enabled)
            if let kp = item.exercise.keyPoints, !kp.isEmpty {
                Text("採点ポイント：" + kp.joined(separator: "、")).font(.caption)
            }
            Text(.init(item.exercise.explanation)).font(.callout).foregroundStyle(.secondary)
            if auto == nil && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.saved {
                Picker("自己採点", selection: Binding(get: { session.selfScores[item.id] ?? -1 }, set: { session.selfScores[item.id] = $0 < 0 ? nil : $0 })) {
                    Text("未採点").tag(-1.0)
                    Text("× 0").tag(0.0)
                    Text("△ 半分").tag(0.5)
                    Text("○ 満点").tag(1.0)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
        }
        .padding(.vertical, 8)
        Divider()
    }

    @ViewBuilder
    private func compositionReview(_ c: CompositionPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(c.promptJa).font(.callout)
            Text("あなたの答案（\(AnswerChecker.wordCount(session.compositionText))語）").font(.caption.bold())
            Text(session.compositionText.isEmpty ? "（無解答）" : session.compositionText)
                .font(.system(.body, design: .serif)).textSelection(.enabled)
            Text("模範解答").font(.caption.bold())
            ForEach(c.modelAnswers, id: \.self) { Text($0).font(.system(.body, design: .serif)).textSelection(.enabled) }
            Text("採点ポイント").font(.caption.bold())
            ForEach(c.keyPoints, id: \.self) { Label($0, systemImage: "checkmark.square").font(.callout) }
            if !session.compositionText.trimmingCharacters(in: .whitespaces).isEmpty && !session.saved {
                HStack {
                    Text("自己評価")
                    Picker("自己評価", selection: Binding(get: { session.compositionSelfScore ?? -1 }, set: { session.compositionSelfScore = $0 < 0 ? nil : $0 })) {
                        Text("未").tag(-1)
                        ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    Spacer()
                    if grading { ProgressView().controlSize(.small) }
                    Button("AI 添削") { Task { await grade(c) } }
                        .disabled(grading || !store.progress.settings.aiEnabled || store.apiKey.isEmpty)
                        .help("設定で API キーを登録すると利用できます")
                }
            }
            if let e = gradeError { Text(e).foregroundStyle(.red).font(.callout) }
            if let f = session.aiFeedback {
                Text("AI 添削の得点目安を英作文の得点に使用しています。").font(.caption).foregroundStyle(.secondary)
                FeedbackView(feedback: f)
            }
        }
        .padding(.vertical, 6)
    }

    private func grade(_ c: CompositionPrompt) async {
        grading = true
        gradeError = nil
        defer { grading = false }
        do {
            session.aiFeedback = try await EssayGrader(apiKey: store.apiKey, model: store.progress.settings.aiModel)
                .grade(prompt: c, answer: session.compositionText)
        } catch {
            gradeError = error.localizedDescription
        }
    }
}
