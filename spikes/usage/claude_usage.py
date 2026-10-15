"""Claude Code 사용량 검증: 키체인 토큰 → 비공식 OAuth 사용량 API.

토큰은 읽기만 하고 갱신하지 않는다(Claude Code가 refresh token을 교체하므로,
우리가 갱신하면 Claude Code 로그인이 풀릴 수 있다).
"""
import json
import subprocess
import time

from _common import http_json, show

r = subprocess.run(
    ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
    capture_output=True, text=True, timeout=20,
)
if r.returncode != 0:
    raise SystemExit(f"키체인 읽기 실패: {r.stderr.strip()}")
oauth = json.loads(r.stdout).get("claudeAiOauth")
if not oauth:
    raise SystemExit("claudeAiOauth 항목 없음")

minutes_left = (oauth["expiresAt"] / 1000 - time.time()) / 60
print(f"토큰 만료까지: {minutes_left:.0f}분 (음수면 만료됨)")
print("scopes에 user:profile 포함:", "user:profile" in oauth.get("scopes", []))

status, body = http_json(
    "https://api.anthropic.com/api/oauth/usage",
    headers={
        "Authorization": f"Bearer {oauth['accessToken']}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "mactatus-spike/0.1",
        "Accept": "application/json",
    },
)
show(f"GET /api/oauth/usage → HTTP {status}", body)
