#!/bin/zsh
# 사용: ./run.sh <테스트> [추가 인자]
# 테스트: perm, axlist, items, notch, bt, media
cd "$(dirname "$0")"
T=$1
X=${2:-}
LOG="$PWD/build/out/$T.log"
rm -f "$LOG"
open -n -W build/SpikeLab.app --args "$PWD/build/libSpikeTests.dylib" "$T" "$LOG" "$X"
cat "$LOG"
