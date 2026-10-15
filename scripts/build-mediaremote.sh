#!/bin/zsh
# Vendor/mediaremote-adapter를 clang으로 빌드해 build/vendor/MediaRemoteAdapter.framework를 만든다(CMake 없이).
# 이 프레임워크는 앱에 링크하지 않고, /usr/bin/perl이 mediaremote-adapter.pl로 불러 쓴다(docs/spike-results.md 4번).
# scripts/build.sh가 부른다. 소스가 바뀌지 않았으면 다시 빌드하지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=Vendor/mediaremote-adapter
OUT=build/vendor/MediaRemoteAdapter.framework
BIN=$OUT/Versions/A/MediaRemoteAdapter

if [[ ! -d $SRC/src ]]; then
  echo "mediaremote-adapter 소스가 없음: $SRC" >&2
  exit 1
fi
if [[ -f $BIN && -z $(find $SRC/src $SRC/include -newer $BIN -print -quit) ]]; then
  exit 0
fi

# `test` 명령(adapter/test.m)은 따로 빌드하는 테스트 클라이언트가 있어야 해서 빼고 빌드한다
sources=("$SRC"/src/adapter/*.m "$SRC"/src/private/*.m "$SRC"/src/utility/*.m)
sources=(${sources:#*/adapter/test.m})
rm -rf "$OUT"
mkdir -p "$OUT/Versions/A/Resources"
clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -mmacosx-version-min=26.0 \
  -I "$SRC/include" -I "$SRC/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$BIN" $sources

cat > "$OUT/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.7.7</string>
  <key>CFBundleVersion</key><string>0.7.7</string>
</dict>
</plist>
PLIST
ln -sfn A "$OUT/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$OUT/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$OUT/Resources"
echo "mediaremote-adapter 빌드: $OUT"
