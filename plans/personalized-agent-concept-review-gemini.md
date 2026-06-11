# 외부 엄중 리뷰 — Gemini (agy)

- 대상: `plans/personalized-agent-concept.md`
- 엄중도(rigor): max
- 집중 검토: iOS 사실성(UNCalendarNotificationTrigger repeats 폰닫힘 정시발화·알림탭 딥링크 SwiftUI 라우팅·시뮬레이터 알림검증 한계·무료 Apple ID 제약); tool-calling 타당성(llama.cpp /v1/messages tools 지원·PR #17570·Qwen3 chat template 버그·프롬프트 폴백 JSON 마커 스트리밍 파싱 함정·게이트 실측이 결정한다는 접근의 충분성); 날씨 소스(Open-Meteo 무키 vs 기상청 vs OpenWeatherMap·ATS https·한국 정확도·WeatherKit 제외 타당성); Tavily 키 주입(.env→Secrets.swift gitignore vs 설정화면 Keychain·시뮬레이터/실기기 안전성); 범위 적정성(YAGNI/누락·날씨한정 D6·백엔드보류 D7·브리핑-채팅 상태머신 충돌); 기존코드 정합(AnthropicChatClient tools 확장 시 raw-byte SSE 파서 충돌·ChatViewModel ChatState 머신에 브리핑/tool 라운드 통합)
- 생성: 2026-06-11 11:05:56 +0900

---

# PocketLlama 개인화 에이전트 컨셉 확정안(v1.1) 검토 보고서

## 1. 총평
본 컨셉 확정안은 로컬 알림을 통한 '벨'과 앱 진입 시 '실시간 생성'을 결합하여 무료 개발자 계정의 제약을 영리하게 회회하고 있으나, **iOS 런타임의 실제 생명주기와 llama-server의 SSE 스트리밍 스펙을 과소평가한 설계 결함**이 다수 발견되었습니다. 

특히, 기존의 SSE 스트리밍 파서와 뷰모델이 단방향 텍스트 수신만 고려하여 작성되어 있어, 이대로 구현을 시작하면 **도구 호출(Tool Calling) 발생 시 스트리밍 디코딩 크래시 또는 응답 먹통(무반응)이 발생하여 전체 에이전트 루프가 붕괴**됩니다. 또한, 사용자가 알림을 탭하고 들어왔을 때 이를 처리할 라우팅 메커니즘이 전혀 준비되어 있지 않아 실제 기기 환경에서의 기획 검증이 불가한 상태입니다.

---

## 2. Blocker (빌드 실패·런타임 오류·잘못된 전제)

### [Blocker 1] SSE 스트리밍 파서의 `tool_use` 디코딩 미지원 및 크래시 위험
*   **근거 위치**: 
    *   [AnthropicChatClient.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Services/AnthropicChatClient.swift#L125-L141) (`process` 함수 및 140줄 `// thinking_delta / 기타 이벤트는 무시`)
    *   [StreamChunk.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Models/StreamChunk.swift#L13-L22) (구조체 정의 전체)
*   **결함 내용**:
    *   현재 SSE 파서는 오직 `content_block_delta` 내의 `text_delta` 타입만 처리하며, 그 외의 이벤트는 버리도록 하드코딩되어 있습니다.
    *   llama-server의 Anthropic 호환 `/v1/messages` 스펙상 모델이 도구를 호출할 경우, 이벤트는 `content_block_start`(type: `tool_use`)로 시작하여 `content_block_delta`(delta.type: `input_json_delta`)를 통해 인자 JSON 데이터가 쪼개져서 수집됩니다.
    *   이대로 서버에 `tools` 파라미터를 실어 요청을 보내고 모델이 도구 호출을 시도할 경우, 앱의 SSE 파서는 `input_json_delta` 이벤트를 무시하여 **사용자 화면이 무반응 상태로 대기하거나 JSON 디코딩 에러가 나서 런타임 오류로 폭사**하게 됩니다.
    *   또한, `arguments` 데이터 형식이 llama.cpp 버전과 PR 리팩토링 여부에 따라 `String` 또는 `Object`로 혼들려 오는 회귀 현상(PR #20198)이 존재하여 이에 대한 방어적 역직렬화 대책이 없습니다.
*   **구체적 대안**: `StreamChunk`에 `content_block` 및 `input_json_delta` 필드를 추가하고, `AnthropicChatClient.swift` 내에 `tool_use` 인자 델타를 누적하는 버퍼를 신설해야 하며, `arguments`가 객체 또는 문자열일 때 모두 파싱 가능한 디코더(Failable/Dynamic Decoder)로 전면 개편해야 합니다.

### [Blocker 2] `ChatViewModel`의 단발성 `Task` 설계로 인한 멀티 라운드 도구 실행 불가
*   **근거 위치**:
    *   [ChatViewModel.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/ViewModels/ChatViewModel.swift#L70-L90) (`send()`의 비동기 Task 실행 흐름)
    *   [ChatState.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/ViewModels/ChatState.swift#L11-L17) (상태 머신 정의 전체)
*   **결함 내용**:
    *   현재 `ChatViewModel.send()`는 한 번의 스트리밍/비스트리밍 호출이 끝나면 즉시 상태를 `.idle`로 되돌리고 비동기 태스크를 소멸시킵니다.
    *   웹검색 도구 호출(Tavily)이 발화하려면 `[사용자 메시지] → [LLM: Tool Use 요청] → [App: Tavily API 검색] → [App: Tool Result 추가 전송] → [LLM: 최종 답변 생성]`이라는 최소 2라운드의 루프 제어 흐름이 필수적입니다.
    *   현재 뷰모델은 이 2차 전송과 최종 조율 흐름을 관리할 제어 루프가 전혀 없으며, `ChatState` 상태 머신에도 툴이 작동 중임을 알리는 상태(예: `.searching` 또는 `.executingTool`)가 없어 사용자에게 멈춘 것으로 인지되거나 비정상 상태 전이가 일어납니다.
*   **구체적 대안**: `send()` 태스크 내부를 최대 2회 제한의 루프 구조로 개편하여 도구 호출 응답 수신 시 비동기로 Tavily API를 실행한 후, `tool_result` 메시지를 컨텍스트에 덧붙여 2차 API 요청을 재귀적으로 실행하도록 수정하고, `ChatState`에 `.searching`을 신설해야 합니다.

---

## 3. Major (구현 중 반드시 보완해야 할 부분)

### [Major 1] 알림 탭(Notification Tap) 수신에 따른 SwiftUI 라우팅 메커니즘 부재
*   **근거 위치**:
    *   [PocketLlamaApp.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/PocketLlamaApp.swift#L10-L18) (앱 진입점)
    *   [RootView.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Views/RootView.swift#L11-L36) (라우팅 뷰 분기)
*   **결함 내용**:
    *   계획서([personalized-agent-concept.md:L42-L46](file:///Users/drlee/workspace/pocket-llama-lab/plans/personalized-agent-concept.md#L42-L46))는 아침 8시 로컬 알림 탭 시 날씨를 수집하고 브리핑 카드를 띄우는 시나리오를 정의하고 있습니다.
    *   그러나 현재 코드베이스에는 `UNUserNotificationCenterDelegate` 구현이 부재하며, 탭했을 때 어떤 화면으로 전환하거나 이벤트를 뷰모델로 전달할 라우팅 설계가 아예 유실되어 있습니다.
    *   이대로 구현하면 사용자가 알림 배너를 눌러도 그냥 일반 채팅 뷰가 뜰 뿐, 실시간 날씨 수집 및 브리핑 생성이 자동으로 시작되지 않습니다.
*   **구체적 대안**: `PocketLlamaApp.swift`에 `UIApplicationDelegateAdaptor` 혹은 `UNUserNotificationCenterDelegate`를 연동하여 알림 탭 이벤트를 캡처하고, 커스텀 URL Scheme 또는 SwiftUI `NavigationPath` 상태 제어를 통해 앱 진입 시 브리핑 트리거 메서드를 자동 호출하는 배선을 구축해야 합니다.

### [Major 2] 브리핑 카드 생성 시 기존 대화(Chat Session)와의 상태머신 충돌 및 히스토리 표류
*   **근거 위치**:
    *   [ChatViewModel.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/ViewModels/ChatViewModel.swift#L14-L29) (`messages` 배열 관리 및 세션 로드)
    *   [personalized-agent-concept.md](file:///Users/drlee/workspace/pocket-llama-lab/plans/personalized-agent-concept.md#L92) (범위 - 브리핑 카드 표시 후 채팅 이어가기)
*   **결함 내용**:
    *   `ChatViewModel`은 단일 `messages` 배열을 영속화하여 사용합니다. 기존 대화 기록이 쌓여 있는 상태에서 브리핑 생성이 트리거될 때의 정합성 처리가 유실되어 있습니다.
    *   만약 브리핑 생성이 기존 메시지 뒤에 단순히 추가되는 방식이라면, 슬라이딩 윈도우(`historyWindow = 12`)에 이전 사적 대화들이 포함되어 LLM이 브리핑 지시를 무시하고 엉뚱한 대화를 이어받는 형식 표류가 일어납니다.
    *   반대로 강제로 세션을 지우고 새 대화로 시작할 경우, 사용자의 기존 대화 히스토리가 백업 없이 소실됩니다.
*   **구체적 대안**: 브리핑 진입 시 기존 대화 기록을 명시적으로 백업/아카이빙한 뒤 세션을 비우거나, 시스템 프롬프트를 브리핑 전용 모드로 일시 전환하여 기존 대화 히스토리가 브리핑 생성 요청 컨텍스트에 침범하지 않도록 세션을 명확히 격리해야 합니다.

### [Major 3] Tavily API Key 주입 방식의 미확정 및 보안 공백
*   **근거 위치**:
    *   [personalized-agent-concept.md](file:///Users/drlee/workspace/pocket-llama-lab/plans/personalized-agent-concept.md#L103) (열린 결정 - Tavily 키 주입 방식)
*   **결함 내용**:
    *   `.env`를 빌드타임 스크립트로 `Secrets.swift`에 복사하는 방식은 실기기 배포 및 외부 사용자 실사용 시 API Key 변경이 불가능하게 만듭니다. 또한, 디컴파일에 의해 API Key가 평문 노출될 수 있어 보안상 안전하지 않습니다.
    *   반면 설정 화면 Keychain 보관은 안전하지만 자동 빌드/테스트 하네스에서의 동작 신뢰성을 별도로 보장해야 합니다. 이 결정을 "열린 결정"으로 모호하게 넘겨둔 것은 설계 공백입니다.
*   **구체적 대안**: Tavily API Key 주입 방식은 `SettingsView`에 입력 필드를 추가하고 iOS `Keychain`을 통해 안전하게 암호화 보관하며, 런타임에 동적으로 조회해 사용하는 방식으로 확정해야 합니다.

### [Major 4] llama-server의 Qwen3 템플릿 버그 및 KV 양자화 대책 미비
*   **근거 위치**:
    *   [personalized-agent-concept.md](file:///Users/drlee/workspace/pocket-llama-lab/plans/personalized-agent-concept.md#L104) (열린 결정 - tool-calling 방식)
    *   [research-personalized-agent-agentic-tools.md](file:///Users/drlee/workspace/pocket-llama-lab/plans/research-personalized-agent-agentic-tools.md#L61-L63) (Qwen3 chat template 버그 3종)
*   **결함 내용**:
    *   대상 모델(Qwen3.6-35B-A3B)의 Jinja 템플릿 결함으로 인해 `tools` 요청 시 500 오류가 나거나, `preserve_thinking` 옵션 누락 시 2턴 만에 이전 컨텍스트를 소실해 빈 인자 `{}`로 무한 도구 호출 루프에 빠지는 이슈가 이미 보고되어 있습니다.
    *   "게이트 실측 후 결정"으로 미루고 있으나, 네이티브 도구 호출 실패 시 대안인 '프롬프트 기반 폴백(JSON 마커)'은 스트리밍 중 토큰 단위(예: `[TO`, `OL_`, `USE]`)로 끊어 올 때의 가로채기(Interception) 로직이 대단히 까다로우며 이에 대한 클라이언트 측 파서 사양이 전무합니다.
*   **구체적 대안**: llama-server 기동 시 `--chat-template-file`로 패치된 Jinja 파일을 의무 주입하도록 서버 요구사양을 명시하고, 요청 본문에 `preserve_thinking: true`가 전달되도록 규정해야 합니다. 또한, 프롬프트 폴백용 Regex 파서 사양을 사전에 계획서에 기술해야 합니다.

---

## 4. Minor / 정합성

### [Minor 1] 로컬 네트워크 권한 거부 시 트러블슈팅 안내 누락
*   **근거 위치**:
    *   [Info.plist](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Info.plist#L5-L18) (`NSLocalNetworkUsageDescription` 및 ATS 설정)
    *   [AnthropicChatClient.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Services/AnthropicChatClient.swift#L222-L228) (`ClientError.notConnected` 맵핑)
*   **결함 내용**:
    *   `Info.plist`에 `NSAllowsArbitraryLoads`를 부여하여 Tailscale 등 사설 IP 접근을 ATS로부터 해제한 점은 훌륭합니다.
    *   다만, 사용자가 최초 실행 시 '로컬 네트워크 권한' 팝업을 거절할 경우 단순히 타임아웃이나 `ClientError.notConnected`가 반환되어 사용자는 단순히 "서버 다운"으로 오인할 가능성이 큽니다.
*   **구체적 대안**: `ChatState.failed` 상태 또는 에러 배너 노출 시, `notConnected` 에러에 대해서는 "아이폰 [설정] -> [PocketLlama] -> [로컬 네트워크] 권한이 켜져 있는지 확인해 주세요"라는 안내를 덧붙이도록 개선을 제안합니다.

### [Minor 2] 한국 날씨 정확도 제고를 위한 날씨 서비스 추상화
*   **근거 위치**:
    *   [personalized-agent-concept.md](file:///Users/drlee/workspace/pocket-llama-lab/plans/personalized-agent-concept.md#L101) (날씨 소스 결정 보류)
*   **결함 내용**:
    *   Open-Meteo는 API 키가 없고 무료여서 편리하지만, 국내 단기 예보 정확도는 기상청 공공 API에 비해 떨어집니다. 비가 오는 여부로 우산을 챙기라는 아침 비서 시나리오에서 부정확한 날씨 정보는 UX의 실용성을 완전히 파괴합니다.
*   **구체적 대안**: 날씨를 쿼리하는 클래스를 즉시 Open-Meteo 결합형으로 짜지 말고, `WeatherServiceProtocol`로 추상화하여 v0.1은 Open-Meteo로 신속 구현하되 향후 기상청 공공 API 서비스로 원활히 스위칭할 수 있도록 결합도를 낮춰 설계하십시오.

---

## 5. 검증한 사실 (실제로 확인한 파일 목록)

1.  **[personalized-agent-concept.md](file:///Users/drlee/workspace/pocket-llama-lab/plans/personalized-agent-concept.md)**
    *   **확인 내용**: 컨셉 확정안의 아키텍처 흐름 및 열린 결정 항목(날씨 소스, 키 주입, tool-calling 방식) 검토.
2.  **[AnthropicChatClient.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Services/AnthropicChatClient.swift)**
    *   **확인 내용**: SSE 스트림 바이트 디코더 작동 흐름 확인. `delta?.type == "text_delta"`만 허용하고 있어 다른 툴 호출 델타 유실 이슈 확인. ATS 에러 매핑 정책 확인.
3.  **[StreamChunk.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Models/StreamChunk.swift)**
    *   **확인 내용**: `Decodable` 구조체 내에 `tool_use` 관련 content block 디코딩 필드가 아예 유실되어 있는 사실 확인.
4.  **[ChatViewModel.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/ViewModels/ChatViewModel.swift)**
    *   **확인 내용**: `send()` 비동기 태스크가 단발성으로 종료되어 도구 실행 및 최종 답변 생성을 위한 2라운드 요청을 보낼 수 없는 구조적 문제 확인.
5.  **[ChatState.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/ViewModels/ChatState.swift)**
    *   **확인 내용**: 도구 실행 단계에 대응하는 진행 상태가 누락된 점 확인.
6.  **[PocketLlamaApp.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/PocketLlamaApp.swift) 및 [RootView.swift](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Views/RootView.swift)**
    *   **확인 내용**: 로컬 알림 탭 액션을 가로챌 `UNUserNotificationCenterDelegate` 또는 딥링크 라우터가 부재하여 알림 탭 시 브리핑 진입이 불가능한 한계 확인.
7.  **[Info.plist](file:///Users/drlee/workspace/pocket-llama-lab/app/PocketLlama/Info.plist)**
    *   **확인 내용**: `NSAllowsArbitraryLoads: true`를 통한 Tailscale 우회 적용 확인 및 `NSLocalNetworkUsageDescription` 메시지 존재 여부 확인.
8.  **[research-personalized-agent-agentic-tools.md](file:///Users/drlee/workspace/pocket-llama-lab/plans/research-personalized-agent-agentic-tools.md)**
    *   **확인 내용**: Qwen3 chat template의 Jinja 템플릿 크래시, `preserve_thinking` 유실 루프 이슈 검토.
