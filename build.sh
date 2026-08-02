#!/bin/bash
# 发布打包脚本：archive → 签名 → 公证 → DMG → Sparkle appcast
#
# 使用前提（发布前配置）：
#   1. 在下方填入 Developer ID 证书名、Apple ID 与 Team ID
#   2. 在钥匙串中保存公证专用密码：xcrun notarytool store-credentials notary-password
#   3. 生成 Sparkle EdDSA 密钥：$(find DerivedData -name generate_keys -type f | head -1)
#      并将公钥填入 project.yml 的 SUPublicEDKey，appcast 用 sign_update 签名
#   4. 上传 DMG 到服务器，更新 appcast.xml（Sparkle 官方模板）
#
# 用法：./build.sh [版本号]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-0.1.0}"
BUILD_DIR="$ROOT/DerivedData/Release"

# ---- 发布配置（占位，发布时填写） ----
DEVELOPER_ID="Developer ID Application: YOUR_NAME (TEAMID)"
NOTARY_TEAM_ID="TEAMID"
NOTARY_APPLE_ID="your@apple.com"          # 或留空使用 keychain profile
NOTARY_PROFILE="notary-password"
APPCAST_URL="https://example.com/appcast.xml"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> 1/5 archive"
xcodebuild archive \
    -project "$ROOT/dao.xcodeproj" \
    -scheme dao \
    -configuration Release \
    -archivePath "$BUILD_DIR/dao.xcarchive" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    DEVELOPMENT_TEAM="$NOTARY_TEAM_ID"

APP_PATH="$BUILD_DIR/dao.xcarchive/Products/Applications/dao.app"

echo "==> 2/5 携带第三方许可证（BSD-3/MIT/Apache 分发要求）"
LIC_DIR="$APP_PATH/Contents/Resources/Licenses"
mkdir -p "$LIC_DIR"
cp "$ROOT/Vendor/mediaremote-adapter/LICENSE" "$LIC_DIR/mediaremote-adapter-BSD-3.txt"
for pkg in defaults keyboardshortcuts launchatlogin lottie-spm skylightwindow sparkle; do
    src="$ROOT/DerivedData/SourcePackages/checkouts/$pkg"
    lic=$(find "$src" -maxdepth 1 \( -iname "LICENSE*" -o -iname "LICENCE*" \) | head -1)
    [ -n "$lic" ] && cp "$lic" "$LIC_DIR/$pkg.txt"
done
echo "    -> 许可证已放入 app bundle"

echo "==> 3/5 验证签名"
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute "$APP_PATH"

echo "==> 4/5 制作 DMG"
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "dao" -srcfolder "$STAGE" \
    -ov -format UDZO "$BUILD_DIR/dao-$VERSION.dmg"

echo "==> 5/5 公证 + 盖章"
if [ -n "$NOTARY_APPLE_ID" ]; then
    xcrun notarytool submit "$BUILD_DIR/dao-$VERSION.dmg" \
        --apple-id "$NOTARY_APPLE_ID" \
        --team-id "$NOTARY_TEAM_ID" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
else
    xcrun notarytool submit "$BUILD_DIR/dao-$VERSION.dmg" \
        --keychain-profile "$NOTARY_PROFILE" --wait
fi
xcrun stapler staple "$BUILD_DIR/dao-$VERSION.dmg"

echo "==> 6/6 生成 appcast 签名（需 Sparkle 工具）"
SIGN_UPDATE="$(find "$ROOT/DerivedData" -name sign_update -type f 2>/dev/null | head -1)"
if [ -n "$SIGN_UPDATE" ] && [ -f "$SIGN_UPDATE" ]; then
    "$SIGN_UPDATE" "$BUILD_DIR/dao-$VERSION.dmg"
else
    echo "!! sign_update 未找到，请手动为 DMG 生成 appcast 签名"
fi

echo ""
echo "✅ 产物：$BUILD_DIR/dao-$VERSION.dmg"
echo "   将 DMG 上传服务器并更新 appcast.xml（URL: $APPCAST_URL）"
