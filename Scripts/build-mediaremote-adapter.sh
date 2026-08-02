#!/bin/bash
# 构建 MediaRemoteAdapter.framework（ungive/mediaremote-adapter，MIT）
#
# 背景：macOS 15.4+ 上第三方 App 无法直接访问 MediaRemote 私有框架，
# 但系统二进制 /usr/bin/perl 具有访问权限。该 framework 由 perl 动态加载，
# 用于获取播放信息与控制媒体播放（boring.notch 同款方案，已验证 macOS 26）。
#
# 依赖：cmake（brew install cmake）
# 输出：Vendor/MediaRemoteAdapter.framework（gitignore，不提交二进制）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
BUILD="$ROOT/Vendor/build-mediaremote-adapter"
OUT="$ROOT/Vendor/MediaRemoteAdapter.framework"

if ! command -v cmake >/dev/null 2>&1; then
    echo "warning: cmake 未安装（brew install cmake）。媒体控制将降级为 AppleScript。"
    exit 0
fi

cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" >/dev/null

cmake --build "$BUILD" --config Release >/dev/null

SRC_FRAMEWORK="$BUILD/MediaRemoteAdapter.framework"
if [ ! -d "$SRC_FRAMEWORK" ]; then
    echo "error: MediaRemoteAdapter.framework 构建产物缺失"
    exit 1
fi

rm -rf "$OUT"
cp -R "$SRC_FRAMEWORK" "$OUT"
echo "✅ MediaRemoteAdapter.framework 已生成：$OUT"
