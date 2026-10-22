import EigoCore
import SwiftUI

/// 今日のおすすめ学習（復習＋新出）
struct TodaySessionView: View {
    @Environment(AppStore.self) private var store
    @State private var items: [StudyItem]?
    @State private var wordMode: WordMode = .flashcard

    var body: some View {
        Group {
            if let items {
                StudySessionView(title: "今日の学習", items: items, wordMode: wordMode) { self.items = nil }
            } else {
                let plan = store.planner.todaysSession()
                let due = store.planner.dueItems().count
                VStack(spacing: 18) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 52)).foregroundStyle(.blue)
                    Text("今日の学習").font(.largeTitle.bold())
                    Text("復習 \(due) 件 ＋ 新出 \(max(0, plan.count - due)) 件（合計 \(plan.count) 件）").font(.title3)
                    Picker("単語の出題形式", selection: $wordMode) {
                        ForEach(WordMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 420)
                    Button {
                        items = plan
                    } label: {
                        Label("開始", systemImage: "play.fill").frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(plan.isEmpty)
                    Text("1日の新出数は設定で変更できます。忘れかけた頃に自動で復習が出題されます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("今日の学習")
    }
}

/// 間違いノート
struct WeakItemsView: View {
    @Environment(AppStore.self) private var store
    @State private var session: [StudyItem]?

    var body: some View {
        let planner = store.planner
        let items = store.progress.weakKeys().compactMap(planner.item(for:))
        Group {
            if let session {
                StudySessionView(title: "間違いノート", items: session) { self.session = nil }
            } else if items.isEmpty {
                ContentUnavailableView("苦手な項目はありません", systemImage: "hand.thumbsup", description: Text("間違えた単語・問題がここに集まります。"))
            } else {
                List {
                    Section {
                        Button {
                            session = items
                        } label: {
                            Label("\(items.count) 件をまとめて復習", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Section("苦手な項目") {
                        ForEach(items) { item in
                            let card = store.progress.cards[item.key]
                            HStack {
                                Image(systemName: item.skill.systemImage).foregroundStyle(.secondary)
                                switch item {
                                case let .word(w): Text(w.headword).bold(); Text(w.primaryMeaning).foregroundStyle(.secondary)
                                case let .exercise(e, _): Text(e.sentence ?? e.prompt).lineLimit(1)
                                }
                                Spacer()
                                if let c = card { Text("正答 \(c.correctCount)/\(c.totalCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("間違いノート")
    }
}
