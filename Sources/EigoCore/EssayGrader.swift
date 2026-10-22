import Foundation
import Security

/// AI 添削の結果
public struct EssayFeedback: Codable, Hashable, Sendable {
    public struct Correction: Codable, Hashable, Sendable {
        public var original: String
        public var corrected: String
        public var explanation: String
    }

    /// 観点別評価（各0〜5）
    public var content: Int
    public var organization: Int
    public var vocabulary: Int
    public var grammar: Int
    /// 入試の想定得点率（0〜100）
    public var estimatedScore: Int
    public var overall: String
    public var corrections: [Correction]
    public var revisedText: String
    public var advice: [String]
}

/// Claude API（Messages API）を使った英作文添削。
/// API キーは利用者自身のものを Keychain に保存して使う（任意機能）。
public struct EssayGrader: Sendable {
    public enum GradeError: Error, LocalizedError {
        case noKey
        case http(Int, String)
        case refused
        case unparsable(String)

        public var errorDescription: String? {
            switch self {
            case .noKey: return "API キーが設定されていません（設定 > AI添削）。"
            case let .http(code, msg): return "API エラー (\(code)): \(msg)"
            case .refused: return "この答案は添削できませんでした。表現を変えて再度お試しください。"
            case let .unparsable(s): return "添削結果を読み取れませんでした: \(s.prefix(200))"
            }
        }
    }

    public var apiKey: String
    public var model: String

    public init(apiKey: String, model: String = "claude-opus-5-5") {
        self.apiKey = apiKey
        self.model = model
    }

    static let systemPrompt = """
    あなたは日本の難関大学（旧帝大・医学部を含む）の英語入試に精通した英作文の採点者です。
    高校生の答案を、入試の採点基準に沿って公平かつ具体的に添削してください。
    - 誤りは文法・語法・語彙選択・論理構成・設問条件の順に確認する。
    - 減点対象の箇所は corrections に「元の表現」「直した表現」「理由（日本語）」で挙げる。
    - revisedText は答案の意図と語数条件を保ったまま、受験生が再現できる水準で書き直す。
    - advice は次回に生かせる学習アドバイスを日本語で2〜4項目。
    出力は指定の JSON オブジェクトのみとし、前後に説明文を付けないこと。
    JSON 形式:
    {"content":0-5,"organization":0-5,"vocabulary":0-5,"grammar":0-5,"estimatedScore":0-100,
     "overall":"総評（日本語）","corrections":[{"original":"","corrected":"","explanation":""}],
     "revisedText":"","advice":[""]}
    """

    public func grade(prompt: CompositionPrompt, answer: String) async throws -> EssayFeedback {
        guard !apiKey.isEmpty else { throw GradeError.noKey }

        let user = """
        【問題の種類】\(prompt.kind.displayName)
        【問題】\(prompt.promptJa)
        【条件】\(prompt.conditions ?? "特になし")
        【採点ポイント】\(prompt.keyPoints.joined(separator: " / "))
        【参考模範解答】\(prompt.modelAnswers.first ?? "")
        【受験生の答案】
        \(answer)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": Self.systemPrompt,
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "messages": [["role": "user", "content": user]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GradeError.unparsable(String(decoding: data, as: UTF8.self))
        }
        guard (200..<300).contains(code) else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "不明なエラー"
            throw GradeError.http(code, msg)
        }
        if json["stop_reason"] as? String == "refusal" { throw GradeError.refused }

        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return try Self.parseFeedback(text)
    }

    /// 応答テキストから JSON オブジェクト部分を取り出してデコード
    public static func parseFeedback(_ text: String) throws -> EssayFeedback {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw GradeError.unparsable(text)
        }
        let data = Data(text[start...end].utf8)
        do {
            return try JSONDecoder().decode(EssayFeedback.self, from: data)
        } catch {
            throw GradeError.unparsable(text)
        }
    }
}

/// API キーを Keychain に保存する
public enum KeychainStore {
    static let service = "com.eigomaster.app"

    public static func save(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func load(account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
