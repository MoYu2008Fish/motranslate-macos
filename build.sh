#!/bin/bash
# 构建并打包成 .app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/MoTranslate.app"

if [ -f "Resources/AppIcon-source.png" ]; then
    echo "==> 打包应用图标"
    swift tools/make-icon.swift
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "==> 编译 ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/MoTranslate"

echo "==> 打包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MoTranslate"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# 本地 ad-hoc 签名；源码重编译后，系统可能要求重新确认辅助功能授权。
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

SIZE=$(du -sh "$APP" | cut -f1)
echo "==> 完成: $APP ($SIZE)"
