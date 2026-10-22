import Foundation

/// 解答の正誤判定（表記ゆれを吸収）
public enum AnswerChecker {
    /// 比較用に正規化：小文字化、記号の統一、句読点除去、空白の圧縮
    public static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        let replacements: [(String, String)] = [
            ("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\""),
            ("　", " "), ("—", "-"), ("–", "-"),
        ]
        for (a, b) in replacements { t = t.replacingOccurrences(of: a, with: b) }
        // 文中の短縮形を展開して揺れを吸収
        let contractions: [(String, String)] = [
            ("can't", "cannot"), ("won't", "will not"), ("n't", " not"),
            ("i'm", "i am"), ("'re", " are"), ("'ve", " have"), ("'ll", " will"), ("'d", " would"),
        ]
        for (a, b) in contractions { t = t.replacingOccurrences(of: a, with: b) }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "'-"))
        t = String(t.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func isCorrect(_ input: String, answers: [String]) -> Bool {
        let n = normalize(input)
        guard !n.isEmpty else { return false }
        return answers.contains { normalize($0) == n }
    }

    /// 英文の語数（自由英作文の語数カウント用）
    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\n" })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }
}
