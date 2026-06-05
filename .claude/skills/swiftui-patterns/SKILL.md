---
name: swiftui-patterns
description: PocketLlama 앱의 표준 SwiftUI 구현 패턴 — Anthropic 호환 /v1/messages URLSession 클라이언트, SSE 스트리밍 파서, 멀티턴 계약, ChatState 상태머신, ClientError, base URL 정규화. SwiftUI/Swift 코드를 작성·수정할 때, 특히 네트워킹·스트리밍·채팅 화면·설정 구현 시 반드시 이 스킬을 따른다. swift-builder 에이전트의 1차 참조. 계획서 §4·§7·§8·§9의 normative를 코드로 고정한다.
---

# SwiftUI Patterns — PocketLlama 구현 표준

이 프로젝트의 모든 Swift 코드는 계획서(`plans/swiftui-ollama-ios-mvp-plan.md`)의 §7(API 계약)·§8(iOS 포인트)·§9(앱 구조)를 따른다. 이 스킬은 그 normative를 **재사용 가능한 코드 패턴**으로 고정해, 매번 계획서를 재해석하지 않게 한다. 골격 코드는 `references/swift-snippets.md`.

## 불변 규칙 (why 포함 — 어기면 런타임·계약 오류)
- **`max_tokens` 필수**: Anthropic `/v1/messages`는 `max_tokens`가 없으면 400. 모든 요청에 포함.
- **`model: "local"`**: llama-server 단일 모델 별칭(게이트에서 확인한 값). 하드코딩 회피하려면 `/v1/models`의 `data[0].id`를 쓰되 기본 `"local"`.
- **`content[0]`을 가정하지 말 것**: 응답 `content`는 블록 배열. `type == "text"`만 골라 합쳐라(THINK=on이면 `thinking` 블록이 먼저 올 수 있음).
- **base URL 정규화**: 사용자는 base만 저장(`http://192.168.0.10:8080`). 클라이언트가 경로를 조립한다 — 끝 슬래시 제거, 실수로 들어온 `/v1/messages` 잘라냄, 그 위에 `/v1/messages`·`/health`·`/v1/models` 합성. (계획서 §7.1)
- **SSE는 버퍼 파서로**: 줄 단위 단순 처리는 이벤트 경계(`\n\n`)·다중 `data:`·`\r\n`에서 깨진다. `SSEDecoder`(빈 줄 flush, 다중 data는 `\n` join, 끝 `\r` 제거)를 쓴다. (계획서 §7.4)
- **멀티턴**: UI 메시지 배열을 `messages`에 user/assistant 교대로 전송. 히스토리 `content`는 문자열로 단순화. 길면 최근 N(예: 12) 슬라이딩 윈도우. (계획서 §7.2)

## 핵심 컴포넌트 (계획서 §9 구조)
| 컴포넌트 | 표준 |
|---|---|
| `LLMChatClient`(protocol) | `send`/`stream`/`health`/`models`. `AnthropicChatClient`가 구현. Phase 10 OpenAI 대비 추상화(§4.6) |
| `AnthropicChatClient` | `URLSession`. 비스트림 `data(for:)`, 스트림 `bytes(for:)`+`SSEDecoder`. 헤더 `Content-Type`/`anthropic-version`/(옵션)`x-api-key` |
| `Models` | `MessagesRequest`/`MessagesResponse`/`StreamEvent`(Codable), `ChatMessage`, `ClientError` |
| `ChatViewModel` | `ChatState` 머신 + 메시지 배열 + 취소. `@MainActor`로 UI 갱신 |
| `AppSettingsStore` | base URL(+선택 API Key) `UserDefaults` |
| Views | `RootView`/`SettingsView`/`ModelInfoView`/`ChatView`(입력+Cancel) |

## 상태머신 (계획서 §8.4)
`ChatState`: `.idle` / `.connecting` / `.ingesting`("맥북이 프롬프트 분석 중…") / `.generating` / `.cancelled` / `.failed(ClientError)`. 단순 로딩 불리언 금지 — 35B TTFT가 길어 "멈춘 듯" 오해를 부른다.

## 취소·중복 방지 (계획서 §8.5)
Cancel 버튼은 MVP 포함. `URLSessionTask.cancel()` → `.cancelled`. 전송 중 버튼 비활성화 + 디바운스, in-flight 1개만.

## 동시성·관찰
- `async/await` 우선. 네트워크는 백그라운드, UI 갱신은 `@MainActor`.
- iOS 17+면 `@Observable` 매크로 권장(계획서 §8.1 최소 타깃). 미만이면 `ObservableObject`+`@Published`.
- 스트림 수신 중 `Task`로 취소 가능하게 보관.

## 안티패턴 (하지 말 것)
- `max_tokens` 누락 / `content[0].text` 직접 접근 / `bytes.lines`만으로 SSE 파싱(버퍼 없이) / base URL에 `/v1` 중복 / 동기 블로킹 네트워크 / 단일 `isLoading` 불리언으로 상태 표현.

## ATS·권한 (계획서 §8.2~8.3)
- `Info.plist`: `NSLocalNetworkUsageDescription` + `NSAllowsLocalNetworking=YES` 기본 포함. 권한 팝업은 "연결 테스트" 동작에 연결.

## 더 보기
- 실제 골격 코드(복붙 시작점): `references/swift-snippets.md`
- 계약 원본·심화: 계획서 §7(요청/응답/SSE/에러), §8(iOS), §9(구조)
