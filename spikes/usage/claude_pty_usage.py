"""Claude Code 대체 경로 검증: 가상 터미널(PTY)에서 claude를 띄우고 /usage 화면을 읽는다.

모델 요청을 보내지 않으므로 사용량을 쓰지 않는다. 부수 효과로 키체인 토큰이 갱신되는지도 확인한다.
"""
import json
import os
import pty
import re
import select
import subprocess
import time

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[=>()][0-9A-Za-z]?")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def token_minutes_left():
    raw = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                         capture_output=True, text=True).stdout
    return round((json.loads(raw)["claudeAiOauth"]["expiresAt"] / 1000 - time.time()) / 60)


print("시작 전 토큰 만료까지(분):", token_minutes_left())

pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM="xterm-256color", COLUMNS="120", LINES="40")
    os.execvp("claude", ["claude", "--allowed-tools", "", "--strict-mcp-config",
                         "--settings", '{"disableAllHooks":true}'])

buf = ""


def pump(seconds):
    global buf
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.3)
        if r:
            try:
                buf += os.read(fd, 65536).decode(errors="replace")
            except OSError:
                return


try:
    pump(8)                       # 시작 화면
    os.write(fd, b"/usage")
    pump(1)
    os.write(fd, b"\r")
    deadline = time.time() + 25
    while time.time() < deadline and "Current week" not in ANSI.sub("", buf):
        pump(1)
    pump(2)
    screen = ANSI.sub("", buf)
    start = screen.rfind("Current session")
    print("\n== /usage 화면에서 읽은 줄")
    for line in screen[start:].splitlines() if start >= 0 else screen.splitlines()[-40:]:
        line = EMAIL.sub("<email 가림>", line).strip()
        if line:
            print(" ", line[:110])
finally:
    for keys in (b"\x1b", b"/exit\r"):
        try:
            os.write(fd, keys)
        except OSError:
            pass
        time.sleep(1)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass

print("\n종료 후 토큰 만료까지(분):", token_minutes_left())
