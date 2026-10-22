# コンテンツ作成ガイド

## パックの基本形

```json
{
  "schemaVersion": 1,
  "id": "vocab.core.l3",
  "revision": 2,
  "skill": "vocabulary",
  "title": "Lv3 共通テスト基礎語彙",
  "words": [ ... ],
  "units": [ ... ],
  "compositions": [ ... ],
  "passages": [ ... ],
  "notices": [ ... ]
}
```

- `skill`: `vocabulary` / `grammar` / `construction` / `composition` / `reading` / `knowledge`
- `units` は `skill` の分野（文法・構文・基礎知識）に表示されます
- `revision` は**内容を変えたら必ず増やしてください**（増やさないと配信されません）
- `id`（パック・単語・単元・問題）は**一度公開したら変えないでください**。学習記録はこの ID に紐づいています

## 単語

```json
{"id": "w-acquire", "headword": "acquire", "pos": "動", "meanings": ["習得する", "獲得する"], "level": 3,
 "ipa": "/əˈkwaɪər/", "example": {"en": "...", "ja": "..."},
 "derivatives": ["acquisition 名 習得"], "synonyms": [], "antonyms": [], "collocations": [],
 "note": "語法・注意点", "accentNote": "アクセント注意"}
```

## 演習（Exercise）

| type | 用途 | 必須 |
|---|---|---|
| `choice` | 選択問題 | `choices`、`answers` は選択肢の文字列と完全に一致させる |
| `fill` | 空所補充 | `sentence` に `___`、`answers` に許容解を複数 |
| `reorder` | 整序 | `choices` = 語句（正解の語順で書いてよい。表示時にシャッフルされる）、`answers[0]` = 正解文 |
| `translateToJa` | 英文和訳 | `keyPoints` に採点ポイント |
| `translateToEn` | 和文英訳 | `answers` に複数の模範解答（完全一致なら自動で正解）、`keyPoints` |
| `shortAnswer` | 内容説明など | `keyPoints` |

`explanation` は Markdown（太字・斜体など行内の書式のみ）で書けます。

## 単元の解説（explanation）

段落は空行で区切ります。使える書式：`## 見出し`、`### 小見出し`、`- 箇条書き`、`| 表 |`、`> 注意ボックス`、`**太字**`。

## 公開手順

```bash
scripts/swiftpm.sh build --product eigo-tool
.build/debug/eigo-tool validate Content     # 形式・ID重複・正解の整合性
.build/debug/eigo-tool manifest Content     # manifest.json を再生成
.build/debug/eigo-tool stats Content        # レベル別の収録数
scripts/swiftpm.sh test                     # manifest とパックの整合性も検査
git commit -am "content: ..." && git push
```

## 著作権

市販の単語帳・問題集・入試過去問の本文や問題を転載しないでください。例文・長文はすべてオリジナルで作成します。
