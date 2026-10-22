#!/bin/zsh
# ULSハブ用の Web 版パッケージ dist/hub/eigo-master-<build>.zip を作る。
# 使い方: scripts/build_hub_package.sh [build番号]   （省略時は 日付(YYYYMMDD)+連番2桁。例 2026102301）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(cat VERSION)"
OUT="$ROOT/dist/hub"; mkdir -p "$OUT"

BUILD="${1:-}"
if [[ -z "$BUILD" ]]; then
  D="$(date +%Y%m%d)"; N=1
  while [[ -e "$OUT/eigo-master-$D$(printf %02d $N).zip" ]]; do N=$((N+1)); done
  BUILD="$D$(printf %02d $N)"
fi
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "build は整数で指定してください" >&2; exit 1; }

STAGE="$(mktemp -d "$ROOT/dist/.hubstage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R hub/css hub/js hub/index.html hub/icon.png "$STAGE/"
mkdir -p "$STAGE/content"
cp -R Content/packs Content/manifest.json "$STAGE/content/"
sed "s/__VERSION__/$VERSION/; s/__BUILD__/$BUILD/" hub/tool.json > "$STAGE/tool.json"

ZIP="$OUT/eigo-master-$BUILD.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr -X "$ZIP" tool.json index.html icon.png css js content)
echo "▶ $ZIP"
echo "  build : $BUILD"
echo "  size  : $(stat -f %z "$ZIP") bytes"
echo "  sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
