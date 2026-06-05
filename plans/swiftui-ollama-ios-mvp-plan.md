# SwiftUI PocketLlama iOS MVP 세부 계획

작성일: 2026-04-02
개정 이력:
- v2 (2026-06-05): 서빙 백엔드 · 모델 · 폴더 구조 전면 개정 (`Ollama` → `llama.cpp`)
- **v3 (2026-06-05): Gemini·Grok 리뷰 반영** — Pre-Phase 0 실측 게이트, 멀티턴 계약, 신규 생성 전략, 보안/ATS/SSE/취소 보강. (출처: `plans/swiftui-ollama-ios-mvp-plan-review.md`, `plans/swiftui-ollama-ios-mvp-plan-review-grok.md` — §16에 통합 판정)

참조 문서: `docs/ollama-iphone-research.md` (단, 서빙 전제는 본 계획서가 `Ollama` → `llama.cpp`로 갱신함)

---

## 0. 이번 개정 요약 (v1 → v2 → v3)

| 항목 | v1 (구) | v2/v3 (현행) |
|---|---|---|
| 서빙 백엔드 | `Ollama` (app) | **`llama.cpp` (`llama-server`)** |
| 모델 | `qwen3.5:27b-coding-nvfp4` | **`Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf` (로컬 GGUF)** |
| 모델 경로 | ollama 내부 | `~/workspace/dev/llm-serving/models/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf` (~27GB) |
| API | `POST /api/chat` (줄단위 JSON) | **Anthropic 호환 `POST /v1/messages` (SSE)** |
| 포트 | `11434` | **`8080`** |
| 모델 선택 | 여러 모델 전환 | **단일 모델 표시** (llama-server는 1개 로드) |
| 앱 이름 | `ollama-iphone` | **`PocketLlama`** (확정 2026-06-05) |
| Phase 1 전략 | (미정) | **신규 생성** (리네임 금지 — §4.4 근거) |
| 폴더 구조 | 분산/중첩 git | **`app/` · `server/` · `docs/` · `plans/` 단일 repo** |

### 실행 순서 원칙 (v3에서 모순 해소)

> 리뷰 지적(Grok §3.1): 기존 v2는 "코드/구조 안 건드림"과 "Phase 0에서 `server/serve.sh` 실행"이 모순이었다. v3에서 **단일 경로로 고정**한다:
>
> 1. **Phase 0 게이트**는 `~/workspace/dev/llm-serving`에서 **직접** 수행한다(이 repo의 `server/` 복제 불필요). 서버가 아이폰 접속·Anthropic API로 실제 동작하는지 **먼저 실측**한다.
> 2. **§5.4 폴더 마이그레이션**(`server/` 복제 · 루트 `git init` · `app/` 신규 생성)은 **Phase 1 직전**에 일괄 수행한다.
> 3. 그 전까지 코드·Xcode·폴더는 변경하지 않는다.

---

## 1. 목표 / 범위

맥북에서 `llama-server`로 서빙 중인 `Qwen3.6-35B-A3B` 모델에, 아이폰 네이티브 앱이 **Anthropic 호환 `/v1/messages`**로 접속해 **멀티턴 채팅**하는 `SwiftUI` MVP.

범위: 같은 Wi-Fi 접속 / 서버 URL 저장 / 연결 테스트(`/health`) / 모델 표시(`/v1/models`) / **멀티턴** 채팅(비스트리밍 검증 → 스트리밍 본선) / 요청 취소 / 실기기 실행.

범위 밖: App Store 배포, 외부 공개 노출, 멀티 사용자 인증, 음성/카메라/이미지, **thinking 블록 UI**(서버 기본 `THINK=off`이므로 — §12·§16 참고), tool use.

---

## 2. Definition of Ready — Pre-Phase 0 게이트 (신설, 필수)

> ✅ **통과 완료 (2026-06-05, `plans/_gate.md`)**: `/health` 200, `/v1/models`(id=파일명), `/v1/messages` 비스트림 "Pong", SSE `text_delta` 모두 PASS. `model:"local"` 수용 확인. 무인증 동작. 자동화: `.claude/skills/server-gate/scripts/gate.sh`.

> 리뷰 지적(Grok §3.2, §8): 앱이 쓸 경로(`/v1/messages`)가 **실측되지 않은 채** iOS를 짜기 시작하면, 중반에 "404/파싱 실패/경로 없음"으로 되돌릴 위험이 크다. 아래 8줄을 **모두 통과**해야 Phase 1로 간다.

