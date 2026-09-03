#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR}"

ANDROID_HOME="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
BUILD_TOOLS_DIR=$(ls -d $ANDROID_HOME/build-tools/* | sort -V | tail -n 1)
ANDROID_JAR=$(ls $ANDROID_HOME/platforms/android-*/android.jar | sort -V | tail -n 1)

echo ">>> [1/5] 检查 Android SDK 工具..."
echo "  Build-tools: $BUILD_TOOLS_DIR"
echo "  android.jar: $ANDROID_JAR"

AAPT2="$BUILD_TOOLS_DIR/aapt2"
ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"
D8="$BUILD_TOOLS_DIR/d8"

echo ">>> [2/5] 同步网页与图像资源..."
mkdir -p "$SCRIPT_DIR/assets"
cp "$ROOT_DIR/index.html" "$SCRIPT_DIR/assets/"
cp "$ROOT_DIR/cabinet.html" "$SCRIPT_DIR/assets/"
if [ -f "$ROOT_DIR/images.js" ]; then
    cp "$ROOT_DIR/images.js" "$SCRIPT_DIR/assets/"
fi
if [ -d "$ROOT_DIR/images" ]; then
    cp -r "$ROOT_DIR/images" "$SCRIPT_DIR/assets/"
fi

BUILD_DIR="/tmp/fruit-slot-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo ">>> [3/5] aapt2 编译与链接资源..."
"$AAPT2" compile --dir "$SCRIPT_DIR/res" -o "$BUILD_DIR/compiled.zip"
"$AAPT2" link "$BUILD_DIR/compiled.zip" \
    -I "$ANDROID_JAR" \
    --manifest "$SCRIPT_DIR/AndroidManifest.xml" \
    -A "$SCRIPT_DIR/assets" \
    --java "$BUILD_DIR/gen" \
    -o "$BUILD_DIR/unaligned.apk" \
    --auto-add-overlay

echo ">>> [4/5] 编译 Java 代码与 D8 字节码打包..."
mkdir -p "$BUILD_DIR/classes"
find "$SCRIPT_DIR/java" "$BUILD_DIR/gen" -name "*.java" > "$BUILD_DIR/sources.txt"
javac -encoding UTF-8 -cp "$ANDROID_JAR" -d "$BUILD_DIR/classes" @"$BUILD_DIR/sources.txt"

find "$BUILD_DIR/classes" -name "*.class" > "$BUILD_DIR/classes.txt"
"$D8" --output "$BUILD_DIR" --lib "$ANDROID_JAR" $(cat "$BUILD_DIR/classes.txt")

# 将 classes.dex 写入 apk
python3 -c "import zipfile; z = zipfile.ZipFile('$BUILD_DIR/unaligned.apk', 'a'); z.write('$BUILD_DIR/classes.dex', 'classes.dex'); z.close()"

echo ">>> [5/5] 对齐 (zipalign) 与自签名 (apksigner)..."
"$ZIPALIGN" -f -p 4 "$BUILD_DIR/unaligned.apk" "$BUILD_DIR/aligned.apk"

# 生成/复用签名密钥
KEYSTORE="$ROOT_DIR/fruit-release.jks"
if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair -v -keystore "$KEYSTORE" -alias fruit -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass fruit2026 -keypass fruit2026 -dname "CN=Fruit, OU=Game, O=Arcade, L=BJ, ST=BJ, C=CN"
fi

APK_NAME="水果大满贯.apk"
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:fruit2026 --ks-key-alias fruit --key-pass pass:fruit2026 \
    --out "$OUTPUT_DIR/$APK_NAME" "$BUILD_DIR/aligned.apk"

rm -rf "$BUILD_DIR"

echo "========================================================"
echo "  [SUCCESS] APK 构建成功！"
echo "  输出文件: $OUTPUT_DIR/$APK_NAME"
echo "========================================================"
