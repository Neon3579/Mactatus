# 0단계 검증 결과

> 확인 날짜 2026-10-15 · macOS 27.0.1 (26A434) · MacBook Air M2 · Xcode 26.6 / Swift 6.3
> 검증 코드: `spikes/usage/`(사용량), `spikes/probe/`(권한 없이 확인), `spikes/SpikeLab/`(권한이 필요한 검증용 앱)

## 한눈에 보기

| # | 항목 | 판정 | 요약 |
|---|---|---|---|
| 1 | Claude 사용량 API | **가능(우회 필요)** | API는 정상. 단 키체인 토큰이 자주 만료돼 있음 → `claude`를 가상 터미널로 띄워 `/usage`를 읽으면 토큰도 갱신됨 |
| 2 | Codex 사용량 | **가능** | 실시간 API(`wham/usage`)와 `codex app-server` 모두 정상. 요금제마다 한도 창 구성이 다름 |
| 3 | Gemini CLI 할당량 | **불가능** | 개인용 Gemini Code Assist 지원 종료. 대신 **Antigravity** 할당량은 읽을 수 있음 |
| 4 | mediaremote-adapter | **가능** | macOS 27에서 재생 정보 읽기·재생 제어 정상. 직접 호출은 막혀 있음 |
| 5 | 노치 패널(전체 화면 포함) | **가능(우회 필요)** | 전체 화면 전환 때 시스템이 패널을 아래로 옮김 → 위치를 다시 잡으면 정상 |
| 6 | 블루투스 기기 배터리 | **가능** | 연결 알림 등록·배터리(왼쪽·오른쪽·케이스) 읽기 정상. 연결이 끊기는 순간 알림은 미확인 |
| 7 | 메뉴바 아이콘 목록·캡처 | **가능(방식 변경)** | 창 목록 방식은 macOS 27에서 불가 → 손쉬운 사용 API로 목록·누르기 가능 |
| 8 | ⌘ 끌기로 아이콘 이동 | **미검증** | 사용자 요청으로 실제 아이콘 이동 테스트는 제외. 테스트용 아이콘은 자리가 없어 의미 있는 결과 없음 |
| 9 | 메뉴바 밖에 놓기 | **미검증** | 8번과 같은 이유 |
| 10 | 편집 모드용 덮개 창 | **가능** | 메뉴바 위에 보이고 클릭·끌기를 가로챔 |

---

## 1. Claude 사용량 — 가능(우회 필요)

**실시간 API**
- `GET https://api.anthropic.com/api/oauth/usage`
  - 헤더: `Authorization: Bearer <키체인 토큰>`, `anthropic-beta: oauth-2025-04-20`
  - 토큰: 키체인 `Claude Code-credentials` → `claudeAiOauth.accessToken`(`/usr/bin/security`로 읽으면 확인 창 없음)
- 응답(HTTP 200)에서 쓸 값
  - `five_hour.utilization`·`resets_at`(5시간 세션), `seven_day.utilization`·`resets_at`(주간)
  - `limits[]`: `kind`, `group`, `percent`, `severity`, `resets_at` — 화면에 그대로 쓰기 좋은 정리본
  - `seven_day_breakdown.rows[]`: 주간 사용 비중(이번 확인: Claude Code 79%, Cowork 21%)
  - `extra_usage`, `spend`: 추가 크레딧 정보
- 필드 이름이 자주 바뀌는 흔적이 있음(`iguana_necktie`, `cedar_ember` 같은 코드명 필드 다수) → 모르는 필드는 무시하고, `limits[]` → `five_hour`/`seven_day` 순서로 읽는다

**토큰 만료 문제**
- 이 맥에서는 Claude를 데스크톱 앱으로만 써서 CLI 토큰이 **5.6일째 만료** 상태였음 → API는 401
- `claude auth status`로는 갱신되지 않음
- **해결:** `claude`를 가상 터미널(PTY)에서 띄워 `/usage`를 보내면 모델 요청 없이(사용량 소모 없음) 토큰이 갱신되고(만료 −8104분 → +479분), 화면에서 세션 %도 읽을 수 있음
  - 실행 옵션: `--allowed-tools "" --strict-mcp-config --settings '{"disableAllHooks":true}'`
- **우리 앱은 토큰을 직접 갱신하지 않는다.** Claude Code가 refresh token을 교체하므로 우리가 갱신하면 Claude Code 로그인이 풀릴 수 있음

**로컬 로그(오늘 토큰)**
- `~/.claude/projects/**/*.jsonl` + 데스크톱 앱 세션 `~/Library/Application Support/Claude/local-agent-mode-sessions/**/.claude/projects/**/*.jsonl`
- `type == "assistant"` 줄의 `message.usage`를 `message.id`+`requestId`로 중복 제거해 합산 → 정상 동작

