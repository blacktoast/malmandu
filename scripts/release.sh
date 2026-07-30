#!/bin/bash
# Malmandu 배포용 빌드 스크립트
#
# 사용법:
#   ./scripts/release.sh              # 기본 버전(0.0.1)
#   VERSION=0.1.0 ./scripts/release.sh
#
# 결과물:
#   .build/dist/Malmandu.app           — 실행 가능한 .app 번들 (universal, ad-hoc 서명됨)
#   .build/dist/Malmandu-<ver>.dmg     — 배포용 DMG
#   .build/dist/Malmandu-<ver>.dmg.sha256 — Homebrew Cask용 체크섬
set -euo pipefail

VERSION="${VERSION:-0.0.1}"
APP_NAME="Malmandu"
DISPLAY_NAME="말만두"
BUNDLE_ID="com.malmandu.app"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/.build/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
ICON_SRC="$PROJECT_DIR/mandu_smile.png"

if [ ! -f "$ICON_SRC" ]; then
  echo "❌ 아이콘 소스를 찾을 수 없습니다: $ICON_SRC" >&2
  exit 1
fi

echo "🧹 이전 빌드 정리..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "🔨 릴리스 빌드 (universal: arm64 + x86_64)..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
BINARY_PATH="$BIN_DIR/$APP_NAME"
if [ ! -f "$BINARY_PATH" ]; then
  echo "❌ 빌드된 바이너리를 찾을 수 없습니다: $BINARY_PATH" >&2
  exit 1
fi

echo "🎨 아이콘 생성 ($ICON_SRC → AppIcon.icns)..."
ICONSET="$DIST_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"     >/dev/null
sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png"  >/dev/null
iconutil -c icns "$ICONSET" -o "$DIST_DIR/AppIcon.icns"
rm -rf "$ICONSET"

echo "📦 .app 번들 구성..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$DIST_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' \
  -exec cp -R {} "$APP_DIR/Contents/Resources/" \;

for bundle in malmandu_Malmandu.bundle malmandu_MalmanduCore.bundle; do
  if [ ! -d "$APP_DIR/Contents/Resources/$bundle" ]; then
    echo "❌ 앱 리소스 번들을 찾을 수 없습니다: $bundle" >&2
    exit 1
  fi
done

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>말만두가 음성을 녹음하여 텍스트로 변환하기 위해 마이크 접근이 필요합니다.</string>
</dict>
</plist>
PLIST

echo "🔏 Ad-hoc 서명 (서명 신원 없음 → Gatekeeper 경고는 여전히 남음)..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --verbose "$APP_DIR" || {
  echo "❌ 서명 검증 실패" >&2
  exit 1
}

echo "💿 DMG 생성 (hdiutil)..."
DMG_STAGING="$DIST_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Malmandu $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGING"
rm -f "$DIST_DIR/AppIcon.icns"

SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "$SHA" > "$DMG_PATH.sha256"

SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"

echo ""
echo "✅ 릴리스 빌드 완료"
echo "   버전:     $VERSION"
echo "   App:      $APP_DIR"
echo "   DMG:      $DMG_PATH ($SIZE)"
echo "   SHA-256:  $SHA"
echo ""
echo "다음 단계:"
echo "  1. 로컬 설치 테스트:  open \"$DMG_PATH\""
echo "  2. GitHub Release 업로드:"
echo "     gh release create v$VERSION \"$DMG_PATH\" --title \"v$VERSION\" --notes \"Release $VERSION\""
echo "  3. Homebrew tap Cask 파일에 SHA-256 갱신:"
echo "     $SHA"
