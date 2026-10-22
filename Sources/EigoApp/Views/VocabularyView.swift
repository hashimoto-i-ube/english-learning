import EigoCore
import SwiftUI

struct VocabularyView: View {
    @Environment(AppStore.self) private var store
    @State private var level: Level?
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var mode: WordMode = .flashcard
    @State private var session: [StudyItem]?
    @State private var selected: Word?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "すべて", unseen = "未学習", learning = "学習中", mastered = "定着", bookmarked = "★"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let session {
                StudySessionView(title: "英単語", items: session, wordMode: mode) { self.session = nil }
            } else {
                HSplitView {
                    list.frame(minWidth: 380)
                    Group {
                        if let w = selected {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(w.headword).font(.system(size: 34, weight: .bold, design: .serif))
                                        Spacer()
                                        let key = ItemKey.word(w.id)
                                        Button { store.toggleBookmark(key) } label: {
                                            Image(systemName: store.progress.bookmarks.contains(key) ? "star.fill" : "star")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    HStack {
                                        Text(w.pos); if let ipa = w.ipa { Text(ipa) }; Text(w.level.title)
                                    }
                                    .foregroundStyle(.secondary)
                                    WordDetailView(word: w)
                                }
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ContentUnavailableView("単語を選択", systemImage: "character.book.closed")
                        }
                    }
                    .frame(minWidth: 320)
                }
            }
        }
        .navigationTitle("英単語・熟語")
        .searchable(text: $search, prompt: "英語・日本語で検索")
    }

    private var filtered: [Word] {
        store.library.words.filter { w in
            if let level, w.level != level { return false }
            let key = ItemKey.word(w.id)
            let card = store.progress.cards[key]
            switch filter {
            case .all: break
            case .unseen: if card != nil { return false }
            case .learning: if card == nil || card!.isMastered { return false }
            case .mastered: if card?.isMastered != true { return false }
            case .bookmarked: if !store.progress.bookmarks.contains(key) { return false }
            }
            if search.isEmpty { return true }
            let q = search.lowercased()
            return w.headword.lowercased().contains(q) || w.meanings.contains { $0.contains(search) }
        }
    }

    private var list: some View {
        let words = filtered
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Picker("レベル", selection: $level) {
                        Text("全レベル").tag(Level?.none)
                        ForEach(Level.allCases) { Text($0.title).tag(Level?.some($0)) }
                    }
                    Picker("状態", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 150)
                }
                HStack {
                    Picker("形式", selection: $mode) {
                        ForEach(WordMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 220)
                    Spacer()
                    Button {
                        let due = store.planner.dueItems(skill: .vocabulary)
                        let newOnes = words.filter { store.progress.cards[ItemKey.word($0.id)] == nil }.prefix(store.progress.settings.dailyNewWords)
                        session = due + newOnes.map { .word($0) }
                    } label: { Label("復習＋新出", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    Button {
                        session = words.shuffled().prefix(30).map { .word($0) }
                    } label: { Label("表示中から30語", systemImage: "shuffle") }
                    .disabled(words.isEmpty)
                }
            }
            .padding(10)
            Divider()
            List(words, selection: Binding(get: { selected?.id }, set: { id in selected = words.first { $0.id == id } })) { w in
                HStack {
                    statusDot(for: w)
                    Text(w.headword).bold()
                    Text(w.pos).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(w.primaryMeaning).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(w.id)
            }
            Text("\(words.count) 語").font(.caption).foregroundStyle(.secondary).padding(4)
        }
    }

    private func statusDot(for w: Word) -> some View {
        let c = store.progress.cards[ItemKey.word(w.id)]
        let color: Color = c == nil ? .gray.opacity(0.3) : (c!.isMastered ? .green : (c!.isWeak ? .red : .orange))
        return Circle().fill(color).frame(width: 8, height: 8)
    }
}
