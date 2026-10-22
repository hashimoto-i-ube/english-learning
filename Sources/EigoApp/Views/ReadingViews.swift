import EigoCore
import SwiftUI

struct ReadingListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            ForEach(Level.allCases) { lv in
                let list = store.library.passages.filter { $0.level == lv }
                if !list.isEmpty {
                    Section(lv.title) {
                        ForEach(list) { p in
                            NavigationLink(value: p) {
                                HStack {
                                    let recs = store.progress.readings.filter { $0.passageID == p.id }
                                    Image(systemName: recs.isEmpty ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(recs.isEmpty ? Color.secondary : Color.green)
                                    VStack(alignment: .leading) {
                                        Text(p.title).bold()
                                        Text("\(p.topic)・\(p.wordCount) 語・設問 \(p.questions.count)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let last = recs.last { Text("\(last.wordsPerMinute) wpm・\(last.correct)/\(last.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("長文読解")
        .navigationDestination(for: Passage.self) { ReadingDetailView(passage: $0) }
    }
}

struct ReadingDetailView: View {
    @Environment(AppStore.self) private var store
    let passage: Passage

    enum Phase { case ready, reading, questions, done }

    @State private var phase: Phase = .ready
    @State private var start = Date()
    @State private var readingSeconds: Double = 0
    @State private var qIndex = 0
    @State private var correct = 0
    @State private var showGlossary = false
    @State private var showTranslation = false

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(passage.title).font(.title.bold())
                    Text("\(passage.level.title)・\(passage.topic)・\(passage.wordCount) 語\(passage.targetMinutes.map { "・目標 \($0) 分" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    if phase == .ready {
                        Text("「読み始める」を押すと計測が始まります。辞書を使わずに読み、読み終えたら設問に進みましょう。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(passage.paragraphs.enumerated()), id: \.offset) { i, para in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("[\(i + 1)] ").font(.caption.bold()).foregroundStyle(.secondary) + Text(para)
                                if showTranslation, let t = passage.translation, i < t.count {
                                    Text(t[i]).font(.callout).foregroundStyle(.secondary)
                                        .padding(8).background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .font(.system(size: 16, design: .serif))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                        }
                    }
                    if showGlossary, let g = passage.glossary {
                        GroupBox("語注") {
                            ForEach(g, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline) { Text(item.term).bold(); Text(item.meaning).foregroundStyle(.secondary); Spacer() }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 420)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    controls
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 360, idealWidth: 420)
        }
        .navigationTitle(passage.title)
        .toolbar {
            ToolbarItemGroup {
                if passage.glossary != nil { Toggle("語注", isOn: $showGlossary) }
                if passage.translation != nil && phase == .done { Toggle("全訳", isOn: $showTranslation) }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .ready:
            Button {
                start = Date(); phase = .reading; store.beginStudy()
            } label: { Label("読み始める", systemImage: "timer").frame(minWidth: 160) }
            .buttonStyle(.borderedProminent).controlSize(.large)
        case .reading:
            TimelineView(.periodic(from: start, by: 1)) { ctx in
                let s = Int(ctx.date.timeIntervalSince(start))
                Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 40, weight: .bold).monospacedDigit())
            }
            Button {
                readingSeconds = Date().timeIntervalSince(start)
                phase = passage.questions.isEmpty ? .done : .questions
                if passage.questions.isEmpty { finish() }
            } label: { Label("読み終えた → 設問へ", systemImage: "checkmark") }
            .buttonStyle(.borderedProminent).controlSize(.large)
        case .questions:
            Text("設問 \(qIndex + 1) / \(passage.questions.count)").font(.caption).foregroundStyle(.secondary)
            let q = passage.questions[qIndex]
            ExerciseView(exercise: q) { g in
                store.record(.exercise(q, skill: .reading), grade: g)
                if g.isCorrect { correct += 1 }
                if qIndex + 1 < passage.questions.count { qIndex += 1 } else { finish() }
            }
            .id(q.id)
        case .done:
            let wpm = readingSeconds > 0 ? Int(Double(passage.wordCount) / (readingSeconds / 60)) : 0
            VStack(alignment: .leading, spacing: 10) {
                Text("結果").font(.title2.bold())
                Text("読解速度: \(wpm) wpm（\(Int(readingSeconds / 60))分\(Int(readingSeconds) % 60)秒）")
                Text("正答: \(correct) / \(passage.questions.count)")
                Text(wpmAdvice(wpm)).font(.callout).foregroundStyle(.secondary)
                Button("もう一度解く") {
                    phase = .ready; qIndex = 0; correct = 0; showTranslation = false
                }
            }
        }
    }

    private func finish() {
        phase = .done
        let wpm = readingSeconds > 0 ? Int(Double(passage.wordCount) / (readingSeconds / 60)) : 0
        store.addReading(ReadingRecord(passageID: passage.id, date: Date(), seconds: readingSeconds,
                                       wordsPerMinute: wpm, correct: correct, total: passage.questions.count))
        store.flushStudyTime()
    }

    private func wpmAdvice(_ wpm: Int) -> String {
        switch wpm {
        case ..<80: return "目安：共通テストでは 120〜150 wpm、難関大では 150 wpm 以上が求められます。まずは精読で構文を確実に取りましょう。"
        case 80..<120: return "共通テスト完答には 120 wpm 以上が目標です。音読と、既習英文の再読で速度を上げましょう。"
        case 120..<160: return "共通テスト水準です。難関大では精度を保ったまま 150 wpm 以上を目指しましょう。"
        default: return "難関大レベルの速度です。設問の正答率とのバランスを確認しましょう。"
        }
    }
}