**서버 사실(확인됨):** `llama-server` 버전 9430에 `--api-key`(env `LLAMA_API_KEY`), `--reasoning [on|off|auto]`, `--jinja` 존재. `llm-serving/README.md`는 "최신 llama.cpp가 Anthropic Messages API(`/v1/messages`)를 스트리밍·tool use 포함 네이티브 지원"이라 명시 → **별도 변환 프록시 불필요**(Gemini 위험1은 과장). **단, 아래 E2E 실측으로 최종 확정한다.**

착수 전 체크리스트:

1. [ ] 맥북에서 서버를 **`0.0.0.0` 바인딩**으로 기동 (방법은 §6)
2. [ ] 맥북 로컬에서 `POST /v1/messages` (비스트리밍) **HTTP 200** + `content[].text` 수신
3. [ ] 동일 요청에 `"stream": true` → SSE에서 `text_delta` **1회 이상** 수신
4. [ ] **LAN 타 기기**(아이폰 브라우저 등)에서 `GET /health` **200**
5. [ ] LAN 타 기기에서 `GET /v1/models` 응답 스키마 1건 확보(§7.4 채울 샘플)
6. [ ] `--api-key` 적용 시, **Anthropic 경로의 인증 헤더 형식**(`x-api-key` vs `Authorization: Bearer`) 실측 확정 (§4.5)
7. [ ] 맥북 IP·방화벽(8080 인바운드)·동일 Wi-Fi 확인
8. [ ] 위 결과를 §7.4·§4.5에 **반영**(샘플 JSON·헤더 형식 고정)

검증용 curl (맥북 또는 LAN 기기):

```bash
# 비스트리밍 200 + 텍스트
curl -s "http://<HOST>:8080/v1/messages" \
  -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"local","max_tokens":64,"messages":[{"role":"user","content":"ping"}]}'

# 스트리밍 SSE
curl -N "http://<HOST>:8080/v1/messages" \
  -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"local","max_tokens":64,"stream":true,"messages":[{"role":"user","content":"ping"}]}'
```

> ⚠️ **이 게이트가 통과되기 전까지 iOS 코드는 작성하지 않는다.** (DoR)

---

## 3. 현재 전제 (이 Mac·이 시점 기준)

> Grok §5 메모: "검증 완료"는 이 머신·이 시점 전제다. 다른 머신에서는 §6 이식성 메모를 따른다.

- **모델 파일**: `~/workspace/dev/llm-serving/models/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf` (≈25.3 GiB) — 존재 확인
- **llama.cpp**: Homebrew, `/opt/homebrew/bin/llama-server`, version **9430** — 설치 확인
- **서버 스크립트**: `llm-serving/scripts/serve.sh`
  - 포트 `8080`, `-ngl 999 -fa on`, KV `q8_0`, ctx 기본 65536
  - thinking 기본 `--reasoning off` (`THINK=off`)
  - 샘플링 기본 `temp 1.0 / top_p 0.95 / top_k 20`
  - **`--host 127.0.0.1` 고정** ← 아이폰 접속 블로커(§6에서 해소)
  - 엔드포인트: OpenAI `/v1/chat/completions` · Anthropic `/v1/messages` · `/health` · `/v1/models` · 웹 UI `/`
- **인증**: 기본 무인증(`ANTHROPIC_AUTH_TOKEN`=아무 값). `--api-key`로 켤 수 있음(§4.5).
- **현재 Xcode 프로젝트**: `IPHONEOS_DEPLOYMENT_TARGET = 26.4`, `PBXFileSystemSynchronizedRootGroup` 방식 — **수동 리네임 취약**(§4.4 근거).

---

## 4. 아키텍처 결정 (확정)

1. **앱 이름**: **`PocketLlama`** (확정 2026-06-05). 번들 ID 예 `com.drlee.pocketllama`, `@main` = `PocketLlamaApp`.

2. **API 방식**: **Anthropic 호환 `/v1/messages`** (`URLSession` raw HTTP — Swift 공식 SDK 없음).

3. **서버 위치**: 이 repo `server/`에 **스크립트만** 복제(27GB 가중치 미포함, §5.3). 원본 SSOT는 `llm-serving`.

4. **Phase 1 = 신규 생성 (리네임 금지)** ✅ *v3 결정*
   - 근거: 현재 프로젝트가 `PBXFileSystemSynchronizedRootGroup`(Xcode 16+ 동기화 그룹) + 배포타깃 26.4. 이 방식에서 폴더명/타깃명 수동 변경은 참조 유실·빌드 실패 위험이 크다(Gemini 위험2, Grok §3.4).
   - 방침: 기존 `ollama-iphone/`은 **삭제**(내용이 Hello World 템플릿뿐이라 보존 가치 없음), `app/`에 Xcode로 **새 `PocketLlama` 프로젝트를 깨끗이 생성**한다. 중첩 `.git` history도 함께 폐기(보존할 커밋은 "Initial Commit" 하나뿐).

