#!/bin/bash
# 古籍镜 · 一键编译 + 打包（.app 与 .dmg）
#
# 用法：bash build.sh [输出目录]     默认输出到桌面

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HOME/Desktop}"
FINAL_APP="${OUT_DIR}/古籍镜.app"
FINAL_DMG="${OUT_DIR}/古籍镜-1.0.dmg"
EXEC_NAME="GuJiJing"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

# 组装、签名、打包全在临时目录里做，最后才把成品拷到桌面。
# 桌面在 iCloud 文件提供程序纳管下（目录上带着 com.apple.fileprovider.fpfs#P），
# Finder 会不停给 .app 塞 com.apple.FinderInfo，codesign 会当场拒绝：
#   "resource fork, Finder information, or similar detritus not allowed"
# 在 /tmp 里签完名再拷回去 —— 事后再多出什么扩展属性也不影响已生效的签名。
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="${WORK}/古籍镜.app"
DMG="${WORK}/古籍镜-1.0.dmg"
BUILD_DIR="${WORK}/build"
mkdir -p "$BUILD_DIR"

echo "==> 1/4 编译"
swiftc -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK" \
  -framework AppKit \
  -o "${BUILD_DIR}/${EXEC_NAME}" \
  "${SRC_DIR}/Core.swift" "${SRC_DIR}/App.swift" \
  "${SRC_DIR}/Views.swift" "${SRC_DIR}/Translate.swift" \
  "${SRC_DIR}/main.swift"

echo "==> 2/4 组装 古籍镜.app"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BUILD_DIR}/${EXEC_NAME}" "${APP}/Contents/MacOS/${EXEC_NAME}"
cp "${SRC_DIR}/Info.plist" "${APP}/Contents/Info.plist"
# 韵书数据必须打进 Resources，否则「韵典」标签页是空的
cp "${SRC_DIR}/rhymebooks.json" "${APP}/Contents/Resources/rhymebooks.json"
# 本地对照语料（离线译文）也必须打进去：corpus/ 里每本书一个 json，
# 再加 _common.json 兜底，否则「译」按钮只能联网查。
if [ -d "${SRC_DIR}/corpus" ]; then
  cp -R "${SRC_DIR}/corpus" "${APP}/Contents/Resources/corpus"
fi
if [ -f "${SRC_DIR}/古籍镜.icns" ]; then
  cp "${SRC_DIR}/古籍镜.icns" "${APP}/Contents/Resources/古籍镜.icns"
fi

echo "==> 3/4 ad-hoc 签名"
xattr -cr "$APP"
if ! codesign --force --deep --sign - "$APP" 2>"${WORK}/codesign.err"; then
  echo "⚠️ ad-hoc 签名没成功（本机照样能跑，分发时对方要右键「打开」）："
  head -3 "${WORK}/codesign.err"
fi

echo "==> 4/4 打包 古籍镜-1.0.dmg"
STAGE="${WORK}/stage"
mkdir -p "$STAGE"
cp -R "$APP" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
# ULMO = lzma：比默认的 UDZO(zlib) 小 25 MB 上下（88 MB → 64 MB）。
# 代价是打包慢几分钟，且要 macOS 10.15+ 才能挂载。
hdiutil create -volname "古籍镜" -srcfolder "$STAGE" -ov -format ULMO "$DMG" > /dev/null

echo "==> 拷到 ${OUT_DIR}"
rm -rf "$FINAL_APP"
cp -R "$APP" "$FINAL_APP"
cp "$DMG" "$FINAL_DMG"

echo
echo "完成："
echo "  $FINAL_APP"
echo "  $FINAL_DMG"
