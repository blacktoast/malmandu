# 말만두 (malmandu)

맥OS 메뉴바에 상주하는 음성-텍스트 변환 도구입니다. 글로벌 단축키를 누르면 마이크 녹음을 시작하고, 다시 누르면 STT API로 전사하여 현재 포커스된 입력창에 자동으로 붙여넣습니다.

**지원 STT 제공자:** Groq Whisper, Soniox (비동기 + 실시간 WebSocket)

## 시스템 요구사항

- macOS 15.0 이상
- Swift 6.0 이상 (Xcode 16 이상)
- STT API 키:
  - [Groq API 키](https://console.groq.com) (무료 티어 제공)
  - [Soniox API 키](https://console.soniox.com) (선택사항)

## 빌드 및 실행

```bash
# 빌드
swift build

# 테스트 실행 (44개 테스트)
swift test

# 앱 실행 (터미널에서 직접)
swift build && .build/debug/Malmandu

# 앱 실행 (권장 — .app 번들로 래핑하여 메뉴바 아이콘 정상 표시)
./scripts/run.sh

# Xcode에서 열기
open Package.swift
```

> **참고:** `swift run Malmandu`로도 실행 가능하지만, `.app` 번들이 아니라 메뉴바 아이콘이 표시되지 않을 수 있습니다.
> `scripts/run.sh`를 사용하면 자동으로 `.app` 번들을 생성하고 실행합니다.

## API 키 설정

### Groq

1. [console.groq.com](https://console.groq.com)에서 계정 생성 후 API 키 발급
2. 앱 실행 후 메뉴바 아이콘 클릭 → **설정...** 선택
3. **API** 탭 → **서비스 제공자**에서 **Groq** 선택
4. API 키 입력 → **연결 테스트**로 확인

### Soniox

1. [console.soniox.com](https://console.soniox.com)에서 계정 생성 후 API 키 발급
2. **API** 탭 → **서비스 제공자**에서 **Soniox** 선택
3. API 키 입력 → **연결 테스트**로 확인
4. **STT 모델** 드롭다운에서 원하는 모델 선택

API 키는 macOS Keychain에 제공자별로 안전하게 저장됩니다.

## STT 모델

| 제공자 | 모델 | 방식 | 설명 |
|--------|------|------|------|
| Groq | `whisper-large-v3` | 동기 REST | 정확도 우선 (기본값) |
| Groq | `whisper-large-v3-turbo` | 동기 REST | 속도 우선 |
| Soniox | `stt-rt-v4` | WebSocket 실시간 | 실시간 변환 (기본값) |
| Soniox | `stt-async-v4` | 비동기 REST | 파일 업로드 → 폴링 |
| Soniox | `stt-async-v3` | 비동기 REST | 레거시 |

## 단축키 사용법

| 동작 | 기본 단축키 |
|------|------------|
| 녹음 시작 / 중지 | `⌥ + ⌃ + Space` (Option+Control+Space) |
| 녹음 시작 / 중지 (대체) | `Fn` 키 |

설정 → **녹음** 탭에서 원하는 단축키로 변경할 수 있습니다.

## 사용 흐름

1. 텍스트를 입력하고 싶은 앱의 입력창에 포커스
2. `⌥ + ⌃ + Space` 또는 `Fn`으로 녹음 시작 (메뉴바 아이콘이 채워진 마이크로 변경)
3. 말하기
4. 같은 키를 다시 눌러 녹음 중지
5. 선택된 STT 제공자가 음성을 텍스트로 변환하여 자동 붙여넣기

## 시스템 권한 설정

앱이 처음 실행될 때 두 가지 권한을 요청합니다.

### 마이크 권한

**시스템 설정 → 개인정보 보호 및 보안 → 마이크** 에서 말만두를 허용합니다.

### 손쉬운 사용 (Accessibility) 권한

텍스트 자동 붙여넣기에 필요합니다.

**시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용** 에서 말만두를 허용합니다.

> 권한이 없으면 텍스트 변환은 되지만 자동 붙여넣기가 작동하지 않습니다.

## 설정 옵션

| 탭 | 항목 | 설명 |
|----|------|------|
| API | 서비스 제공자 | Groq / Soniox 선택 |
| API | API 키 | 선택된 제공자의 인증 키 (Keychain 저장) |
| API | STT 모델 | 제공자별 모델 선택 |
| API | 연결 테스트 | API 키 유효성 확인 |
| 녹음 | 녹음 단축키 | 글로벌 단축키 커스터마이징 |
| 녹음 | 기본 언어 | 한국어, English, 日本語, 中文, Español, Français, Deutsch |
| 일반 | 효과음 | 녹음 시작/종료 효과음 on/off |

## 프로젝트 구조

```
Sources/
├── MalmanduCore/          # 핵심 비즈니스 로직 (테스트 가능)
│   ├── Models/
│   │   └── AppState.swift  # 앱 상태 (@Observable)
│   ├── Services/
│   │   ├── STTServiceProtocol.swift      # STT 프로토콜 + STTProvider enum
│   │   ├── DynamicSTTClient.swift        # 런타임 제공자 전환 프록시
│   │   ├── GroqAPIClient.swift           # Groq Whisper API 클라이언트
│   │   ├── SonioxSTTClient.swift         # Soniox 비동기 REST 클라이언트
│   │   ├── SonioxRealtimeClient.swift    # Soniox 실시간 WebSocket 클라이언트
│   │   ├── RecordingCoordinator.swift    # 녹음→STT→붙여넣기 파이프라인
│   │   ├── AudioRecorder.swift           # AVFoundation 마이크 녹음
│   │   ├── AudioProcessor.swift          # FluidAudio VAD 무음 제거
│   │   ├── KeychainService.swift         # API 키 Keychain 저장
│   │   ├── TextInjector.swift            # Accessibility 기반 텍스트 붙여넣기
│   │   └── SoundService.swift            # 효과음 재생
│   └── Overlay/
│       ├── OverlayPanel.swift            # 투명 NSPanel
│       ├── OverlayManager.swift          # 오버레이 생명주기 관리
│       └── OverlayContentView.swift      # 상태별 SwiftUI 뷰
└── Malmandu/
    └── MalmanduApp.swift  # 진입점, 메뉴바, 설정 UI

Tests/
└── MalmanduCoreTests/     # 44개 단위 테스트
```

## 아키텍처

```
┌─────────────────┐   ┌──────────────────┐   ┌─────────────────┐
│  AudioRecorder   │──>│ AudioProcessor   │──>│ STTServiceProtocol │
│  (마이크 녹음)    │   │  (VAD 무음제거)   │   │  (음성→텍스트)    │
└─────────────────┘   └──────────────────┘   └────────┬────────┘
                                                       │
                          ┌────────────────────────────┤
                          │           DynamicSTTClient  │
                          │         (런타임 라우팅)      │
                          ├────────────┬───────────────┤
                          │            │               │
                    GroqAPIClient  SonioxSTT    SonioxRealtime
                    (REST 동기)    (REST 비동기)  (WebSocket)
```

## 기술 스택

- **Swift 6** + Swift Concurrency (async/await, actor)
- **SwiftUI** — 메뉴바, 설정 화면, 오버레이
- **AVFoundation** — 마이크 녹음 (M4A 포맷)
- **URLSession WebSocket** — Soniox 실시간 스트리밍
- **Groq Whisper API** — 음성→텍스트 변환
- **Soniox API** — 비동기 REST + 실시간 WebSocket STT
- **FluidAudio** — Silero VAD 기반 무음 구간 제거
- **Security framework** — Keychain API 키 저장
- **KeyboardShortcuts** — 글로벌 단축키
- **Swift Testing** — 단위 테스트 (`@Test`, `#expect`)