## 2. Codex 사용량 — 가능

- **실시간 API:** `GET https://chatgpt.com/backend-api/wham/usage`
  - 헤더: `Authorization: Bearer <access_token>`, `ChatGPT-Account-Id: <account_id>` (`~/.codex/auth.json`의 `tokens`)
  - 응답: `plan_type`, `rate_limit.primary_window`/`secondary_window`(`used_percent`, `limit_window_seconds`, `reset_at`), `credits`, `rate_limit_reset_credits`
- **CLI 경로:** `codex -s read-only -a never app-server` → JSON-RPC 한 줄씩
  - `initialize` → `account/rateLimits/read`: `rateLimits.primary`(`usedPercent`, `windowDurationMins`, `resetsAt`), `planType`, 무료 리셋 쿠폰 목록
  - `account/read`는 `params`가 필요함(`{}`)
- **요금제마다 창 구성이 다름**
  - 지금(free): 30일 창 1개(`secondary`는 null)
  - 10/2 세션 로그(plus 시절): 5시간 창 + 주간 창
  - → 화면은 창 개수·길이를 고정하지 말고 받은 대로 그린다
- **주의**
  - npm으로 설치된 전역 `codex`는 설치가 깨져 실행 안 됨(`@openai/codex-darwin-arm64` 누락). ChatGPT 앱 안의 `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`는 정상
  - 세션 로그(`~/.codex/sessions`)는 마지막 기록이 10/2라 오래됨 → 보조 정보로만 사용
  - 토큰은 직접 갱신하지 않는다(만료까지 약 205시간 남음, 만료되면 Codex에 맡김)

## 3. Gemini — Gemini CLI는 불가능, Antigravity는 가능

**Gemini CLI(`cloudcode-pa.googleapis.com`)**
- 토큰은 메모리에서만 갱신해 호출 성공(Google refresh token은 교체되지 않음)
- `loadCodeAssist`: 무료 등급이 `UNSUPPORTED_CLIENT` — "개인용 Gemini Code Assist 지원이 종료됐으니 Antigravity로 옮기라"는 안내
- `retrieveUserQuota`: 403 `SUBSCRIPTION_REQUIRED`
- → 이 계정으로는 Gemini CLI 할당량을 보여줄 수 없음

**Antigravity(대안)**
- Antigravity 앱이 켜져 있으면 로컬 `language_server`에 물어볼 수 있음
  - 프로세스 인자에서 `--csrf_token` 확인, `lsof`로 대기 포트 확인
  - `POST http(s)://127.0.0.1:<포트>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` (헤더 `X-Codeium-Csrf-Token`, `Connect-Protocol-Version: 1`)
- 응답: 모델 그룹별 5시간·주간 잔여 비율과 리셋 시각
  - "Gemini Models"(Gemini Flash·Pro): `gemini-5h`, `gemini-weekly`
  - "Claude and GPT models": `3p-5h`, `3p-weekly`
- `GetUserStatus`에는 모델별 잔여 비율과 요금제(Pro)도 있음
- 앱이 꺼져 있을 때 쓸 클라우드 경로는 미검증

## 4. 음악 제어 — 가능

- MediaRemote를 직접 부르면 빈 결과(재생 중인데도 `IsPlaying=false`) → macOS 15.4 이후 제한이 27에서도 유지됨
- **mediaremote-adapter**(BSD-3)
  - cmake 없이 clang으로 직접 빌드 가능(`src/adapter/*.m`, `src/private/MediaRemote.m`, `src/utility/*.m` → 프레임워크)
  - `test` 통과, `get`으로 Apple Music 재생 정보(제목·아티스트·앨범·길이·경과 시간·앱 번들 ID) 확인
  - `send 2`(재생/일시정지 전환) 정상
  - 앨범 아트는 이번엔 비어 있었음 → 1단계 이후 `stream`으로 재확인

## 5. 노치 패널 — 가능(우회 필요)

- 노치 위치: x 645.5, 폭 179, 높이 32pt / 메뉴바 높이 33pt(`auxiliaryTopLeftArea`·`auxiliaryTopRightArea`로 계산)
- 창 설정: `NSPanel`(테두리 없음, 비활성) + 레벨 `mainMenu + 3` + `canJoinAllSpaces`·`stationary`·`fullScreenAuxiliary`·`ignoresCycle`
- 데스크톱: 정상 표시
- **전체 화면:** 전환 순간 시스템이 패널을 화면 아래쪽(y 92)으로 옮김. `constrainFrameRect`를 무시하는 것만으로는 부족 → **Space가 바뀔 때마다 프레임을 다시 위로 설정**하면 전체 화면 위에서도 정상 표시
- 전체 화면에서 마우스 올림 → 펼침/접힘 정상

