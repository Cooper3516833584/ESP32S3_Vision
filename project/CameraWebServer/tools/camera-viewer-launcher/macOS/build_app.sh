#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/dist"
APP_PATH="$OUTPUT_DIR/Camera Viewer.app"

command -v swiftc >/dev/null 2>&1 || {
  echo "需要在 macOS 上使用 Xcode Command Line Tools 提供的 swiftc 构建 Camera Viewer.app。" >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
swiftc -O -target arm64-apple-macosx11.0 \
  -framework AppKit -framework Foundation \
  "$SCRIPT_DIR/CameraViewer.swift" \
  -o "$OUTPUT_DIR/CameraViewer-arm64"
swiftc -O -target x86_64-apple-macosx11.0 \
  -framework AppKit -framework Foundation \
  "$SCRIPT_DIR/CameraViewer.swift" \
  -o "$OUTPUT_DIR/CameraViewer-x86_64"
lipo -create "$OUTPUT_DIR/CameraViewer-arm64" "$OUTPUT_DIR/CameraViewer-x86_64" \
  -output "$APP_PATH/Contents/MacOS/CameraViewer"
rm -f "$OUTPUT_DIR/CameraViewer-arm64" "$OUTPUT_DIR/CameraViewer-x86_64"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>CameraViewer</string>
  <key>CFBundleIdentifier</key><string>org.esp32s3vision.cameraviewer</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Camera Viewer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Camera Viewer 需要访问本地网络，用于连接 ESP32-S3 摄像头开发板。</string>
</dict>
</plist>
PLIST

chmod +x "$APP_PATH/Contents/MacOS/CameraViewer"
plutil -lint "$APP_PATH/Contents/Info.plist"
"$APP_PATH/Contents/MacOS/CameraViewer" --self-test
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/Camera-Viewer-macOS.zip"
echo "已生成：$APP_PATH"