5. **보안: LAN 무인증 vs `--api-key`** — *결정 필요(§14), v3 권장안 제시*
   - 문제: `0.0.0.0` 바인딩 시 동일 Wi-Fi의 누구나 맥북 35B에 프롬프트를 보낼 수 있다(Gemini 위험4, Grok §3.5).
   - **권장 A (MVP 기본)**: "신뢰된 가정용 LAN, 무인증 수용". `server/README.md`에 **경고 명시**. 외부망은 절대 노출 금지(Tailscale은 Phase 10).
   - **옵션 B (강화)**: 서버 `--api-key <KEY>`(env `LLAMA_API_KEY`) + 앱 `SettingsView`에 키 입력란 + `UserDefaults` 저장 + 모든 요청에 인증 헤더.
     - ⚠️ **헤더 형식은 실측 후 고정**: llama-server의 `--api-key`는 OpenAI 경로에서 `Authorization: Bearer`를 검사한다. Anthropic 경로(`/v1/messages`)에서 `x-api-key`를 받는지 §2 게이트 6번에서 확인해 여기에 적는다.

6. **클라이언트 프로토콜 추상화** ✅ *v3 결정*
   - 리뷰 지적(Grok §5, Gemini 위험1 대안2): Phase 10에서 OpenAI 호환을 병행하면 `AnthropicChatClient`라는 이름이 거짓이 된다.
   - 방침: `protocol LLMChatClient`(send/stream/health/models)를 정의하고 `AnthropicChatClient`가 이를 구현. Phase 10에서 `OpenAIChatClient`를 같은 프로토콜로 추가.

---

## 5. 목표 폴더 구조

### 5.1 현재 문제점
- 루트가 git 아님 / `ollama-iphone/`만 중첩 git → 버전관리 분산
- 이름이 `ollama` 기반인데 백엔드는 `llama.cpp` → 혼란
- 서버 스크립트 둘 곳 없음, 앱 내부 구조 부재

### 5.2 목표 구조
```
pocket-llama-lab/                  # 루트 (2026-06-05 ollama-iphone-lab → pocket-llama-lab 변경 완료)
├── README.md                      # 신규: 개요 + 서버 기동법(0.0.0.0/보안 경고) + 앱 빌드법
├── .gitignore                     # 신규: 빌드 산출물/xcuserdata/*.gguf/.DS_Store
├── docs/
│   └── research.md                # 구 ollama-iphone-research.md (이름 정리 + v2 전환 박스)
├── plans/
│   └── mvp-plan.md                # 본 계획서 (이름 정리; 현 파일명 swiftui-ollama-ios-mvp-plan.md)
├── server/                        # llm-serving에서 가져온 사본(스크립트만)
│   ├── README.md                  # 0.0.0.0 안내 + 보안 경고 + 이식성(MODEL 경로)
│   ├── serve.sh                   # HOST 변형(§6)
│   └── test-anthropic.sh          # /v1/messages 비스트림+스트림 스모크(앱 경로 검증)
└── app/
    └── PocketLlama.xcodeproj + PocketLlama/
        ├── PocketLlamaApp.swift
        ├── Models/                # ChatTurn, MessagesRequest/Response, StreamChunk, ModelsResponse, ClientError
        ├── Utilities/             # ServerURL(정규화), SSEDecoder
        ├── Services/              # LLMChatClient(프로토콜 + ChatCompletion/StreamEvent) + AnthropicChatClient
        ├── Stores/                # AppSettingsStore (URL, API Key, useStreaming)
        ├── ViewModels/            # ChatViewModel + ChatState
        ├── Views/                 # RootView, SettingsView, ModelInfoView, ChatView
        └── Assets.xcassets/
```

### 5.3 server/ ↔ llm-serving 동기화 + 이식성
- 원본 SSOT: `~/workspace/dev/llm-serving/scripts/`. `server/`는 앱·아이폰 접속용 최소 사본.
- **이식성(Grok §4.9)**: `serve.sh` 기본 모델은 특정 Mac 절대경로. `server/README.md`에 다른 머신에서 쓰는 법을 명시 — **`MODEL` 환경변수 / 첫 인자(로컬 GGUF 경로 또는 `repo:quant`) / `LLAMA_CACHE`**.

