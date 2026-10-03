#!/bin/zsh
#
# 构建“重启到 Windows.app”。
#   ./build.sh            只构建到 build/
#   ./build.sh --install  构建并安装到 /Applications

set -euo pipefail

ROOT=${0:A:h}
APP_NAME="重启到 Windows"
BUNDLE_ID="local.wendao.reboot-to-windows"
VERSION="2.0"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
INSTALLED="/Applications/$APP_NAME.app"

rm -rf "$BUILD"
mkdir -p "$BUILD"

# 图标
swift "$ROOT/app/make-icon.swift" "$BUILD/icon-1024.png"
ICONSET="$BUILD/applet.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
	sips -z $size $size "$BUILD/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
	sips -z $((size * 2)) $((size * 2)) "$BUILD/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/applet.icns"

# App 本体
osacompile -o "$APP" "$ROOT/app/main.applescript"
cp "$BUILD/applet.icns" "$APP/Contents/Resources/applet.icns"
rm -f "$APP/Contents/Resources/Assets.car"   # 否则系统会优先用里面的默认脚本图标
install -m 755 "$ROOT/$APP_NAME.command" "$APP/Contents/Resources/reboot-to-windows.command"

PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleName -string "$APP_NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
plutil -replace NSAppleEventsUsageDescription -string "设置好启动项后，需要向系统发送“重新启动”指令。" "$PLIST"
plutil -replace NSSystemAdministrationUsageDescription -string "需要管理员权限来设置下一次启动的系统。" "$PLIST"
# osacompile 默认带的这些权限说明本 App 都用不到
for key in CFBundleIconName NSAppleMusicUsageDescription NSCalendarsUsageDescription NSCameraUsageDescription \
	NSContactsUsageDescription NSHomeKitUsageDescription NSMicrophoneUsageDescription \
	NSPhotoLibraryUsageDescription NSRemindersUsageDescription NSSiriUsageDescription; do
	plutil -remove $key "$PLIST" 2>/dev/null || true
done

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
print "已构建：$APP"

if [[ ${1:-} == --install ]]; then
	if [[ -e $INSTALLED ]]; then
		existing_id=$(plutil -extract CFBundleIdentifier raw -o - "$INSTALLED/Contents/Info.plist" 2>/dev/null || true)
		if [[ $existing_id != "$BUNDLE_ID" ]]; then
			print -u2 "$INSTALLED 已存在且不是本项目构建的（$existing_id），不覆盖。"
			exit 1
		fi
		rm -rf "$INSTALLED"
	fi
	ditto "$APP" "$INSTALLED"
	codesign --verify --strict "$INSTALLED"
	print "已安装：$INSTALLED"
fi
