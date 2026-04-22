#!/bin/bash
# malmandu 앱을 .app 번들로 래핑하여 실행하는 스크립트
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Malmandu"
APP_DIR="$PROJECT_DIR/.build/${APP_NAME}.app"

echo "🔨 빌드 중..."
cd "$PROJECT_DIR"
swift build

echo "📦 .app 번들 생성 중..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 바이너리 복사
cp ".build/arm64-apple-macosx/debug/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Info.plist 생성
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>malmandu</string>
    <key>CFBundleDisplayName</key>
    <string>malmandu</string>
    <key>CFBundleIdentifier</key>
    <string>com.malmandu.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>Malmandu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>malmandu가 음성을 녹음하여 텍스트로 변환하기 위해 마이크 접근이 필요합니다.</string>
</dict>
</plist>
PLIST

echo "🚀 앱 실행 중..."
open "$APP_DIR"
echo "✅ 메뉴바 상단에서 마이크 아이콘(🎙)을 확인하세요!"