### 5.4 마이그레이션 단계 (Phase 1 직전 일괄 — Phase 0 통과 후)
1. 루트 `git init`, 루트 `.gitignore`/`README.md` 작성
2. `ollama-iphone/` 삭제(신규 생성 방침이므로 보존 불필요. 굳이 history 보존 시 `git subtree`/`filter-repo`는 과함)
3. `server/` 생성 + `llm-serving`에서 `serve.sh`(HOST 변형)·`test-anthropic.sh` 복제
4. `docs/ollama-iphone-research.md` → `docs/research.md`(+ 상단 v2 전환 박스), `plans/...` → `plans/mvp-plan.md`
5. 첫 통합 커밋

---

## 6. 서버 측 준비

목표: 아이폰이 `http://<맥북IP>:8080/v1/messages`로 접속.

- [ ] **Phase 0(게이트)**: `server/` 복제 없이 `llm-serving`에서 직접 `0.0.0.0` 기동. 두 방법 중 택1:
  - (a) `serve.sh`의 `--host`를 일시적으로 `0.0.0.0`로 실행, 또는
  - (b) 스크립트 수정 없이 직접:
    ```bash
    llama-server -m ~/workspace/dev/llm-serving/models/Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf \
      --host 0.0.0.0 --port 8080 -ngl 999 -fa on --jinja --reasoning off \
      --cache-type-k q8_0 --cache-type-v q8_0 -c 65536
    ```
- [ ] **Phase 1 이후(`server/serve.sh`)**: `HOST` 환경변수 추가 → `--host "${HOST:-127.0.0.1}"`. 아이폰 접속 시 `HOST=0.0.0.0 ./server/serve.sh`
- [ ] **보안 결정 적용**(§4.5): 무인증이면 `server/README.md`에 경고. `--api-key`면 키 전달.
- [ ] **맥 절전 방지**(Grok §5): 서버 맥은 절전/디스플레이 슬립이 연결을 끊을 수 있음 → `caffeinate -dimsu` 또는 클램셸+전원 권장. Phase 9 검증과 연결.
- [ ] 맥북 IP·방화벽(8080)·동일 Wi-Fi 확인

메모: `THINK=off` 기본이라 MVP 응답에 thinking 블록이 안 섞인다(§12).

---

## 7. API 계약 상세 (Anthropic 호환 `/v1/messages`)

> Swift는 공식 SDK가 없으므로 `URLSession` raw HTTP로 직접 구현.

### 7.1 공통
- `POST http://<맥북IP>:8080/v1/messages`
- 헤더: `Content-Type: application/json`, `anthropic-version: 2023-06-01`. 인증 켜면 §4.5 형식.
- `model`: `"local"`. **`max_tokens` 필수**(누락 시 400).
- **URL 정규화 규칙(Grok §4.5)**: 사용자는 **base URL만** 저장(예 `http://192.168.0.10:8080`). 클라이언트가 경로를 조립한다 — 끝 슬래시 제거, 사용자가 실수로 `/v1/messages`를 넣으면 잘라냄, base + `/v1/messages` / `/health` / `/v1/models`로 합성.

### 7.2 멀티턴 요청 (MVP 핵심 — Grok §3.3)

UI 메시지 배열 → `messages`에 **user/assistant 교대**로 전송. assistant 히스토리 `content`는 **문자열**로 단순화(MVP).

```json
{
  "model": "local",
  "max_tokens": 1024,
  "system": "You are a helpful assistant.",
  "messages": [
    { "role": "user", "content": "내 이름은 Alice야." },
    { "role": "assistant", "content": "안녕하세요 Alice!" },
    { "role": "user", "content": "내 이름이 뭐였지?" }
  ]
}
```

- 첫 메시지는 `user`, 이후 교대. `system`은 top-level(생략 가능).
- **토큰 폭증 정책(Grok §3.3)**: 히스토리가 길어지면 ctx 초과·지연. MVP는 **최근 N턴만 전송**(예: 최근 12메시지)하는 단순 슬라이딩 윈도우. 요약은 Phase 10.

### 7.3 비스트리밍 응답
```json
{ "id":"msg_...", "type":"message", "role":"assistant",
  "content":[{"type":"text","text":"..."}],
  "stop_reason":"end_turn",
  "usage":{"input_tokens":12,"output_tokens":34} }
```
- 텍스트 = `content`에서 `type=="text"` 블록의 `text`. **`content[0]`를 가정하지 말 것**(THINK=on이면 `thinking` 블록이 먼저 올 수 있음).
- `stop_reason`: `end_turn` / `max_tokens`(잘림) / `tool_use` / `pause_turn` / `refusal`.

