import EigoCore
import SwiftUI

enum SidebarItem: Hashable {
    case home
    case review
    case weak
    case mockExam
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
                    Label {
                        HStack {
                            Text("模擬試験")
                            if store.mockSession?.isSubmitted == false {
                                Spacer()
                                Text("受験中").font(.caption).padding(.horizontal, 6).background(.orange.opacity(0.8), in: Capsule()).foregroundStyle(.white)
                            }
                        }
                    } icon: { Image(systemName: "timer") }
                    .tag(SidebarItem.mockExam)
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
        .onAppear(perform: applyLaunchArguments)
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

    /// 起動引数で画面を指定（動作確認用）。例: open EigoMaster.app --args -EigoStartScreen mockExam -EigoStartMockExam 3
    private func applyLaunchArguments() {
        let d = UserDefaults.standard
        switch d.string(forKey: "EigoStartScreen") {
        case "review": selection = .review
        case "weak": selection = .weak
        case "mockExam": selection = .mockExam
        case "stats": selection = .stats
        case let s?: if let skill = Skill(rawValue: s) { selection = .skill(skill) }
        case nil: break
        }
        let lv = d.integer(forKey: "EigoStartMockExam")
        if let level = Level(rawValue: lv), store.mockSession == nil {
            selection = .mockExam
            store.startMockExam(level: level)
            #if DEBUG
            // 動作確認用：半分の問題に正答して即提出
            if d.bool(forKey: "EigoMockAutoSubmit"), let session = store.mockSession {
                for (i, item) in session.exam.allItems.enumerated() where i % 2 == 0 {
                    session.answers[item.id] = item.exercise.answers.first
                }
                session.compositionText = "I think that students should read more books because reading helps them think deeply."
                session.submit()
            }
            #endif
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .home: HomeView(selection: $selection)
        case .review: TodaySessionView()
        case .weak: WeakItemsView()
        case .mockExam: MockExamHomeView()
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
