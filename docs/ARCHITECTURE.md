# アーキテクチャ

```
Sources/
  EigoCore/       UI に依存しないロジック（将来の iOS 版や CLI でも再利用）
    Models.swift          コンテンツの型（Word, StudyUnit, Exercise, CompositionPrompt, Passage, ContentPack）
    ContentLibrary.swift  パックの読み込み・統合（revision の大きい方を採用）・検証
    ContentUpdater.swift  manifest を見て差分パックをダウンロード（SHA-256 検証）、GitHub Releases の確認
    SRS.swift             間隔反復スケジューラ（SM-2 を簡略化）
    Progress.swift        学習記録（JSON 1ファイル、欠けたキーは既定値で読み込む前方互換デコード）
    StudyPlanner.swift    「今日の学習」の組み立て、分野別の進捗集計
    AnswerChecker.swift   解答の表記ゆれ吸収（大文字小文字・句読点・短縮形）
    EssayGrader.swift     Claude API による英作文添削（任意）、API キーはキーチェーンに保存
    DataLocation.swift    保存先の決定（環境変数 > 設定 > Application Support）
  EigoApp/        SwiftUI の macOS アプリ
  EigoTool/       コンテンツの検証・manifest 生成・統計を行う CLI
Content/
  manifest.json   配信用の目録（eigo-tool manifest で生成）
  packs/*.json    コンテンツパック
Tests/EigoCoreTests  ロジックとコンテンツの整合性のテスト
scripts/
  swiftpm.sh      キャッシュをリポジトリ内に置いて swift を実行するラッパー
  build_app.sh    .app バンドルを作成（Info.plist に配信元 URL を埋め込む）
```

## コンテンツの読み込み順

1. アプリ同梱：`EigoMaster.app/Contents/Resources/Content/packs`
2. ダウンロード済み：`<データフォルダ>/content/packs`

同じ `id` のパックは `revision` が大きい方が使われます。新しい形式（`schemaVersion` がアプリの対応より大きい）のパックは読み込まず、アプリ更新を促します。

## 拡張の余地

- **リスニング・スピーキング**：`Skill.listening / .speaking` を予約済みです。`Word`・`Exercise`・`Passage` には音声などの参照を持つ `media` フィールドがあり、今のバージョンでは無視されます。機能を実装したら `Skill.isAvailable` を変更し、ビューを追加します。
- **新しい問題形式**：`ExerciseType` に case を追加し、`ExerciseView` に UI を足します。古いアプリで新形式のパックを読めないようにするため、`schemaVersion` を上げます。
- **学習記録の移行**：`LearnerProgress` はキーが欠けていても既定値で読み込めるため、フィールドを足しても既存の進捗は失われません。
- **AI 機能**：`EssayGrader` と同じパターン（キーチェーンのキーと Messages API）で、例えば和訳添削や弱点分析を追加できます。
