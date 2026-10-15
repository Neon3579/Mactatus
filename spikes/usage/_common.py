"""0단계 검증용 공통 도우미. 토큰·개인정보는 절대 출력하지 않는다."""
import base64
import json
import re
import urllib.error
import urllib.request

SENSITIVE = re.compile(r"(token|secret|email|account|user_id|project|^id$|_id$|sub$)", re.I)


def redact(value, key=""):
    """민감해 보이는 키의 값을 가린다(구조와 타입은 남긴다)."""
    if isinstance(value, dict):
        return {k: redact(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v, key) for v in value]
    if key and SENSITIVE.search(key) and isinstance(value, (str, int)):
        return f"<{type(value).__name__} 가림>"
    return value


def jwt_claims(token):
    """서명 검증 없이 JWT 본문만 읽는다(만료 시각 확인용)."""
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload))
    except Exception:
        return {}


def http_json(url, headers=None, body=None, method=None, timeout=45):
    """(상태 코드, JSON 또는 텍스트)를 돌려준다. 예외를 올리지 않는다."""
    data = None
    headers = dict(headers or {})
    if body is not None:
        if isinstance(body, (dict, list)):
            data = json.dumps(body).encode()
            headers.setdefault("Content-Type", "application/json")
        else:
            data = body.encode() if isinstance(body, str) else body
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode()
            status = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        status = e.code
    except Exception as e:  # 네트워크 오류 등
        return None, f"{type(e).__name__}: {e}"
    try:
        return status, json.loads(raw)
    except ValueError:
        return status, raw[:500]


def show(title, obj):
    print(f"\n== {title}")
    if isinstance(obj, (dict, list)):
        print(json.dumps(redact(obj), indent=2, ensure_ascii=False))
    else:
        print(obj)