### 7.4 스트리밍 (SSE) — 파서는 normative

이벤트 시퀀스:
```
event: message_start      → {"type":"message_start","message":{...}}
event: content_block_start→ {"index":0,"content_block":{"type":"text","text":""}}
event: content_block_delta→ {"index":0,"delta":{"type":"text_delta","text":"안녕"}}
event: content_block_stop → {"index":0}
event: message_delta      → {"delta":{"stop_reason":"end_turn"},"usage":{...}}
event: message_stop
```
- 누적 텍스트 = `content_block_delta` 중 `delta.type=="text_delta"`의 `delta.text`.
- 종료 = `message_stop`. `stop_reason`은 `message_delta`.
- `thinking_delta`(THINK=on)는 MVP에서 **무시**.

**SSE 파싱은 줄 단위 단순 처리로 부족(Gemini §3, Grok §4.2).** 다음을 만족하는 **버퍼 기반 디코더**를 Phase 7의 normative 구현으로 한다:
- 이벤트 경계 = **빈 줄**(`\n\n`)에서 flush
- `data:` **다중 줄**은 `\n`으로 join(단순 concat 아님 — SSE 스펙)
- `\r\n` 대응(라인 끝 `\r` 제거)
- 알 수 없는 이벤트/주석(`:`)·`data: [DONE]` 류는 무시

참고 스켈레톤(보완 주석 포함):
```swift
struct SSEEvent { var event: String?; var data: String }

final class SSEDecoder {
    private var dataLines: [String] = []
    private var eventType: String?
    /// bytes.lines 로 받은 '한 줄'을 투입. 빈 줄이면 이벤트 1개 방출.
    func push(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            defer { dataLines.removeAll(); eventType = nil }
            guard !dataLines.isEmpty else { return nil }
            return SSEEvent(event: eventType, data: dataLines.joined(separator: "\n")) // 다중 data 줄 → \n join
        }
        if line.hasPrefix(":") { return nil }                       // 주석 무시
        if line.hasPrefix("event:") { eventType = trim(line, "event:") }
        else if line.hasPrefix("data:") { dataLines.append(trim(line, "data:")) }
        return nil
    }
    private func trim(_ s: String, _ p: String) -> String {
        String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
    }
}
```

### 7.5 보조 엔드포인트
- **연결 테스트**: `GET /health` → 200이면 정상(Anthropic 경로엔 가벼운 GET 없음).
- **모델 표시**: `GET /v1/models` (OpenAI 호환). **실측 샘플(2026-06-05, `plans/_gate.md`):**
  ```json
  { "object":"list", "data":[ { "id":"Qwen3.6-35B-A3B-UD-Q5_K_XL.gguf", "object":"model", "created":1780667041, "owned_by":"llamacpp", "meta":{ "n_ctx":65536, "n_params":35505251456 } } ] }
  ```
  → 표시값 `data[0].id` = **모델 파일명**(`"local"`이 아님). 단 **요청의 `model:"local"`은 서버가 수용**(게이트 비스트림 "Pong" 확인) — 표시는 파일명, 요청은 `"local"`로 OK. **fallback**: `/v1/models` 실패해도 `/health`만 200이면 "모델: (이름 미상)"으로 채팅 진행 가능하게(Grok §4.7).

### 7.6 에러 계약 (Grok §4.6)
- 4xx/5xx 시 본문 JSON(`{"error":{...}}` 또는 llama-server 형식)을 파싱해 사용자 메시지로.
- 네트워크 오류를 **분류**: 타임아웃 / 연결 거부(서버 꺼짐·포트 다름) / 로컬 네트워크 권한 거부 / DNS·주소 형식. → `ClientError` 공통 enum으로 묶어 일관 표시.

---

## 8. iOS 구현 포인트

### 8.1 네트워킹
- `URLSession`. 비스트리밍은 `data(for:)`, 스트리밍은 `URLSession.bytes(for:)` + `for try await line in bytes.lines` → §7.4 `SSEDecoder`.
- `URLSessionConfiguration.waitsForConnectivity = true`. `timeoutIntervalForRequest`는 35B TTFT 대비 넉넉히(120s+), 단 **취소 가능**해야 함(§8.5).
- **최소 iOS 버전**: `bytes(for:)`/`AsyncSequence`는 iOS 15+. 신규 생성 시 배포타깃은 **iOS 17+** 권장(현 프로젝트 26.4는 신규 생성으로 재설정). §14에 최종 기재.

