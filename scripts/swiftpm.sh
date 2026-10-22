#!/bin/zsh
# SwiftPM を、キャッシュ・中間生成物をすべてプロジェクト内（外付けボリューム）に置いて実行する。
# 使い方: scripts/swiftpm.sh build -c release / scripts/swiftpm.sh test
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$ROOT/.cache/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.cache/swiftpm-module-cache"
export TMPDIR="$ROOT/.cache/tmp/"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"
cmd="$1"; shift
exec swift "$cmd" --package-path "$ROOT" \
  --scratch-path "$ROOT/.build" \
  --cache-path "$ROOT/.cache/swiftpm" \
  --config-path "$ROOT/.cache/swiftpm-config" \
  --security-path "$ROOT/.cache/swiftpm-security" \
  "$@"
