#!/bin/zsh
# 호스트 앱은 처음 한 번만 빌드한다(다시 빌드하면 서명이 바뀌어 권한을 다시 줘야 함).
# 테스트 dylib는 매번 다시 빌드해도 된다. 호스트를 강제로 다시 빌드하려면 --host.
set -e
cd "$(dirname "$0")"
APP=build/SpikeLab.app
mkdir -p "$APP/Contents/MacOS" build/out

if [[ ! -f "$APP/Contents/MacOS/SpikeLab" || "$1" == "--host" ]]; then
  cp Info.plist "$APP/Contents/Info.plist"
  swiftc -swift-version 5 -target arm64-apple-macos26.0 -O Host/main.swift -o "$APP/Contents/MacOS/SpikeLab"
  codesign --force --sign - --identifier com.mactatus.spikelab "$APP"
  echo "호스트 앱 빌드함 — 권한은 이 앱(SpikeLab)에 부여"
fi

swiftc -swift-version 5 -target arm64-apple-macos26.0 -emit-library -module-name SpikeTests Tests/*.swift \
  -o build/libSpikeTests.dylib \
  -framework AppKit -framework ScreenCaptureKit -framework IOBluetooth -framework ApplicationServices
codesign --force --sign - build/libSpikeTests.dylib
echo "테스트 라이브러리 빌드 완료"
