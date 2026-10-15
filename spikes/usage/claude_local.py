"""Claude Code 로컬 로그(JSONL)로 오늘 토큰 사용량 집계. 대화 내용은 읽지 않는다."""
import glob
import json
import os
import time
from collections import defaultdict
from datetime import datetime

HOME = os.path.expanduser("~")
ROOTS = [
    f"{HOME}/.claude/projects",
    f"{HOME}/.config/claude/projects",
    *glob.glob(f"{HOME}/Library/Application Support/Claude/claude-code-sessions/**/.claude/projects", recursive=True),
    *glob.glob(f"{HOME}/Library/Application Support/Claude/local-agent-mode-sessions/**/.claude/projects", recursive=True),
]
today = datetime.now().astimezone().date()
cutoff = time.time() - 2 * 86400

totals = defaultdict(lambda: defaultdict(int))
seen = set()
files_scanned = 0
for root in ROOTS:
    for path in glob.glob(f"{root}/**/*.jsonl", recursive=True):
        if os.path.getmtime(path) < cutoff:
            continue
        files_scanned += 1
        with open(path, errors="replace") as f:
            for line in f:
                if '"usage"' not in line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                msg = row.get("message") or {}
                usage = msg.get("usage")
                if row.get("type") != "assistant" or not usage:
                    continue
                ts = row.get("timestamp")
                if not ts or datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date() != today:
                    continue
                key = (msg.get("id"), row.get("requestId"))
                if key in seen:
                    continue
                seen.add(key)
                bucket = totals[msg.get("model", "?")]
                for field in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
                    bucket[field] += usage.get(field) or 0
                bucket["messages"] += 1

print("검색한 위치:", [r.replace(HOME, "~") for r in ROOTS if os.path.isdir(r)])
print("최근 2일 수정된 파일 수:", files_scanned)
for model, b in totals.items():
    print(f"{model}: {dict(b)}")
if not totals:
    print("오늘 기록 없음")
