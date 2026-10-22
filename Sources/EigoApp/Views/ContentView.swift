import EigoCore
import SwiftUI

enum SidebarItem: Hashable {
    case home
    case review
    case weak
    case skill(Skill)
    case stats
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("ホーム", systemImage: "house").tag(SidebarItem.home)
                    Label {
                        HStack {
                            Text("今日の学習")
                            Spacer()
                            let due = store.planner.dueItems().count
                            if due > 0 { Text("\(due)").font(.caption).padding(.horizontal, 6).background(.red.opacity(0.8), in: Capsule()).foregroundStyle(.white) }
                        }
                    } icon: { Image(systemName: "calendar.badge.clock") }
                    .tag(SidebarItem.review)
                    Label("間違いノート", systemImage: "exclamationmark.bubble").tag(SidebarItem.weak)
                }
                Section("学習") {
                    ForEach(Skill.allCases.filter(\.isAvailable)) { s in
                        Label(s.displayName, systemImage: s.systemImage).tag(SidebarItem.skill(s))
                    }
                }
                Section("今後追加予定") {
                    ForEach(Skill.allCases.filter { !$0.isAvailable }) { s in
                        Label(s.displayName, systemImage: s.systemImage)
                            .foregroundStyle(.secondary)
                            .tag(SidebarItem.skill(s))
                    }
                }
                Section {
                    Label("学習記録", systemImage: "chart.bar.xaxis").tag(SidebarItem.stats)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = store.statusMessage {
                Text(msg)
                    .font(.callout)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .onTapGesture { store.statusMessage = nil }
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(6))
                        if store.statusMessage == msg { store.statusMessage = nil }
                    }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home: HomeView(selection: $selection)
        case .review: TodaySessionView()
        case .weak: WeakItemsView()
        case .stats: StatsView()
        case let .skill(s):
            switch s {
            case .vocabulary: VocabularyView()
            case .grammar, .construction, .knowledge: UnitListView(skill: s)
            case .composition: CompositionListView()
            case .reading: ReadingListView()
            case .listening, .speaking: ComingSoonView(skill: s)
            }
        }
    }
}

struct ComingSoonView: View {
    let skill: Skill
    var body: some View {
        ContentUnavailableView {
            Label(skill.displayName, systemImage: skill.systemImage)
        } description: {
            Text("今後のアップデートで追加予定です。\nコンテンツ形式は音声データ（media）に対応済みのため、アプリ更新で順次利用可能になります。")
        }
    }
}
