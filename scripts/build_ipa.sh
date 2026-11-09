#!/usr/bin/env bash
# 构建 HXPhotoPickerExample 为 arm64 ad-hoc 签名 IPA
# 仅做构建：不改动源码；如需兼容新 Swift 编译器，用环境变量开关，不修改 .swift 文件。
set -euo pipefail

SCHEME="${SCHEME:-HXPhotoPickerExample}"
WORKSPACE="${WORKSPACE:-HXPhotoPickerExample.xcworkspace}"
CONFIG="${CONFIG:-Release}"
SDK="${SDK:-iphoneos}"
BUILD_DIR="${BUILD_DIR:-build}"
OUT_IPA="${OUT_IPA:-$PWD/HXPhotoPicker-adhoc.ipa}"

# 老工程是 Swift 5.0；新版 Xcode 默认 Swift 5 模式，这里显式锁定避免自动升级报错
SWIFT_VER="${SWIFT_VER:-5.0}"
# 若新编译器开启严格并发检查导致大面积报错，设为 minimal 或空串关闭
STRICT_CONCURRENCY="${STRICT_CONCURRENCY:-minimal}"
# 部署目标按示例工程原值
IOS_TARGET="${IOS_TARGET:-12.0}"

echo "==== toolchain ===="
xcodebuild -version
sw_vers

echo "==== pods ===="
if [ -f Podfile ]; then
  if [ ! -f "Pods/Manifest.lock" ] || [ "Podfile.lock" -nt "Pods/Manifest.lock" ]; then
    echo "Pods 与 Podfile.lock 不一致，重新 pod install"
    pod install
  else
    echo "Pods 已就绪（本地 podspec，无外部依赖）"
  fi
fi

echo "==== build ===="
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk "$SDK" \
  -arch arm64 \
  -derivedDataPath "$BUILD_DIR" \
  IPHONEOS_DEPLOYMENT_TARGET="$IOS_TARGET" \
  SWIFT_VERSION="$SWIFT_VER" \
  SWIFT_STRICT_CONCURRENCY="$STRICT_CONCURRENCY" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  clean build

APP="$(find "$BUILD_DIR/Build/Products" -maxdepth 3 -type d -name "*.app" | head -1)"
if [ -z "$APP" ]; then
  echo "构建失败：未找到 .app 产物"
  exit 1
fi
echo "APP=$APP"

echo "==== ad-hoc sign ===="
# 先签内嵌 framework / dylib，再签主二进制与 .app 外壳
while IFS= read -r fw; do
  fw_name="$(basename "$fw" .framework)"
  if [ -f "$fw/$fw_name" ]; then
    codesign --force --sign - --timestamp=none "$fw"
  fi
done < <(find "$APP" -maxdepth 3 -type d -name "*.framework")
while IFS= read -r lib; do
  codesign --force --sign - --timestamp=none "$lib"
done < <(find "$APP" -maxdepth 4 -type f \( -name "*.dylib" -o -name "*.so" \))
codesign --force --sign - --timestamp=none --deep "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | head -20 || true

echo "==== package ===="
rm -rf Payload "$OUT_IPA"
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry "$OUT_IPA" Payload
rm -rf Payload
ls -l "$OUT_IPA"

echo "==== summary ===="
shasum -a 256 "$OUT_IPA" | tee "$OUT_IPA.sha256"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$APP/Info.plist" || true
lipo -info "$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")" || true
