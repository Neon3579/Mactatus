# Mactatus

개인용 macOS 메뉴바·노치 허브 앱. 전체 계획과 확정된 결정은 [PLAN.md](PLAN.md)에 있다. 작업을 시작하기 전에 해당 단계 부분과 [docs/spike-results.md](docs/spike-results.md)(0단계 검증 결과, 만들어진 뒤)를 먼저 읽을 것.

## 구성

| 영역 | 위치 | 패키지 |
|---|---|---|
| ① AI 사용량(Claude Code·Codex·Gemini, 안 되면 Antigravity) | 메뉴바 아이콘 + 팝오버 | `UsageKit` |
| ② 시스템 리소스 | 메뉴바 아이콘 + 팝오버(①과 별도 아이콘) | `MetricsKit` |
| ③ 메뉴바 서랍(Windows 숨겨진 아이콘 방식, 편집 모드 포함. macOS 기본 « 버튼은 그대로 둠) | 메뉴바 ⌄ + 서랍 패널 | `DrawerKit` |
| ④ 노치 허브(음악·블루투스·다운로드·파일 트레이·상태 팝업·스크린샷·클립보드) | 내장 디스플레이 노치 | `NotchKit`, `Modules` |

폴더 구조는 PLAN.md 5장을 따른다. Xcode 프로젝트는 1단계에서 만든다.

## 환경

- 대상: **macOS 26 이상만**(deployment target 26.0). 이전 버전용 분기·대체 디자인을 만들지 않는다
- 개발 맥: MacBook Air M2(노치 있음), macOS 27, Xcode 26.6, Swift 6.3
- 개인용 앱: App Store·공증·자동 업데이트 없음

## 빌드·테스트

- Xcode 프로젝트를 만든 뒤 이 섹션에 실제 빌드·테스트 명령을 적을 것
- `UsageKit`의 파서는 단위 테스트 필수. 실제 응답·로그에서 만든 샘플을 테스트 데이터로 쓰되, 토큰·이메일 등 개인 정보는 지운다
- UI를 바꾼 뒤에는 앱을 실행해서 직접 확인한다. 권한 허용처럼 사용자가 해야 하는 단계는 사용자에게 요청한다

## 코드 규칙

- Swift 6 언어 모드(strict concurrency). 데이터를 가져오는 서비스는 `actor`, 화면용 모델은 `@Observable @MainActor`
- SwiftUI 우선. 노치 창·서랍·메뉴바 구분자 등 SwiftUI로 안 되는 부분만 AppKit(`NSPanel`, `NSStatusItem`)
- 에이전트 앱(`LSUIElement`), **App Sandbox 끔**
- 서명: **Apple Development 인증서 + 1단계에서 정한 번들 ID를 고정**. "Sign to Run Locally"로 바꾸지 말 것 — 빌드마다 손쉬운 사용·화면 기록 권한이 풀린다
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
- 실패하면 앱이 죽지 않고 그 기능만 숨기거나 대체 모드로 전환한다(서랍 → 접기 모드, 사용량 API → 로컬 로그 추정값)

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
