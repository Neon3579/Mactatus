"""Gemini CLI 사용량 검증: oauth_creds.json → loadCodeAssist → retrieveUserQuota.

Google refresh token은 갱신해도 교체되지 않으므로, 만료됐으면 메모리에서만 갱신한다
(파일에는 쓰지 않음). 클라이언트 ID/시크릿은 설치된 Gemini CLI 패키지에서 읽는다.
"""
import json
import os
import re
import shutil
import subprocess
import time
import urllib.parse

from _common import http_json, show

GEMINI = os.path.expanduser("~/.gemini")
creds = json.load(open(f"{GEMINI}/oauth_creds.json"))
print("oauth_creds.json 키:", list(creds.keys()))
minutes_left = (creds.get("expiry_date", 0) / 1000 - time.time()) / 60
print(f"access_token 만료까지: {minutes_left:.0f}분")

settings = json.load(open(f"{GEMINI}/settings.json"))
auth_type = (settings.get("security", {}).get("auth", {}) or {}).get("selectedType") or settings.get("selectedAuthType")
print("인증 방식:", auth_type)


def cli_oauth_client():
    exe = shutil.which("gemini")
    if not exe:
        return None
    pkg_root = os.path.dirname(os.path.dirname(os.path.realpath(exe)))
    out = subprocess.run(
        ["grep", "-rlE", "OAUTH_CLIENT_SECRET", pkg_root, "--include=*.js"],
        capture_output=True, text=True,
    ).stdout.split()
    for path in out:
        text = open(path, errors="replace").read()
        cid = re.search(r"OAUTH_CLIENT_ID\s*=\s*['\"]([^'\"]+)", text)
        sec = re.search(r"OAUTH_CLIENT_SECRET\s*=\s*['\"]([^'\"]+)", text)
        if cid and sec:
            return cid.group(1), sec.group(1), path.replace(os.path.expanduser("~"), "~")
    return None


token = creds["access_token"]
if minutes_left <= 1:
    client = cli_oauth_client()
    print("CLI에서 OAuth 클라이언트 찾음:", client[2] if client else None)
    if not client or not creds.get("refresh_token"):
        raise SystemExit("갱신 불가")
    status, body = http_json(
        "https://oauth2.googleapis.com/token",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        body=urllib.parse.urlencode({
            "client_id": client[0], "client_secret": client[1],
            "refresh_token": creds["refresh_token"], "grant_type": "refresh_token",
        }),
    )
    print("메모리 갱신 결과: HTTP", status, "| 새 refresh_token 발급됨:", isinstance(body, dict) and "refresh_token" in body)
    if status != 200:
        show("갱신 실패 응답", body)
        raise SystemExit(1)
    token = body["access_token"]

headers = {"Authorization": f"Bearer {token}", "User-Agent": "mactatus-spike/0.1"}
base = "https://cloudcode-pa.googleapis.com/v1internal"
status, assist = http_json(f"{base}:loadCodeAssist", headers=headers,
                           body={"metadata": {"ideType": "GEMINI_CLI", "pluginType": "GEMINI"}})
show(f"loadCodeAssist → HTTP {status}", assist)

project = assist.get("cloudaicompanionProject") if isinstance(assist, dict) else None
if isinstance(project, dict):
    project = project.get("id")
status, quota = http_json(f"{base}:retrieveUserQuota", headers=headers,
                          body={"project": project} if project else {})
show(f"retrieveUserQuota → HTTP {status}", quota)