### 8.2 로컬 네트워크 권한 (iOS 14+)
- `Info.plist`에 `NSLocalNetworkUsageDescription` **필수**.
- 권한 팝업은 앱 시작 직후가 아니라 사용자가 "연결 테스트/전송"을 누를 때 발생하도록.

### 8.3 ATS — 낙관적 서술 교정 (Gemini 위험3, Grok §4.1)
- v2의 "IP 직접 연결은 ATS 대상 아님"은 **부정확에 가깝다.** LAN 평문 HTTP는 아래 조합이 사실상 필요한 경우가 많다 → **Phase 2에서 기본 포함**:
  ```xml
  <key>NSLocalNetworkUsageDescription</key>
  <string>맥북에서 작동 중인 로컬 LLM 서버에 연결하여 대화를 송수신합니다.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
  ```
- `macbook.local`(mDNS) 호스트를 쓰면 **별도 ATS 예외**가 추가로 필요. MVP는 IP 직접 입력이라 우선 불필요하나 §8.3에 명기.

### 8.4 상태 머신 (Gemini 위험5, Grok §4.4)
`ChatViewModel`은 단순 로딩 불리언이 아니라 상태 머신으로:
- `.idle` — 입력 대기
- `.connecting` — 서버 연결 시도 중
- `.ingesting` — **"맥북이 프롬프트를 분석 중입니다…"** (첫 토큰 대기; 35B는 수 초~1분+)
- `.generating` — 스트리밍 수신 중
- `.cancelled` / `.failed(ClientError)`
각 상태에 구체적 한글 안내. "멈춘 듯" 오해·연타를 막음.

### 8.5 요청 취소·중복 방지 (Grok §4.4)
- **Cancel 버튼 = MVP 포함**(범위 밖 아님). `URLSessionTask.cancel()`로 진행 중 요청 중단 → `.cancelled`.
- 전송 중 전송 버튼 비활성화 + 디바운스(연타 방지). 한 번에 하나의 in-flight 요청만.

---

## 9. 앱 구조
- `PocketLlamaApp`(@main) → `RootView`(설정 미완료면 `SettingsView`, 아니면 `ChatView`)
- `Services/LLMChatClient`(protocol: `send`, `stream`, `health`, `models`) ← **추상화(§4.6)**
- `Services/AnthropicChatClient`(구현)
- `Stores/AppSettingsStore` — base URL(+선택적 API Key) `UserDefaults`
- `ViewModels/ChatViewModel` — 메시지 배열 + `ChatState`(§8.4) + 취소
- `Models/` — `ChatMessage`, `MessagesRequest/Response`, `SSEEvent`, `ClientError`(§7.6)
- `Views/` — `SettingsView`(URL/연결테스트/선택 키), `ModelInfoView`(현재 모델/fallback), `ChatView`(리스트+입력+Cancel)

---

## 10. 단계별 계획 (Phase) — 엄격 순서

### Phase 0. 서버 실측 게이트 (DoR)
§2 체크리스트 8줄을 `llm-serving`에서 직접 통과. **통과 전 iOS 코드 금지.**
완료 기준: LAN 기기에서 `/v1/messages` 비스트림 200 + 스트림 `text_delta` 수신.

### Phase 0.5. 폴더 마이그레이션 (§5.4)
루트 `git init`, `server/` 복제(+`test-anthropic.sh`), `app/` 자리 준비. (research.md 전환 박스도 여기서 최소 패치 — Grok §4.8)

### Phase 1. PocketLlama **신규 생성** (리네임 금지 — §4.4)
- `app/`에 새 SwiftUI 프로젝트 `PocketLlama` 생성, 번들ID·최소 iOS(§8.1) 설정
- 폴더 구조(`Models/Services/Stores/ViewModels/Views`)
- 실기기 빌드 확인
완료 기준: 빈 `PocketLlama`가 실기기 실행.

### Phase 2. 로컬 네트워크 + ATS
- `Info.plist`: `NSLocalNetworkUsageDescription` + **`NSAllowsLocalNetworking=YES`(기본 포함)**(§8.3)
- 권한 팝업을 "연결 테스트" 동작에 연결
완료 기준: 로컬 네트워크 연결 시 권한 흐름이 깨지지 않음.

### Phase 3. 설정 화면
- `SettingsView`: base URL 입력 + **정규화 규칙(§7.1)** + (보안 옵션 B면) API Key 필드
- 검증/저장/복원(`UserDefaults`)
완료 기준: URL 저장 후 재실행에도 유지, 클라이언트가 base+경로 조립.

### Phase 4. 연결 테스트
- `health()` → `GET /health`, 상태·에러 **분류 표시(§7.6)**
완료 기준: 버튼으로 연결 여부 + 실패 원인 구분.

