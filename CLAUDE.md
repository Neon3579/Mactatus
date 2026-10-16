# Mactatus

개인용 macOS 메뉴바·노치 허브 앱. 전체 계획과 확정된 결정은 [PLAN.md](PLAN.md)에 있다. 작업을 시작하기 전에 해당 단계 부분과 [docs/spike-results.md](docs/spike-results.md)(0단계 검증 결과, 만들어진 뒤)를 먼저 읽을 것.

## 구성

| 영역 | 위치 | 패키지 |
|---|---|---|
| ① AI 사용량(Claude Code·Codex·Gemini, 안 되면 Antigravity) | 메뉴바 아이콘 + 팝오버 | `UsageKit` |
| ② 시스템 리소스 | 메뉴바 아이콘 + 팝오버(①과 별도 아이콘) | `MetricsKit` |
| ③ 메뉴바 서랍(Windows 숨겨진 아이콘 방식. 숨기기는 macOS "메뉴 막대에서 허용", 서랍에서 눌러 열기) | 메뉴바 ⌄ + 서랍 패널 | `DrawerKit` |
| ④ 노치 허브(음악·블루투스·다운로드·파일 트레이·상태 팝업·스크린샷·클립보드) | 내장 디스플레이 노치 | `NotchKit`, `Modules` |

폴더 구조는 PLAN.md 5장을 따른다. Xcode 프로젝트 대신 루트의 `Package.swift` 하나로 빌드한다(Xcode에서 열 수 있음).

## 환경

- 대상: **macOS 26 이상만**(deployment target 26.0). 이전 버전용 분기·대체 디자인을 만들지 않는다
- 개발 맥: MacBook Air M2(노치 있음), macOS 27, Xcode 26.6, Swift 6.3
- 개인용 앱: App Store·공증·자동 업데이트 없음

## 빌드·테스트

- `swift build` — 컴파일만 확인
- `swift test` — 파서 테스트(`Packages/UsageKit/Tests`)
- `scripts/build.sh [debug|release]` — `build/Mactatus.app`으로 묶고 서명(Apple Development 인증서가 없으면 임시 서명)
- `scripts/run.sh` — release로 빌드한 뒤 실행 중인 앱을 끄고 새로 띄움(`scripts/run.sh debug`로 디버그 빌드)
- `build/Mactatus.app/Contents/MacOS/Mactatus --snapshot <폴더>` — 한 번 조회한 뒤 AI 사용량·시스템 팝오버, 메뉴바 라벨, 서랍, 노치(미니·펼침·빈 상태)를 라이트·다크 PNG로 저장하고 종료. 메뉴바·노치를 열지 않고 화면을 확인할 때 쓴다
- `scripts/build-mediaremote.sh` — `Vendor/mediaremote-adapter`를 clang으로 빌드(`scripts/build.sh`가 부름). 소스가 없으면 음악 모듈이 "읽을 수 없음"으로 뜬다
- `build/Mactatus.app/Contents/MacOS/Mactatus --metrics-detail` — 팝오버가 열린 것처럼 1초마다 전부 측정. 성능 확인용: 12초 뒤부터 60초 동안 `ps -o time= -p <pid>` 차이로 CPU 사용률을 잰다(목표 1% 미만)
- 성능 문제를 찾을 때는 `sample <pid> 20 -file <파일>`로 프로파일을 떠서 무거운 함수를 확인한다
- `UsageKit`의 파서는 단위 테스트 필수. 실제 응답·로그에서 만든 샘플을 테스트 데이터로 쓰되, 토큰·이메일 등 개인 정보는 지운다
- UI를 바꾼 뒤에는 앱을 실행해서 직접 확인한다. 권한 허용처럼 사용자가 해야 하는 단계는 사용자에게 요청한다

## 코드 규칙

