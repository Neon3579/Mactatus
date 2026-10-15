"""Codex 사용량 검증: ① 실시간 API(wham/usage) ② codex app-server RPC ③ 세션 로그의 rate_limits.

토큰은 읽기만 하고 갱신하지 않는다(OpenAI refresh token은 교체되므로 갱신은 Codex에 맡긴다).
"""
import glob
import json
import os
import select
import shutil
import subprocess
import time

from _common import http_json, jwt_claims, show

CODEX = os.path.expanduser(os.environ.get("CODEX_HOME", "~/.codex"))

# --- auth.json 상태 ---
auth = json.load(open(f"{CODEX}/auth.json"))
tokens = auth.get("tokens") or {}
print("auth.json 키:", list(auth.keys()), "| tokens 키:", list(tokens.keys()))
exp = jwt_claims(tokens.get("access_token", "")).get("exp")
hours_left = (exp - time.time()) / 3600 if exp else None
print("access_token 만료까지(시간):", None if hours_left is None else round(hours_left, 1))
print("last_refresh:", auth.get("last_refresh"))

# --- ① 실시간 API ---
if hours_left and hours_left > 0:
    status, body = http_json(
        "https://chatgpt.com/backend-api/wham/usage",
        headers={
            "Authorization": f"Bearer {tokens['access_token']}",
            "ChatGPT-Account-Id": tokens.get("account_id", ""),
            "User-Agent": "mactatus-spike/0.1",
        },
    )
    show(f"① GET wham/usage → HTTP {status}", body)
else:
    print("\n== ① 토큰 만료로 실시간 API 건너뜀")

# --- ② codex app-server JSON-RPC ---
CANDIDATES = [
    os.environ.get("CODEX_BIN"),
    "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",  # ChatGPT 앱에 들어 있는 CLI
    shutil.which("codex"),
]
codex_bin = next(p for p in CANDIDATES if p and os.access(p, os.X_OK))
print("\ncodex 실행 파일:", codex_bin)
proc = subprocess.Popen(
    [codex_bin, "-s", "read-only", "-a", "never", "app-server"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)


def send(msg):
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()


def wait_for(msg_id, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], 0.5)
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            break
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("id") == msg_id:
            return msg
    return {"timeout": True}


try:
    send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "mactatus-spike", "version": "0.1.0"}}})
    show("② initialize", wait_for(1))
    send({"method": "initialized"})
    send({"id": 2, "method": "account/rateLimits/read"})
    show("② account/rateLimits/read", wait_for(2))
    send({"id": 3, "method": "account/read"})
    show("② account/read", wait_for(3))
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()

# --- ③ 가장 최근 세션 로그의 rate_limits ---
files = sorted(glob.glob(f"{CODEX}/sessions/**/rollout-*.jsonl", recursive=True), key=os.path.getmtime)
last = None
for path in reversed(files[-5:]):
    with open(path, errors="replace") as f:
        for line in f:
            if '"token_count"' not in line or '"rate_limits"' not in line:
                continue
            row = json.loads(line)
            payload = row.get("payload") or {}
            if payload.get("type") == "token_count" and payload.get("rate_limits"):
                last = (row.get("timestamp"), payload["rate_limits"])
    if last:
        break
if last:
    show(f"③ 세션 로그 rate_limits (기록 시각 {last[0]})", last[1])
else:
    print("\n== ③ 세션 로그에서 rate_limits 못 찾음")
