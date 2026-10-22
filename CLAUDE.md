# EigoMaster 開発メモ

- ビルド・テストは必ず `scripts/swiftpm.sh`（キャッシュをリポジトリ内に置く）を使う。内蔵SSDの空き容量が少ないため、DerivedData や ~/Library のキャッシュは使わない。
- アプリは `scripts/build_app.sh` で `build/EigoMaster.app` を作る。
- コンテンツを変えたら：パックの `revision` を増やす → `eigo-tool validate` → `eigo-tool manifest Content 0.1.0`（引数は対応する最古のアプリ版。VERSION より新しくするとコンテンツ更新が止まる。schemaVersion を上げたときだけ引き上げる） → テスト。
- 公開済みの ID（パック・単語・単元・問題）は変更しない（学習記録が紐づいている）。
- 教材はすべてオリジナルで作成する（市販教材・過去問の転載は禁止）。
