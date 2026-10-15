#!/bin/zsh
# Mactatus.app을 빌드해서 build/Mactatus.app으로 묶고 서명한다.
# 사용: scripts/build.sh [debug|release]   (기본 debug)
#
# 서명: 유효한 "Apple Development" 인증서, 없으면 이 맥에서 만든 자체 서명 인증서
# "Mactatus 개발 서명"(키체인 접근 → 인증서 지원 → 인증서 생성, 유형: 코드 서명)을 쓴다.
# 둘 다 없으면 임시 서명(ad-hoc)인데, 빌드할 때마다 서명값이 바뀌어
# 손쉬운 사용 권한이 맞지 않게 된다(macOS 27에서 확인).
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

# 서명 인증서 고르기: 환경 변수 → 유효한 Apple Development → 자체 서명 "Mactatus 개발 서명"
IDENTITY=${MACTATUS_SIGN_IDENTITY:-}
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
fi
if [[ -z "$IDENTITY" ]]; then
  # 한글 이름으로는 codesign이 인증서를 못 찾아("unknown exception") 지문(SHA-1)으로 지정한다
  IDENTITY=$(security find-identity -p codesigning | awk '/"Mactatus 개발 서명"/ { print $2; exit }')
fi
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "서명: $(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/ { print $2; exit }')"
else
  codesign --force --sign - "$APP"
  echo "서명: 임시(ad-hoc) — Apple Development 인증서가 없음"
fi
echo "빌드 완료: $APP"