### Phase 5. 모델 표시
- `GET /v1/models` → `data[0].id` 표시, **실패 시 fallback(§7.5)**
완료 기준: 모델명 표시 또는 fallback로 채팅 진행 가능.

### Phase 6. 비스트리밍 — **검증용 최소 1회 + 멀티턴** (UX 본선 아님)
> Grok §4.3: 35B 비스트리밍은 UI가 오래 멈춘 듯 + 120s 타임아웃과 맞물려 실패/중복. → **짧은 답(작은 `max_tokens`)으로 경로·파싱·멀티턴만 검증**하고 실사용 UX는 Phase 7로.
- `POST /v1/messages`(stream 없음, `max_tokens` 포함, `model:"local"`)
- `content` text 블록 표시, `stop_reason=="max_tokens"` 잘림 안내
- **멀티턴(§7.2)**: UI 배열을 user/assistant 교대로 전송
완료 기준: **2턴 이상 맥락 유지**(예: 이름 기억) 확인 + 단발 왕복 성공.

### Phase 7. 스트리밍 — **실사용 UX 필수**
- `stream:true` + **`SSEDecoder`(§7.4 normative)**
- `text_delta` 누적·자동 스크롤, `message_stop` 종료
- **상태 머신(§8.4) + Cancel(§8.5)** 적용
완료 기준: 점진 표시 + `.ingesting` 안내 + 중간 취소 동작.

### Phase 8. 기록·UX 정리
- 최근 대화 1세션 저장/복원, 새 대화, 에러 배너, 빈 상태
완료 기준: 껐다 켜도 마지막 상태 이어서 사용.

### Phase 9. 실기기 검증
- 실제 Wi-Fi 연결 / **맥 절전 시 실패 동작(§6)** / 35B 지연 체감 / 긴 응답 프리징 / 끊김·잘못된 IP UX / 백그라운드 복귀
완료 기준: 비개발자 관점에서도 기본 흐름이 막히지 않음.

### Phase 10. 선택적 확장
- `Tailscale`(HTTPS 원격) / `--api-key` 강화 / **OpenAI 호환 `OpenAIChatClient`(프로토콜 재사용, §4.6)** / **thinking 블록 UI(THINK=on일 때만 — §12)** / 다중 서버·모델(`llama-swap`) / 고급 옵션(시스템 프롬프트·온도·max_tokens) / 코드블록 복사·다크모드 / 히스토리 요약(토큰 관리)

---

## 11. 세부 태스크 묶음
- **A. 게이트/서버**: §2 8줄 통과, `server/`(HOST 변형+`test-anthropic.sh`), 보안 결정 적용, 절전 방지
- **B. 앱 뼈대**: `app/` **신규** PocketLlama + 폴더 구조 + 최소 iOS
- **C. 서버 연결**: URL 정규화 저장, `health()`+에러분류, `/v1/models`+fallback
- **D. 채팅 핵심**: 멀티턴 비스트리밍 검증, `SSEDecoder` 스트리밍, 상태머신+Cancel, `ClientError`
- **E. 마무리**: persistence, 실기기, §5.4 마이그레이션, `docs/research.md` 전환 박스(Phase 0.5에 앞당김), 루트 `README.md`(보안 경고 포함)

---

## 12. 구현 시 주의
- **`max_tokens` 누락 금지**(Anthropic 필수). **`content`/스트림 타입 분기**(text vs thinking).
- **멀티턴은 매 요청 전체 히스토리 전송**(API stateless) + 슬라이딩 윈도우(§7.2).
- **thinking UI는 MVP 범위 밖**: 서버 기본 `THINK=off`라 응답에 `<think>`/`thinking` 블록이 없음. Gemini 리뷰의 "Risk 6: `<think>` 파싱 필수(Phase 7)"는 본 계획과 충돌 → **Phase 10(THINK=on일 때만)로 유지**(Grok §5·§7과 일치).
- **보안**: `0.0.0.0`은 LAN 전체 노출. 외부망 직접 노출 금지(Tailscale로만). 무인증 채택 시 README 경고.
- 27GB GGUF는 절대 repo/커밋 금지(`server/`는 스크립트만).
- 35B는 첫 응답 지연·발열 가능 → 네트워크 실패와 모델 지연을 **구분 표시**.

---

