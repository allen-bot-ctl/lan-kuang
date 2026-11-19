#!/usr/bin/env bash
# 用法：scripts/build.sh VERSION   （仅 macOS）
# 产物：dist/$NAME-$VERSION-mac-universal.{dmg,zip,zip.sha256}
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?用法: scripts/build.sh VERSION}"
VERSION="${VERSION#v}"
# shellcheck disable=SC1091
source ./project.env

SPARKLE_DIR="vendor/Sparkle-${SPARKLE_VERSION}"
if [ ! -d "$SPARKLE_DIR/Sparkle.framework" ]; then
  echo "下载 Sparkle ${SPARKLE_VERSION}"
  mkdir -p "$SPARKLE_DIR"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    | tar -xJ -C "$SPARKLE_DIR"
fi

rm -rf build dist
mkdir -p build dist
SOURCES=(App/*.swift Sources/MonitorCore/*.swift)

for arch in arm64 x86_64; do
  echo "编译 $arch"
  mkdir -p "build/$arch"
  swiftc -O -whole-module-optimization \
    -target "${arch}-apple-macos${MACOS_MIN}" \
    -module-name "$NAME" \
    -F "$SPARKLE_DIR" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${SOURCES[@]}" -o "build/$arch/$NAME"
done
lipo -create "build/arm64/$NAME" "build/x86_64/$NAME" -output "build/$NAME"
info=$(lipo -info "build/$NAME"); echo "$info"
[[ "$info" == *arm64* && "$info" == *x86_64* ]] || { echo "::error::universal 二进制缺架构"; exit 1; }

APP="build/${NAME}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "build/$NAME" "$APP/Contents/MacOS/$NAME"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>${NAME}</string>
  <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>${MACOS_MIN}</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>https://github.com/${GH_OWNER}/${GH_REPO}/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_ED_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

# ad-hoc 签名，不开 hardened runtime
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

STAGE="build/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/${NAME}.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/${NAME}-${VERSION}-mac-universal.dmg"

ditto -c -k --keepParent "$APP" "dist/${NAME}-${VERSION}-mac-universal.zip"
( cd dist && shasum -a 256 "${NAME}-${VERSION}-mac-universal.zip" > "${NAME}-${VERSION}-mac-universal.zip.sha256" )
ls -lh dist
