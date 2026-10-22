import EigoCore
import SwiftUI

/// 文法・構文・基礎知識の単元一覧
struct UnitListView: View {
    @Environment(AppStore.self) private var store
    let skill: Skill

    var body: some View {
        let units = store.library.units(for: skill)
        Group {
            if units.isEmpty {
                ContentUnavailableView("単元がありません", systemImage: skill.systemImage, description: Text("コンテンツ更新で追加されます。"))
            } else {
                List {
                    ForEach(Level.allCases) { lv in
                        let list = units.filter { $0.level == lv }
                        if !list.isEmpty {
                            Section(lv.title) {
                                ForEach(list) { u in
                                    NavigationLink(value: u) { UnitRow(unit: u) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(skill.displayName)
        .navigationDestination(for: StudyUnit.self) { UnitDetailView(unit: $0, skill: skill) }
    }
}

struct UnitRow: View {
    @Environment(AppStore.self) private var store
    let unit: StudyUnit

    var body: some View {
        let keys = unit.exercises.map { ItemKey.exercise($0.id) }
        let seen = store.progress.seen(keys: keys)
        let mastered = store.progress.mastered(keys: keys)
        HStack {
            Image(systemName: store.progress.completedUnits.contains(unit.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(store.progress.completedUnits.contains(unit.id) ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if let c = unit.category { Text(c).font(.caption).foregroundStyle(.blue) }
                    Text(unit.title).bold()
                }
                Text(unit.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("演習 \(seen)/\(unit.exercises.count)・定着 \(mastered)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct UnitDetailView: View {
    @Environment(AppStore.self) private var store
    let unit: StudyUnit
    let skill: Skill
    @State private var session: [StudyItem]?

    var body: some View {
        Group {
            if let session {
                StudySessionView(title: unit.title, items: session) {
                    store.markUnitCompleted(unit.id)
                    self.session = nil
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(unit.level.title)\(unit.category.map { "・" + $0 } ?? "")").font(.caption).foregroundStyle(.secondary)
                            Text(unit.title).font(.largeTitle.bold())
                            Text(unit.summary).font(.title3).foregroundStyle(.secondary)
                        }
                        MarkdownText(markdown: unit.explanation)
                        if !unit.examples.isEmpty {
                            Text("例文").font(.title3.bold())
                            ForEach(unit.examples, id: \.self) { ex in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ex.en).font(.body.italic()).textSelection(.enabled)
                                    Text(ex.ja).foregroundStyle(.secondary)
                                    if let n = ex.note { Text(n).font(.caption).foregroundStyle(.blue) }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        HStack {
                            Button {
                                session = unit.exercises.map { .exercise($0, skill: skill) }
                            } label: {
                                Label("演習を始める（\(unit.exercises.count) 問）", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(unit.exercises.isEmpty)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(unit.title)
    }
}

/// 簡易 Markdown 表示（見出し・箇条書き・段落・表をブロック単位で整形）
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                block(b)
            }
        }
        .textSelection(.enabled)
    }

    private var blocks: [String] {
        markdown.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func block(_ b: String) -> some View {
        if b.hasPrefix("### ") {
            Text(inline(String(b.dropFirst(4)))).font(.headline).padding(.top, 4)
        } else if b.hasPrefix("## ") {
            Text(inline(String(b.dropFirst(3)))).font(.title3.bold()).padding(.top, 6)
        } else if b.hasPrefix("|") {
            table(b)
        } else if b.hasPrefix("> ") {
            Text(inline(b.split(separator: "\n").map { String($0.dropFirst(2)) }.joined(separator: "\n")))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(b.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    let l = String(line)
                    if l.hasPrefix("- ") || l.hasPrefix("・") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(inline(l.hasPrefix("- ") ? String(l.dropFirst(2)) : String(l.dropFirst(1))))
                        }
                    } else {
                        Text(inline(l))
                    }
                }
            }
        }
    }

    private func table(_ b: String) -> some View {
        let rows = b.split(separator: "\n").map(String.init).filter { !$0.contains("---") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                GridRow {
                    ForEach(Array(r.enumerated()), id: \.offset) { _, cell in
                        Text(inline(cell)).fontWeight(i == 0 ? .bold : .regular)
                    }
                }
                if i == 0 { Divider() }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
