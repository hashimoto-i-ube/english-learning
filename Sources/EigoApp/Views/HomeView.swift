import EigoCore
import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: SidebarItem?

    var body: some View {
        @Bindable var store = store
        let planner = store.planner
        let today = store.progress.daily[LearnerProgress.dayKey()]

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let rel = store.availableRelease, let url = URL(string: rel.html_url) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                        Text("新しいバージョン \(rel.tag_name) が公開されています。")
                        Spacer()
                        Link("ダウンロードページを開く", destination: url)
                    }
                    .padding()
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text("英語マスター").font(.largeTitle.bold())
                        Text("高校入学レベルから難関大・医学部合格レベルまで").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("現在のレベル", selection: $store.progress.settings.currentLevel) {
                        ForEach(Level.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 320)
                    .onChange(of: store.progress.settings.currentLevel) { store.save() }
                }

                HStack(spacing: 12) {
                    StatTile(title: "復習待ち", value: "\(planner.dueItems().count)", systemImage: "clock.arrow.circlepath", tint: .orange)
                    StatTile(title: "今日の学習", value: "\(today?.reviews ?? 0) 問", systemImage: "checkmark.circle", tint: .green)
                    StatTile(title: "正答率", value: today.map { $0.reviews == 0 ? "-" : "\(Int(Double($0.correct) / Double($0.reviews) * 100))%" } ?? "-", systemImage: "target", tint: .blue)
                    StatTile(title: "連続学習", value: "\(store.progress.streak()) 日", systemImage: "flame", tint: .red)
                }

                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("今日のおすすめ学習").font(.headline)
                            Text("復習 \(planner.dueItems().count) 件 ＋ 新出単語・文法・構文（\(store.progress.settings.currentLevel.shortTitle) まで）")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            selection = .review
                        } label: {
                            Label("学習を始める", systemImage: "play.fill").padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(6)
                }

                Text("分野別の進捗").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(Skill.allCases.filter(\.isAvailable)) { s in
                        let c = planner.coverage(skill: s)
                        Button { selection = .skill(s) } label: {
                            SkillProgressCard(skill: s, seen: c.seen, mastered: c.mastered, total: c.total)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !store.library.notices.isEmpty {
                    Text("お知らせ・入試情報").font(.title3.bold())
                    ForEach(store.library.notices.prefix(5)) { n in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(n.title).font(.headline)
                                    Spacer()
                                    Text(n.date).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(n.body).font(.callout).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if !store.library.loadErrors.isEmpty {
                    GroupBox("読み込めなかったコンテンツ") {
                        ForEach(store.library.loadErrors, id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("ホーム")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.updateContent() }
                } label: {
                    if store.isUpdating { ProgressView().controlSize(.small) } else { Label("コンテンツ更新", systemImage: "arrow.triangle.2.circlepath") }
                }
                .help("最新の単語・問題・入試情報をダウンロード")
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage).font(.caption).foregroundStyle(tint)
            Text(value).font(.title2.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SkillProgressCard: View {
    let skill: Skill
    let seen: Int
    let mastered: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(skill.displayName, systemImage: skill.systemImage).font(.headline)
            ProgressView(value: Double(seen), total: Double(max(total, 1))) {
                Text("学習済み \(seen) / \(total)").font(.caption)
            }
            ProgressView(value: Double(mastered), total: Double(max(total, 1))) {
                Text("定着 \(mastered)").font(.caption)
            }
            .tint(.green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}
