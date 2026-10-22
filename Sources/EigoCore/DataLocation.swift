import Foundation

/// 進捗・ダウンロードしたコンテンツの保存先。
/// 内蔵SSDを圧迫しないよう、設定で外付けボリューム等に変更できる。
public enum DataLocation {
    public static let defaultsKey = "dataDirectory"
    public static let envKey = "EIGO_DATA_DIR"

    /// 優先順位: 環境変数 > ユーザー設定 > ~/Library/Application Support/EigoMaster
    public static func resolve(defaults: UserDefaults = .standard) -> URL {
        if let env = ProcessInfo.processInfo.environment[envKey], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let path = defaults.string(forKey: defaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EigoMaster", isDirectory: true)
    }

    public static func ensure(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
