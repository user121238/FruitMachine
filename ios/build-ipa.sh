#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR}"

echo ">>> [1/4] 检测编译工具链与 SDK..."
SDK_PATH=$(xcrun -sdk iphoneos --show-sdk-path)
if [ -z "$SDK_PATH" ]; then
    echo "Error: 未找到 iPhoneOS SDK"
    exit 1
fi
echo "  [OK] iPhoneOS SDK: $SDK_PATH"

echo ">>> [2/4] 编译 ARM64 Mach-O 原生二进制 (FruitSlot)..."
xcrun -sdk iphoneos swiftc \
    -parse-as-library \
    -target arm64-apple-ios14.0 \
    -sdk "$SDK_PATH" \
    -framework UIKit -framework WebKit -framework Foundation \
    -O -o "$SCRIPT_DIR/FruitSlot" "$SCRIPT_DIR/App.swift"
echo "  [OK] 编译成功"

echo ">>> [3/4] 构建 Payload/FruitSlot.app 目录结构并同步资源..."
rm -rf "$SCRIPT_DIR/Payload"
mkdir -p "$SCRIPT_DIR/Payload/FruitSlot.app"

cp "$SCRIPT_DIR/FruitSlot" "$SCRIPT_DIR/Payload/FruitSlot.app/"
cp "$SCRIPT_DIR/Info.plist" "$SCRIPT_DIR/Payload/FruitSlot.app/"
cp "$ROOT_DIR/cabinet.html" "$SCRIPT_DIR/Payload/FruitSlot.app/"
cp "$ROOT_DIR/index.html" "$SCRIPT_DIR/Payload/FruitSlot.app/"
if [ -f "$ROOT_DIR/images.js" ]; then
    cp "$ROOT_DIR/images.js" "$SCRIPT_DIR/Payload/FruitSlot.app/"
fi
if [ -d "$ROOT_DIR/images" ]; then
    cp -r "$ROOT_DIR/images" "$SCRIPT_DIR/Payload/FruitSlot.app/"
fi

# 巨魔/自签 Ad-hoc 签名
codesign -s - --force --deep "$SCRIPT_DIR/Payload/FruitSlot.app"

echo ">>> [4/4] 封装 FruitSlot.ipa..."
cd "$SCRIPT_DIR"
IPA_NAME="水果大满贯.ipa"
zip -r9 "$OUTPUT_DIR/$IPA_NAME" Payload
rm -rf "$SCRIPT_DIR/Payload" "$SCRIPT_DIR/FruitSlot"

echo "========================================================"
echo "  [SUCCESS] IPA 构建成功！"
echo "  输出文件: $OUTPUT_DIR/$IPA_NAME"
echo "========================================================"
