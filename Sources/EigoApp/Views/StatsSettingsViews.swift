import AppKit
import Charts
import EigoCore
import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let days = (0..<30).reversed().map { offset -> DailyStat in
            let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let key = LearnerProgress.dayKey(d)
            return store.progress.daily[key] ?? DailyStat(date: key)
        }
        let total = store.progress.daily.values.reduce(0) { $0 + $1.reviews }
        let minutes = store.progress.daily.values.reduce(0) { $0 + $1.minutes }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    StatTile(title: "累計解答数", value: "\(total)", systemImage: "sum", tint: .blue)
                    StatTile(title: "累計学習時間", value: "\(Int(minutes / 60))時間\(Int(minutes) % 60)分", systemImage: "clock", tint: .purple)
                    StatTile(title: "定着した単語", value: "\(store.progress.mastered(keys: store.library.words.map { ItemKey.word($0.id) }))", systemImage: "brain", tint: .green)
                    StatTile(title: "連続学習", value: "\(store.progress.streak()) 日", systemImage: "flame", tint: .red)
                }

                GroupBox("直近30日の解答数") {
                    Chart(days, id: \.date) { d in
                        BarMark(x: .value("日付", String(d.date.suffix(5))), y: .value("解答数", d.reviews))
                            .foregroundStyle(.blue.gradient)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: 5)) }
                    .frame(height: 200)
                }

                GroupBox("直近30日の正答率") {
                    Chart(days.filter { $0.reviews > 0 }, id: \.date) { d in
                        LineMark(x: .value("日付", String(d.date.suffix(5))), y: .value("正答率", Double(d.correct) / Double(d.reviews) * 100))
                        PointMark(x: .value("日付", String(d.date.suffix(5))), y: .value("正答率", Double(d.correct) / Double(d.reviews) * 100))
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 180)
                }

                GroupBox("レベル別 単語の定着") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        ForEach(Level.allCases) { lv in
                            let keys = store.library.words.filter { $0.level == lv }.map { ItemKey.word($0.id) }
                            if !keys.isEmpty {
                                GridRow {
                                    Text(lv.title)
                                    ProgressView(value: Double(store.progress.mastered(keys: keys)), total: Double(keys.count)).frame(width: 240)
                                    Text("\(store.progress.mastered(keys: keys)) / \(keys.count)").monospacedDigit()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !store.progress.readings.isEmpty {
                    GroupBox("長文の読解速度の推移") {
                        Chart(Array(store.progress.readings.enumerated()), id: \.offset) { i, r in
                            LineMark(x: .value("回", i + 1), y: .value("wpm", r.wordsPerMinute))
                            PointMark(x: .value("回", i + 1), y: .value("wpm", r.wordsPerMinute))
                        }
                        .frame(height: 160)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("学習記録")
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var apiKeyDraft = ""

    var body: some View {
        @Bindable var store = store
        TabView {
            Form {
                Picker("現在のレベル", selection: $store.progress.settings.currentLevel) {
                    ForEach(Level.allCases) { Text($0.title).tag($0) }
                }
                Picker("目標レベル", selection: $store.progress.settings.targetLevel) {
                    ForEach(Level.allCases) { Text($0.title).tag($0) }
                }
                Stepper("1日の新出単語: \(store.progress.settings.dailyNewWords) 語", value: $store.progress.settings.dailyNewWords, in: 0...200, step: 5)
                Stepper("1日の新出演習: \(store.progress.settings.dailyNewExercises) 問", value: $store.progress.settings.dailyNewExercises, in: 0...100, step: 2)
            }
            .formStyle(.grouped)
            .tabItem { Label("学習", systemImage: "graduationcap") }

            Form {
                Section("データの保存先") {
                    Text(store.dataDirectory.path).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("変更…") { chooseDirectory() }
                        Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([store.dataDirectory]) }
                    }
                    Text("進捗とダウンロードしたコンテンツを保存します。外付けボリュームを指定できます。").font(.caption).foregroundStyle(.secondary)
                }
                Section("コンテンツ更新") {
                    TextField("配信元URL（空欄で既定値）", text: $store.progress.settings.contentBaseURL)
                    TextField("GitHub リポジトリ（owner/repo、空欄で既定値）", text: $store.progress.settings.githubRepository)
                    Text("現在: \(store.contentBaseURL?.absoluteString ?? "未設定")").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("今すぐコンテンツを更新") { Task { await store.updateContent() } }
                        Button("アプリの更新を確認") {
                            Task {
                                await store.checkAppUpdate()
                                store.statusMessage = store.availableRelease.map { "新バージョン \($0.tag_name) があります" } ?? "アプリは最新です（v\(store.appVersion)）"
                            }
                        }
                        if store.isUpdating { ProgressView().controlSize(.small) }
                    }
                    if let msg = store.statusMessage { Text(msg).font(.caption) }
                    Text("収録パック: \(store.library.packs.count)・単語 \(store.library.words.count) 語").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("データと更新", systemImage: "arrow.triangle.2.circlepath") }

            Form {
                Section {
                    Toggle("AI 添削を使う", isOn: $store.progress.settings.aiEnabled)
                    SecureField("Anthropic API キー", text: $apiKeyDraft)
                    HStack {
                        Button("キーを保存") { store.apiKey = apiKeyDraft; store.statusMessage = "API キーを保存しました" }
                            .disabled(apiKeyDraft.isEmpty)
                        Button("キーを削除") { store.apiKey = ""; apiKeyDraft = "" }
                        Spacer()
                        Text(store.apiKey.isEmpty ? "未登録" : "登録済み").foregroundStyle(.secondary)
                    }
                    TextField("モデル", text: $store.progress.settings.aiModel)
                } footer: {
                    Text("英作文の添削に Claude API を使います（任意・従量課金）。キーは macOS のキーチェーンに保存され、答案は添削時のみ Anthropic に送信されます。")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("AI添削", systemImage: "sparkles") }
        }
        .onChange(of: store.progress.settings) { store.save() }
        .padding()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "ここに保存"
        if panel.runModal() == .OK, let url = panel.url { store.setDataDirectory(url) }
    }
}
