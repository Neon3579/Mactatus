#!/bin/zsh
# 빌드 후 실행 중인 Mactatus를 끄고 새로 띄운다.
# 사용: scripts/run.sh [release|debug]   (기본 release — 실제로 쓸 때는 최적화 빌드)
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh "${1:-release}"
pkill -x Mactatus 2>/dev/null && sleep 0.5 || true
open build/Mactatus.app
echo "실행: build/Mactatus.app"
