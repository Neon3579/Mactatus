#!/bin/zsh
# Mactatus.app을 빌드해서 build/Mactatus.app으로 묶고 서명한다.
# 사용: scripts/build.sh [debug|release]   (기본 debug)
#
# 서명: 키체인에 "Apple Development" 인증서가 있으면 그것으로 서명한다.
# 없으면 임시 서명(ad-hoc)으로 대신하는데, 이 경우 빌드할 때마다
# 손쉬운 사용·화면 기록 권한이 풀린다(3단계부터 문제). Xcode → 설정 → 계정에서
# Apple ID를 추가하면 인증서가 생긴다.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-debug}
swift build -c "$CONFIG" --product Mactatus
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)

APP=build/Mactatus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/Mactatus" "$APP/Contents/MacOS/Mactatus"
# SwiftPM 리소스 묶음(있을 때만)
for bundle in "$BIN_DIR"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "서명: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "서명: 임시(ad-hoc) — Apple Development 인증서가 없음"
fi
echo "빌드 완료: $APP"
