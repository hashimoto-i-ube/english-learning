import EigoCore
import Foundation

// 使い方:
//   eigo-tool validate <Content ディレクトリ>   … 全パックの形式・ID重複・正解の整合性を検査
//   eigo-tool manifest <Content ディレクトリ> [最小アプリバージョン]   … manifest.json を再生成
//   eigo-tool stats <Content ディレクトリ>      … レベル別の収録数を表示

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: eigo-tool validate|manifest|stats <ContentDir> [minAppVersion]")
    exit(2)
}
let command = args[1]
let contentDir = URL(fileURLWithPath: args[2], isDirectory: true)
let packsDir = contentDir.appendingPathComponent("packs", isDirectory: true)

func loadLibrary() -> ContentLibrary {
    let lib = ContentLibrary(directories: [packsDir])
    for e in lib.loadErrors { print("❌ 読み込みエラー: \(e)") }
    return lib
}

switch command {
case "validate":
    let lib = loadLibrary()
    let problems = lib.validate()
    for p in problems { print("⚠️  \(p)") }
    print("packs=\(lib.packs.count) words=\(lib.words.count) units=\(lib.units.values.map(\.count).reduce(0, +)) compositions=\(lib.compositions.count) passages=\(lib.passages.count)")
    exit(problems.isEmpty && lib.loadErrors.isEmpty ? 0 : 1)

case "manifest":
    var entries: [ManifestEntry] = []
    for url in ContentLibrary.packFiles(in: packsDir) {
        do {
            let data = try Data(contentsOf: url)
            let pack = try ContentLibrary.decodePack(data: data)
            entries.append(ManifestEntry(id: pack.id, file: "packs/\(url.lastPathComponent)", revision: pack.revision,
                                         sha256: ContentUpdater.sha256(data), skill: pack.skill, title: pack.title))
        } catch {
            print("❌ \(url.lastPathComponent): \(error)")
            exit(1)
        }
    }
    let f = ISO8601DateFormatter()
    let manifest = ContentManifest(schemaVersion: ContentPack.supportedSchemaVersion, generatedAt: f.string(from: Date()),
                                   minAppVersion: args.count > 3 ? args[3] : nil, packs: entries)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try enc.encode(manifest).write(to: contentDir.appendingPathComponent("manifest.json"))
    print("manifest.json を更新しました（\(entries.count) packs）")

case "stats":
    let lib = loadLibrary()
    for lv in Level.allCases {
        let w = lib.words.filter { $0.level == lv }.count
        let u = lib.units.values.flatMap { $0 }.filter { $0.level == lv }
        let ex = u.flatMap(\.exercises).count
        let c = lib.compositions.filter { $0.level == lv }.count
        let p = lib.passages.filter { $0.level == lv }.count
        print("\(lv.shortTitle): 単語 \(w) / 単元 \(u.count)（演習 \(ex)） / 英作文 \(c) / 長文 \(p)")
    }

default:
    print("unknown command: \(command)")
    exit(2)
}