## 13. 완료 후 산출물 체크리스트
- [x] §2 게이트 8줄 통과 기록 (`plans/_gate.md`)
- [x] 단일 git repo(`app/ server/ docs/ plans/`)
- [x] **신규 생성**된 `PocketLlama` (빌드 통과 / 실기기 실행은 iOS 26.5 플랫폼 설치 후 — Phase 9, 환경 의존)
- [x] `server/serve.sh`(HOST 변형) + `test-anthropic.sh`
- [x] 연결 테스트(`/health`) + 에러 분류
- [x] 모델 표시(`/v1/models`) + fallback
- [x] **멀티턴** 채팅(비스트림 검증 → 스트림 본선) — `useStreaming` 토글로 양 경로
- [x] 스트리밍(`SSEDecoder`) + 상태머신(.connecting~.cancelled) + **Cancel**
- [x] 설정·최근 대화 유지
- [x] 보안 결정(권장 A: 무인증+경고, api-key 옵션) 반영

---

## 14. 결정 필요 항목
- [x] 앱 이름 — `PocketLlama` (2026-06-05)
- [x] Phase 1 전략 — **신규 생성**(리네임 금지)
- [x] **보안** — **권장 A 채택(무인증 LAN + README 경고)**. 구현: 무인증 기본 + 앱(SettingsView)·서버(`API_KEY`) api-key 옵션 제공. 옵션 B로 전환 시에만 §2 게이트 6번(헤더 형식 `x-api-key` vs `Bearer`) 실측 필요.
- [x] iOS 배포타깃 — 현재 `IPHONEOS_DEPLOYMENT_TARGET = 26.4`(기존 프로젝트 복제값). 더 낮은 기기 지원이 필요하면 pbxproj에서 하향 조정.
- [x] 루트 폴더명 `pocket-llama-lab`로 변경 완료(2026-06-05). 계획서/리뷰 파일명의 ollama 잔재 정리는 선택 미결.

---

## 15. 다음 액션
1. **Phase 0 게이트(§2) 실측** — `0.0.0.0` 기동 후 `/v1/messages` 비스트림+스트림, LAN `/health`. 통과 = Definition of Ready.
2. §5.4 마이그레이션 → Phase 1 신규 생성.

---

## 16. 리뷰 통합 판정 (두 문서 → 단일 SSOT)

`plans/swiftui-ollama-ios-mvp-plan-review.md`(Gemini)와 `...-review-grok.md`(Grok)를 본 계획서로 통합했다. 상충 지점 판정:

| 쟁점 | 판정 / 반영 위치 |
|---|---|
| Anthropic = 프록시 필수(404) [Gemini 위험1] | **과장.** llama-server 9430 네이티브 지원(README·`--reasoning`/`--jinja` 확인). 단 **§2 게이트로 실측 확정**. |
| Xcode 리네임 위험 → 신규 생성 [둘 다] | **채택.** §4.4·Phase 1 = 신규 생성(근거: `PBXFileSystemSynchronizedRootGroup`+타깃 26.4 확인). |
| 로컬 네트워크/ATS [둘 다] | **채택.** §8.3에 `NSAllowsLocalNetworking` 기본 포함·mDNS 예외. |
| `0.0.0.0` + `--api-key` [둘 다] | **채택(결정 항목).** §4.5·§6·§14. 헤더 형식은 실측 후 고정. |
| `.ingesting` 등 상태 세분화 [Gemini 위험5] | **채택.** §8.4 상태 머신. |
| `SSEDecoder` 버퍼 파서 [둘 다] | **채택(normative).** §7.4. (Gemini 코드의 다중 data 줄 join·`\r` 처리 보완) |
| 멀티턴 계약 누락 [Grok §3.3] | **채택.** §7.2 + Phase 6 완료기준 "2턴 이상". |
| 실행 순서 모순(§5.4 vs Phase 0) [Grok §3.1] | **해소.** §0 실행 순서 원칙 + Phase 0/0.5 분리. |
| test-client는 OpenAI만 [Grok §3.2] | **반영.** `server/test-anthropic.sh` + §2 게이트. |
| Phase 6 비스트림 UX 리스크 [Grok §4.3] | **반영.** Phase 6 = 검증용 최소 1회, UX 본선은 Phase 7. |
| 요청 취소/중복 [Grok §4.4] | **채택.** §8.5 Cancel = MVP 포함. |
| URL 정규화 / 에러 계약 / models 스키마 [Grok §4.5–4.7] | **채택.** §7.1·§7.6·§7.5. |
| `<think>` UI 필수(Phase 7) [Gemini 위험6] | **기각/하향.** `THINK=off` 기본 → 범위 밖, Phase 10(THINK=on일 때만). |
| 문서 드리프트 / 이식성 / 절전 [Grok §4.8–4.9·§5] | **채택.** §5.4·§5.3·§6. |
