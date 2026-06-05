# PocketLlama

맥북에서 `llama.cpp`(`llama-server`)로 서빙하는 **Qwen3.6-35B-A3B** 모델에, 아이폰 SwiftUI 앱이 **Anthropic 호환 `/v1/messages`(SSE 스트리밍)**로 붙어 멀티턴 채팅하는 로컬 LLM 클라이언트 MVP.

## 구조
```
.
├── app/PocketLlama.xcodeproj   # iOS 앱 (SwiftUI, URLSession)
│   └── PocketLlama/            #   Models·Utilities·Services·Stores·ViewModels·Views
├── server/                     # llama.cpp 서빙 스크립트 (serve.sh: HOST 변형, test-anthropic.sh)
├── models/                     # 모델 가중치(gitignore, 하드링크) — Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf
├── plans/                      # 구현 계획서(v3) + 리뷰
├── docs/                       # 사전 조사
└── .claude/                    # 하네스(에이전트·스킬) — 아래
```

## 빠른 시작

### 1) 서버 기동 (맥북)
```bash
HOST=0.0.0.0 ./server/serve.sh          # 0.0.0.0 = 아이폰/LAN 접속용
# 게이트 검증(권장): .claude/skills/server-gate/scripts/gate.sh --out plans/_gate.md
```
> ⚠️ `0.0.0.0` + 무인증은 같은 Wi-Fi 전체 노출. 신뢰된 가정용 LAN에서만. (보안: `server/README.md`)

### 2) 앱 빌드/실행 (Xcode)
```bash
open app/PocketLlama.xcodeproj
```
- 실기기(또는 시뮬레이터)에서 실행 → `SettingsView`에 맥북 IP(`http://192.168.x.x:8080`) 입력 → 연결 테스트 → 채팅.
- 최소 타깃 iOS 26.4 (현 설정). 코드 컴파일 검증은 `.claude/skills/xcode-build-check/scripts/build-check.sh`(이 맥은 iOS 시뮬 미설치라 macOS SDK 폴백).

## 하네스 (.claude)
이 repo는 두 하네스로 운영한다(상세: `CLAUDE.md`):
- **`strict-review`** — 코드·계획서를 내부+agy(Gemini)·grok 외부 리뷰로 엄중 검토·통합
- **`ios-build`** — 계획서 Phase를 SwiftUI 코드로 구현(swift-builder)+검증(ios-qa), `server-gate`/`xcode-build-check` 보조

## 상태 (2026-06-05)
- ✅ 서버 게이트 통과(`/v1/messages` 비스트림·SSE 실측, `model:"local"` 동작)
- ✅ 앱 Phase 1~8 구현 + 빌드 통과(에러 0) + QA 경계면 검증
- ⏳ Phase 9(실기기) — 이 맥에 iOS 26.5 플랫폼 미설치. Xcode > Settings > Components에서 설치 후 실기기/시뮬 실행.