- Swift 6 언어 모드(strict concurrency). 데이터를 가져오는 서비스는 `actor`, 화면용 모델은 `@Observable @MainActor`
- SwiftUI 우선. 노치 창·서랍 창·메뉴바 아이템 등 SwiftUI로 안 되는 부분만 AppKit(`NSPanel`, `NSStatusItem`)
- 에이전트 앱(`LSUIElement`), **App Sandbox 끔**
- 서명: `scripts/build.sh`가 유효한 Apple Development 인증서, 없으면 이 맥의 자체 서명 인증서 **"Mactatus 개발 서명"**(코드 서명 "항상 신뢰")으로 서명한다. 번들 ID `app.mactatus.Mactatus` 고정
  - 임시 서명(ad-hoc)으로 되돌리지 말 것 — 빌드마다 서명값이 바뀌어 손쉬운 사용 권한이 맞지 않게 된다
  - 자체 서명 인증서는 "항상 신뢰"가 아니면 시스템 설정에서 켜져 있어도 macOS가 권한을 거부한다(AX 오류 -25211)
  - 한글 인증서 이름으로는 codesign이 실패하므로 지문(SHA-1)으로 지정한다
  - 앱은 `open build/Mactatus.app`(또는 `scripts/run.sh`)으로 띄운다. 터미널에서 실행 파일을 직접 띄우면 권한 판단이 터미널 쪽 프로세스 기준이 된다
- 메뉴바 서랍은 아이콘을 옮기지 않는다(⌘-끌기 합성·빈 공간 없음). 숨기기는 사용자가 시스템 설정 → 메뉴 막대 → "메뉴 막대에서 허용"에서 하고, 서랍은 손쉬운 사용으로 목록을 읽고 `AXPress`로 연다. 시스템 설정 값은 직접 바꾸지 않고 화면만 열어 준다
- 메뉴바 아이템은 SwiftUI `MenuBarExtra` 대신 `StatusItemHost`로 직접 만든다(이름·처음 자리를 정할 수 있게). 자세한 이유는 docs/spike-results.md 8·9
- 외부 의존성은 KeyboardShortcuts, mediaremote-adapter만. 다른 패키지를 추가하려면 먼저 사용자에게 물어본다
- 성능 목표: 대기 중 CPU 0.5% 미만, 메모리 100MB 미만. 타이머에 tolerance를 주고, 팝오버가 닫혀 있거나 화면이 잠기면 측정을 줄이거나 멈춘다

## 디자인

- macOS에 원래 있던 기능처럼 보여야 한다: Liquid Glass, SF Pro, SF Symbols, 시스템 색상과 사용자 강조 색상
- 임의의 색·글꼴을 쓰지 않는다. 예외는 상태 색상 3개(초록 정상 / 노랑 70% 이상 / 빨강 90% 이상)
- 다크·라이트 모드, 대비 증가, 동작 줄이기, VoiceOver를 함께 확인한다
- 노치 확장 영역은 순수 검정 + 하드웨어 노치와 이어지는 곡선 모서리

## 비공개 API·비공식 경로

- 비공개 프레임워크(MediaRemote, 센서, CGS 등)와 비공식 엔드포인트(사용량 API)를 쓰는 코드는 한 타입·파일 안에 격리한다
- 해당 파일 맨 위 주석에 "비공식"이라고 적고, 동작을 확인한 macOS 버전을 기록한다
- 실패하면 앱이 죽지 않고 그 기능만 숨기거나 대체 모드로 전환한다(서랍 → 권한 안내, 사용량 API → 로컬 로그 추정값)

## 보안·개인정보

- Claude·Codex·Gemini·Antigravity 토큰은 메모리에서만 쓴다. 로그·디스크·에러 메시지에 남기지 않고, 해당 서비스의 공식 도메인으로만 보낸다
- 사용자의 `~/.claude`, `~/.codex`, `~/.gemini`는 **읽기만** 한다. 절대 수정하지 않는다
- 클립보드 기록은 이 맥에만 저장하고, `ConcealedType`·`TransientType` 항목(비밀번호 관리자 등)은 저장하지 않는다
- 텔레메트리·외부 전송 없음

## 작업 방식

- 사용자와는 한국어로 대화한다. 전문 용어는 쉬운 말로 풀어 쓴다
- 0단계 검증 결과는 `docs/spike-results.md`에 기록한다: 항목마다 가능 / 우회 필요 / 불가능, 근거, 확인한 macOS 버전
- 계획과 다르게 가야 할 때(API가 안 되는 경우 등)는 먼저 사용자에게 알리고, 합의하면 PLAN.md도 고친다
- 단계를 마치면 PLAN.md 7장 로드맵에 완료 표시를 한다
- 커밋은 사용자가 요청할 때만 한다
- 단계별 추천 모델과 effort는 PLAN.md 11장을 따른다
