#!/bin/zsh
# リリースビルドして build/EigoMaster.app を作る（中間生成物はすべてプロジェクト内）。
# 使い方: scripts/build_app.sh [--zip]   （--zip で配布用 zip を dist/ に作成）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# GitHub リポジトリ（owner/repo）を origin から推定。コンテンツ配信元の既定値に使う。
REPO="${EIGO_GITHUB_REPO:-}"
if [[ -z "$REPO" ]]; then
  url="$(git remote get-url origin 2>/dev/null || true)"
  REPO="$(echo "$url" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
fi
CONTENT_URL=""
[[ -n "$REPO" ]] && CONTENT_URL="https://raw.githubusercontent.com/$REPO/main/Content"

echo "▶ swift build (release) v$VERSION ($BUILD_NUMBER) repo=${REPO:-なし}"
scripts/swiftpm.sh build -c release --product EigoMaster

APP="$ROOT/build/EigoMaster.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/EigoMaster" "$APP/Contents/MacOS/EigoMaster"
cp -R "$ROOT/Content" "$APP/Contents/Resources/Content"
[[ -f "$ROOT/Sources/EigoApp/Resources/AppIcon.icns" ]] && cp "$ROOT/Sources/EigoApp/Resources/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>EigoMaster</string>
  <key>CFBundleDisplayName</key><string>英語マスター</string>
  <key>CFBundleIdentifier</key><string>com.eigomaster.app</string>
  <key>CFBundleExecutable</key><string>EigoMaster</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>ja</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>EigoGitHubRepository</key><string>$REPO</string>
  <key>EigoContentBaseURL</key><string>$CONTENT_URL</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "✅ $APP"

if [[ "${1:-}" == "--zip" ]]; then
  mkdir -p "$ROOT/dist"
  ditto -c -k --keepParent "$APP" "$ROOT/dist/EigoMaster-$VERSION.zip"
  echo "📦 dist/EigoMaster-$VERSION.zip"
fi