## 6. 블루투스 — 가능

- 블루투스 권한 필요. **허용 창이 떠 있는 동안 `pairedDevices()` 호출이 멈춤** → 앱에서는 메인 스레드 밖에서 처음 호출할 것
- `IOBluetoothDevice.register(forConnectNotifications:)`: 등록 즉시 이미 연결된 기기(AirPods Pro)를 알려 줌
- 비공개 배터리 속성: `batteryPercentLeft`·`Right`·`Case`가 읽힘(100/100/100 → 테스트 중 왼쪽 0으로 바뀜)
- 1분 동안 연결이 끊기거나 새로 연결되는 일은 기록되지 않아 그 순간의 알림은 미확인 → 5단계에서 확인
- `system_profiler SPBluetoothDataType -json`은 연결이 끊긴 기기의 마지막 배터리 값도 보여줌(보조 수단)

## 7. 메뉴바 아이콘 목록·캡처 — 가능(방식 변경)

**macOS 27에서 바뀐 점**
- 상태 아이템이 더 이상 앱별 창이 아님. `MenuBarAgent`(/System/Library/CoreServices)가 장면(scene) 단위로 그림
  - `CGWindowList`의 layer 25에 다른 앱 아이콘이 나오지 않음, 우리 앱 아이템 창도 목록에 없음
  - → Ice 같은 기존 "창 목록" 방식은 쓸 수 없음
- 자리가 모자라면 아이콘을 숨겨 두는 **기본 « 버튼("가려진 메뉴 막대 항목 보기")**이 있음
  - 이번 확인 때 LM Studio·Antigravity·Notion이 숨겨져 있었고, 테스트용 아이콘 ①②③도 바로 여기로 들어감
  - « 버튼 자체는 AXPress를 지원하지 않음(AXError −25206)

**손쉬운 사용 API로 가능한 것**
- 앱마다 `AXExtrasMenuBar`의 자식 → 모든 메뉴바 아이콘의 앱·위치·크기·`AXPress`(16개 확인)
  - 시스템 아이콘(Wi-Fi·Bluetooth·배터리·제어 센터·시계)은 `MenuBarAgent` 소유
  - 숨겨진 아이콘은 « 근처에 겹친 위치로 나옴 → 숨김 여부 구분 가능
- **숨겨진 아이콘도 옮기지 않고 `AXPress`로 바로 실행됨**(숨겨진 Notion 아이콘 → Notion 검색 창 열림)
- 화면 기록 권한으로 메뉴바 영역을 캡처해 잘라내면 보이는 아이콘의 이미지를 얻을 수 있음. 숨겨진 아이콘은 화면에 그려지지 않으므로 보일 때 캐시해 두거나 앱 아이콘으로 대신해야 함

**주의**
- 우리 앱 자신의 상태 아이템에 다른 스레드에서 AX를 호출하면 크래시(앱 내부에서 처리됨) → 우리 아이템은 AX를 쓰지 말고 직접 다룬다

## 8·9. ⌘ 끌기 이동, 메뉴바 밖에 놓기 — 미검증

- 실제 아이콘을 옮기는 테스트는 사용자 요청으로 제외함
- 테스트용 아이콘(①②③)은 메뉴바에 자리가 없어 « 안으로 들어갔기 때문에, ⌘ 끌기·구분자로 숨기기 결과가 의미 없었음
- 3단계 시작 때 메뉴바에 자리를 만든 상태(예: 메뉴바 앱 몇 개를 잠시 종료)로 다시 검증해야 함

## 10. 편집 모드용 덮개 창 — 가능

- 메뉴바 위에 반투명 창을 레벨 `statusBar + 1`(26)부터 `screenSaver`(1000)까지 띄워 캡처 → 모든 레벨에서 메뉴바 위에 보임(픽셀 색 비교로 확인)
- 덮개 창이 클릭·⌘ 끌기를 모두 받아서(mouseDown·mouseUp, drag 15개), 아래 아이콘은 움직이지 않음

---

## 계획에 반영할 것

1. **AI 사용량:** Claude는 토큰 만료 시 PTY `/usage`로 갱신·읽기. Codex는 `wham/usage` 우선, 창 구성은 요금제대로. **Gemini는 Antigravity로 대체할지 결정 필요**
2. **메뉴바 서랍:** 목록·실행은 손쉬운 사용 API(이동 불필요). macOS 27 기본 « 버튼과 우리 서랍의 관계(대체·함께 쓰기)를 다시 설계해야 함. 아이콘 이동(⌘ 끌기)은 3단계 시작 때 재검증
3. **노치:** Space 변경 알림마다 패널 위치 재설정
4. **블루투스:** 첫 호출은 메인 스레드 밖에서
