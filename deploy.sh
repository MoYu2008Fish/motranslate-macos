#!/bin/bash
# Install/update the app, create a Finder alias, and pin one Dock entry.
set -euo pipefail
cd "$(dirname "$0")"

BUILD=1
LAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        --no-launch) LAUNCH=0 ;;
        -h|--help)
            echo '用法：./deploy.sh [--no-build] [--no-launch]'
            echo '默认重新构建，安装到应用程序，创建桌面替身、固定 Dock 并启动。'
            echo '--no-build   部署已有 build/MoTranslate.app'
            echo '--no-launch 部署后不启动应用'
            exit 0 ;;
        *) echo "未知选项：$arg" >&2; exit 2 ;;
    esac
done
if [ "$(id -u)" -eq 0 ]; then
    echo '请以当前桌面用户运行，不要使用 sudo，以免修改错误用户的桌面和 Dock。' >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo '需要 Xcode 26+ 或对应 Command Line Tools。' >&2
    exit 1
fi
# Prevent two double-click deployments from racing.
mkdir -p build
LOCK=build/.deploy-lock
if ! mkdir "$LOCK" 2>/dev/null; then
    echo '另一次部署正在进行。若上次异常中断，请确认没有部署进程后移除 build/.deploy-lock。' >&2
    exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

if [ "$BUILD" -eq 1 ]; then ./build.sh release; fi
APP="$(pwd)/build/MoTranslate.app"
codesign --verify --deep --strict "$APP"
TARGET_DIR=/Applications
if [ ! -w "$TARGET_DIR" ]; then
    if [ -e "$TARGET_DIR/MoTranslate.app" ]; then
        echo '现有 /Applications/MoTranslate.app 不可写，请调整该应用的文件权限后重试。' >&2
        exit 1
    fi
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
fi
TARGET="$TARGET_DIR/MoTranslate.app"
BACKUPS="$HOME/Library/Application Support/MoTranslate/DeploymentBackups"
# No AppleScript / Automation permission required. Uses native Finder bookmarks
# and merges only this app's persistent Dock tile through CFPreferences.
swift tools/deploy.swift "$APP" "$TARGET" "$BACKUPS" "$HOME/Desktop"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -x "$LSREGISTER" ]; then "$LSREGISTER" -f "$TARGET"; fi
# Reload the current user's Dock so the persisted entry/icon is immediately visible.
/usr/bin/killall -u "$(id -un)" Dock 2>/dev/null || true
if [ "$LAUNCH" -eq 1 ]; then /usr/bin/open "$TARGET"; fi
echo '部署完成。桌面和 Dock 中的「墨译」均打开同一份应用。'
