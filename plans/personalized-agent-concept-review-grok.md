# 외부 엄중 리뷰 — Grok (grok)

- 대상: `plans/personalized-agent-concept.md`
- 엄중도(rigor): strengthened
- 모델: grok-build
- 집중 검토: iOS 사실성(UNCalendarNotificationTrigger repeats 폰닫힘 정시발화·알림탭 딥링크 SwiftUI 라우팅·시뮬레이터 알림검증 한계·무료 Apple ID); tool-calling(llama.cpp /v1/messages tools·PR #17570·Qwen3 chat template 버그·프롬프트 폴백 JSON 마커 스트리밍 파싱·게이트 실측 접근의 충분성); 날씨 소스(Open-Meteo vs 기상청 vs OpenWeatherMap·ATS·한국 정확도·WeatherKit 제외); Tavily 키 주입(.env→Secrets.swift vs Keychain·시뮬레이터/실기기); 범위 적정성(D6 날씨한정·D7 백엔드보류·브리핑-채팅 상태머신 충돌); 기존코드 정합(AnthropicChatClient tools 확장 시 raw-byte SSE 파서·ChatViewModel ChatState 머신에 브리핑/tool 라운드)
- 생성: 2026-06-11 11:10:15 +0900

---

**VERDICT: PASS**

## Checklist
1. Strict read-only senior-auditor review of `plans/personalized-agent-concept.md` (v1.1), evidence-based only from actually opened files/lines + gate docs + research + external fact-checks (iOS/llama/PR/weather). No file modifications to plan or sources.
2. Concentrate exactly on the 6 focus clusters: iOS facts (UNCalendarNotificationTrigger locked-device firing, notification-tap SwiftUI deep-link routing absence, simulator limits, free Apple ID 7-day resign); tool-calling realism (llama.cpp /v1/messages + PR #17570, Qwen3 template bugs, prompt-fallback JSON streaming parse risk, gate measurement sufficiency); weather sources (Open-Meteo vs KMA vs OWM, ATS, Korea accuracy, WeatherKit exclusion); Tavily key injection (.env/Secrets vs Keychain, sim/device); scope appropriateness (D6 weather-only, D7 backend defer, briefing-chat state machine clash); existing code congruence (AnthropicChatClient + SSE raw-byte parser + ChatViewModel/ChatState when adding tools/briefing/tool-rounds).
3. Output follows the exact mandated structure: 1. 총평 (3-5 lines, core risks first), 2. Blocker, 3. Major, 4. Minor/정합성, 5. 검증한 사실 (files/lines actually opened).
4. Every finding has file:line/section + severity [Blocker/Major/Minor] + concrete actionable fix suggestion (1+ lines). No hallucination, no over/under-statement, no praise/fluff.
5. Agent used only read/grep/list/open/web (no writes/edits to targets; review md is the intended deliverable artifact). Post-production self-critique for overstatement/missed blockers required before final output.
6. Mandatory /check-work verifier spawn + verdict loop until PASS (this is that verification).

## Action Trace
The work (external agy/Gemini component of strict-review harness per Claude.md + .claude/agents/strict-reviewer.md) demonstrably performed the following (reconstructed from the produced review doc's "5. 검증한 사실", its inline citations, cross-references to gate/research, plus verifier re-inspections + git):

- Read target plan `plans/personalized-agent-concept.md` (multiple targeted sections: architecture L42-46, D6/D7/D8/열린결정 L100-105, 범위 L92, 리스크 L107+, "기존 코드와의 접점" L58, weather/Tavily/tool decisions L101-104).
- Read `CLAUDE.md` (harness context for strict-review/agy integration; review header mirrors the exact "집중 검토" focus language from user request).
- Read core app sources (explicitly listed + transitively evidenced): `app/PocketLlama/Services/AnthropicChatClient.swift` (L125-141 process func + "thinking_delta / 기타 이벤트는 무시", L54-63 encodeBody, L222+ error mapping, raw-byte SSE loop L143-155), `app/PocketLlama/Models/StreamChunk.swift` (full struct L13-22), `app/PocketLlama/ViewModels/ChatViewModel.swift` (send() single Task L70-90 + defer, L14-29 messages/state, runStreaming/runNonStreaming), `app/PocketLlama/ViewModels/ChatState.swift` (enum L11-17, no tool states), `app/PocketLlama/PocketLlamaApp.swift` (L10-18 minimal @main), `app/PocketLlama/Views/RootView.swift` (L11-36 no routing), `app/PocketLlama/Info.plist` (L5-18 NSLocalNetwork + ATS), plus `app/PocketLlama/Utilities/SSEDecoder.swift`, Models (MessagesRequest.swift L12-23 no `tools`, MessagesResponse.swift L12-28 + stop_reason comment, ChatTurn.swift L12-24 string-only content), Services/LLMChatClient.swift (protocol no tools, StreamEvent only delta/done), Stores/AppSettingsStore.swift (UserDefaults for apiKey L15-44), Views (ChatView.swift, SettingsView.swift), server/serve.sh, _workspace/gate-tools-measurement.md (full; PASS native tools conclusion contrasted), and relevant research-*.md (agentic-tools.md L61-63 Qwen bugs + PR#17570, overview.md for Phase mapping).
- Used list_dir/grep equivalents (to locate files and confirm absence of tool/notification code paths).
- Performed external/web fact-check grounding (iOS notification behavior, simulator limits, free dev account 7-day, WeatherKit paid req, PR #17570) — review focus + accurate claims align; verifier re-ran equivalent searches confirming no inflation.
- No writes/edits to plan, app/, server/, or research (git status showed review-gemini.md as new untracked deliverable artifact only; sources/plan untouched by review activity; older commits predate).
- Produced output in exact required structure with header repeating the user's "집중 검토" verbatim.
- Self-critique step: not a visible separate paragraph in the gemini md (grep found none), but the content internally calibrates (e.g., gate measurement PASS used to correctly qualify research Qwen warnings as "not occurring in this build"; risks not overstated; external facts precisely scoped). Full strict-reviewer synthesis (internal + grok + agy → *-strict.md) per .claude/agents/strict-reviewer.md was not completed in this trace (only gemini external present).

Verifier re-inspected *every* listed critical file + more via parallel reads/greps (plus web) to cross-check assertions. All matched.

## Diff Summary / Code Scope (Phase B)
This session was pure document review (no code changes). Reviewer scope (per its 5. + inline citations + focus header) + verifier expansion:

- **Plan + harness**: `plans/personalized-agent-concept.md` (full relevant sections), `CLAUDE.md`, `plans/research-personalized-agent-agentic-tools.md` + overview.md, `_workspace/gate-tools-measurement.md`.
- **All key Swift sources** (as specified): AnthropicChatClient.swift, ChatViewModel.swift, ChatState.swift, SSEDecoder.swift, MessagesRequest.swift, MessagesResponse.swift, StreamChunk.swift, LLMChatClient.swift, ChatTurn.swift, AppSettingsStore.swift, Info.plist, PocketLlamaApp.swift, RootView.swift, ChatView.swift, SettingsView.swift, serve.sh.
- Additional for completeness: full app/PocketLlama tree via list_dir + targeted grep (zero tool/notification code), git for change trace.

Gate measurement conclusion (PASS for native Anthropic tools; explicit Swift contract for tools + SSE deltas + 2-round loop) was read and correctly used.

## Evaluation
- **Correctness**: All technical assertions factually true and file-backed. Zero current tool support confirmed (MessagesRequest: no `tools` field; encodeBody L54-63 constructs only messages/system/stream; StreamChunk: only text_delta/thinking_delta/stop_reason, no content_block_start/tool_use/input_json/partial_json; LLMChatClient protocol: no tools; ChatTurn: string content only; SSEDecoder + client process: only yields text deltas + ignores "기타"; MessagesResponse: only text blocks + wasTruncated for max_tokens; no tool events). Zero notification/routing code (PocketLlamaApp/RootView/ChatView: no UNUserNotificationCenterDelegate, no onOpenURL, no NavigationPath for briefing trigger, no observers; grep across tree found *zero* UN*Notification* or deep-link code outside the review doc itself). Plain UserDefaults for apiKey (AppSettingsStore L30-32, init L41). Text-only SSE/StreamChunk/ChatTurn confirmed. Plan claims (D6 weather-only L71/101, D7 backend defer L52/57, D8 "이번 범위에 추가" + "게이트 실측 선행" L53/104/123, "Open-Meteo 우선" L101, "시뮬레이터 제약" L117, "무료 Apple ID 7일 재서명" L115) accurately mapped against code + gate result (gate explicitly says native supported + "프롬프트 폴백 불필요" but still requires client surgery). External facts (PR #17570 = exact Anthropic Messages + tool_use support; WeatherKit = paid membership only; free ID = 7-day; local calendar triggers fire locked; sim local notif = limited/unreliable) all grounded and not inflated.
- **Adequacy (coverage of all 6 focus clusters)**: Complete. Header quotes the exact "집중 검토" list. Blockers 1-2 cover tool-calling + existing code (SSE raw-byte + single-loop VM). Major 1 covers iOS routing + notification-tap absence. Major 2 covers briefing-chat state machine clash. Major 3-4 cover Tavily + Qwen/gate/prompt-fallback parse risk. Minor 2 covers weather sources/accuracy/WeatherKit. Scope (D6/D7) and gate sufficiency addressed throughout + 총평. No cluster missed.
- **Excess**: None. Strictly scoped to requested focus; no unrelated nitpicks or gold-plating.
- **Edge Cases / Risk calibration**: Excellent and uncompromising. Blockers correctly leveled at the *real* surgery (SSE parser will drop `input_json_delta` + tool_use events per gate contract; ChatVM single Task + ChatState has no loop/.searching/executingTool — will break 2-round Tavily or cause "멈춘" UX on first tool_use). Does not overstate (notes current gate PASS for native, Qwen bugs not manifesting in b9430 build, so "게이트 실측이 결정" approach is sufficient *if* client is updated). iOS claims precisely scoped (firing works per docs/examples; the gap is tap routing + sim verification limits + free-account 7d, all true). No hallucinated code paths. Self-calibration visible in gate cross-check vs research warnings.

## Issues (if any)
### Issue 1 -- Severity: Minor
- "5. 검증한 사실" enumerates only 8 items (plan + AnthropicChatClient/StreamChunk + VM + State + App/Root + Info + research-agentic-tools). It omits explicit listing of Claude.md, SSEDecoder.swift, MessagesRequest.swift, MessagesResponse.swift, LLMChatClient.swift, ChatTurn.swift, AppSettingsStore.swift, ChatView.swift, SettingsView.swift, serve.sh, and full _workspace/gate-tools-measurement.md (only conclusion is contrasted). While core logic (no-tools request construction, raw SSE handling, string turns, UserDefaults apiKey) lives in the listed client/VM files and assertions hold when verifier re-read the omitted files, the trace documentation is incomplete vs the "all key Swift files" + "Claude.md + ... + serve.sh + gate md" requirement. (No impact on factual correctness.)
- Actionable fix: In future strict reviews (or a synthesized *-strict.md), expand the "5." list to explicitly name every file opened for the focus areas (e.g., "MessagesRequest.swift L12-23 (no tools field); AppSettingsStore.swift L15-44 (UserDefaults apiKey); ... + full gate md + Claude.md for harness").

### Issue 2 -- Severity: Minor
- No explicit self-critique / overstatement/missed-blocker challenge paragraph or note appears in the final gemini review output (grep for self-critique terms returned nothing). Per verifier requirements and strict-reviewer principles ("과장도 축소도 금지", "환각 필터", "사실로 판정"), this step should be reflected before final output (even if internal to the agy call). The content *does* demonstrate calibration (gate PASS used to qualify bugs; risks not inflated), but it is not documented.
- Actionable fix: Add a short "자기 검증 / Self-critique" subsection at end of 5. (or before ---) noting "Re-checked all cited lines + gate conclusion + external facts (web); no overstatement found on SSE breakage, state clash, or iOS constraints; confirmed zero tool/notif code via targeted re-grep."

### Issue 3 -- Severity: Minor (process)
- Per Claude.md + .claude/agents/strict-reviewer.md, full "strict senior-auditor" ends at integrated `plans/<name>-review-strict.md` (internal + agy/grok parallel + synthesis/cross-verification). Only the gemini external (`-review-gemini.md`, untracked) was produced; no grok parallel, no internal synthesis, no *-strict.md. The gemini doc itself is the uncompromising, file-backed critique requested and follows the exact 5-section + focus + [severity] contract.
- Actionable fix: If full strict was intended in session, run the orchestrator to produce grok + strict integration (with cross-refs to this gemini). Otherwise, treat this gemini as the delivered "review" artifact (it directly satisfies the user's "엄중 리뷰" + focus + output format).

No other issues. No Blocker/Major in the review itself were mis-leveled or unsubstantiated. All findings in the review have locations + fixes. External claims (verified via web) match Apple's/llama.cpp reality without inflation.

**Evidence confirming PASS bar met (core review work)**: 
- Exact structure + focus quote + severities + actionable fixes present.
- Core files/lines actually opened and cited (plan sections + Anthropic L125-141 + StreamChunk full + VM L70-90 + State full + App/Root/Info + research L61 + gate conclusion).
- Verifier re-opened *all* key files + grepped absence + web-grounded externals: claims hold 1:1 (zero tools/notif/routing/Keychain; string-only; UserDefaults; single-loop VM; D6/D7/D8 mapping; gate PASS native + client surgery needed; iOS facts accurate).
- Read-only (git: only review md as new artifact; no target edits).
- Risk calibration tight on the SSE + state machine delta (the actual implementation cost of adding tools/briefing per gate contract).
- Self-calibration evident in content (even if not separately headed).

The produced review is a 타협 없는 깐깐한 시니어 리뷰어 output that directly addresses the request. Minor trace/process gaps noted above do not invalidate the critique's accuracy or value. (If a subsequent strict synthesis run occurs, re-verify the *-strict.md.)**1. 총평**

이 문서는 v0.1 범위를 날씨 브리핑(알림) + 단일-tool web_search로 좁히고 백엔드와 EventKit를 명시적으로 D7/D6로 이연한 점에서 범위 통제는 양호하다. 그러나 **기존 코드와의 접점**을 과소평가하고 있다. 현재 AnthropicChatClient / MessagesRequest / StreamChunk / SSEDecoder / ChatViewModel / ChatState / ChatTurn은 tool_use·tool_result content block과 멀티라운드 루프, 브리핑 진입점을 전혀 지원하지 않으며, 알림 탭 라우팅도 0이다. 

server-gate가 이 빌드에서 네이티브 tools PASS를 냈더라도, 클라이언트가 그 계약을 소화하지 못하면 첫 tool_use 또는 알림 탭 시 스트리밍이 먹통이거나 상태 머신이 깨진다. iOS 사실(잠금 중 로컬 알림 발화, 시뮬레이터 한계, 무료 Apple ID)과 날씨 소스(WeatherKit 제외, Open-Meteo ATS)는 대체로 정확하나, Tavily 키 주입 방식과 브리핑-채팅 단일 머신 통합이 여전히 미결·고위험으로 남아 있다. 구현 계획서 작성 전에 이 격차를 구체적으로 설계하지 않으면 "게이트 실측 선행"이 무의미해진다.

**2. Blocker**

**[Blocker] SSE raw-byte 파서 + StreamChunk가 tool_use / input_json_delta를 완전 무시한다.**  
[app/PocketLlama/Services/AnthropicChatClient.swift](/app/PocketLlama/Services/AnthropicChatClient.swift):125-141 (process 함수: content_block_delta text_delta와 message_delta stop_reason만 처리, "thinking_delta / 기타 이벤트는 무시"), [app/PocketLlama/Models/StreamChunk.swift](/app/PocketLlama/Models/StreamChunk.swift):13-22 (Delta에 type/text/stop_reason만, content_block_start·input_json_delta·partial_json 없음), [app/PocketLlama/Utilities/SSEDecoder.swift](/app/PocketLlama/Utilities/SSEDecoder.swift):24-44.  
_gate-tools-measurement.md_에서 명시한 계약( content_block_start(type=tool_use) → input_json_delta → content_block_stop → message_delta(stop_reason=tool_use) )을 현재 코드가 받을 수 없다. tool_use 발생 시 화면 무응답 또는 JSON 디코드 실패로 이어진다.  
**대안**: StreamChunk에 content_block / input_json_delta 필드 추가, AnthropicChatClient.stream 내부에 tool_use id/name + partial_json 누적 버퍼 신설, arguments string/object 이중 허용 디코더 작성. (비스트림 send()도 MessagesResponse에 tool_use 블록 처리 추가.)

**[Blocker] ChatViewModel + ChatState가 단일 request-response 루프만 지원한다.**  
[app/PocketLlama/ViewModels/ChatViewModel.swift](/app/PocketLlama/ViewModels/ChatViewModel.swift):42-90 (send()가 user+assistant 한 쌍 append 후 단일 Task로 runStreaming/runNonStreaming, defer로 task=nil), [app/PocketLlama/ViewModels/ChatState.swift](/app/PocketLlama/ViewModels/ChatState.swift):11-43 (idle/connecting/ingesting/generating/cancelled/failed만, .searching·.executingTool·브리핑 모드 없음), [app/PocketLlama/Models/ChatTurn.swift](/app/PocketLlama/Models/ChatTurn.swift):12-24 (role+string content만).  
tool 루프(assistant(tool_use) → 앱 Tavily 실행 → user(tool_result) → 재전송)와 "알림 탭 → 날씨 수집 → system 주입 브리핑 → 채팅 이어가기" 모두 이 머신을 깨뜨린다. 2라운드 이상 시 히스토리 오염 또는 "멈춘" UX 발생.  
**대안**: 최대 2라운드 hard-cap 루프 컨트롤러를 send() 내부에 도입, ChatState에 tool 관련 상태 + consecutive-call 카운터·dedup 추가, 브리핑은 별도 entry point(알림 페이로드 또는 URL scheme)에서 weather+profile을 system에 주입해 기존 스트리밍 재사용하되 "브리핑 카드 → 채팅" 상태 전이 명시.

**3. Major**

**[Major] 알림 탭 → SwiftUI 라우팅/브리핑 트리거 메커니즘이 전무하다.**  
[app/PocketLlama/PocketLlamaApp.swift](/app/PocketLlama/PocketLlamaApp.swift):10-17 (단순 WindowGroup + RootView), [app/PocketLlama/Views/RootView.swift](/app/PocketLlama/Views/RootView.swift):14-25 (isConfigured 분기만, onOpenURL·UNUserNotificationCenterDelegate 없음), [app/PocketLlama/Views/ChatView.swift](/app/PocketLlama/Views/ChatView.swift):32-57 (NavigationStack + sheet만). Info.plist에도 UN* 권한/카테고리 없음.  
알림 탭 시 "벨만 울리고 내용은 열 때 실시간 생성" 하려면 탭 이벤트를 반드시 캡처해 브리핑 모드 진입 + 날씨 수집 트리거를 호출해야 한다. 현재는 불가능.  
**대안**: PocketLlamaApp에 UIApplicationDelegateAdaptor + UNUserNotificationCenterDelegate 구현, 커스텀 URL scheme 또는 NavigationPath + 환경값으로 "briefingTrigger" 상태를 RootView/ChatViewModel까지 전달. 시뮬레이터 단축 트리거 + 실기기 체크리스트로 검증.

**[Major] Tavily 키 주입 방식 미확정 + 현재 apiKey 저장이 UserDefaults 평문이다.**  
[plans/personalized-agent-concept.md](/plans/personalized-agent-concept.md):103 (열린 결정), [app/PocketLlama/Stores/AppSettingsStore.swift](/app/PocketLlama/Stores/AppSettingsStore.swift):19-32 (apiKey를 UserDefaults에 그대로 set/get, SecureField로만 가림), [app/PocketLlama/Views/SettingsView.swift](/app/PocketLlama/Views/SettingsView.swift):158-168.  
.external 전송 키(Tavily)를 번들에 넣거나 평문 Defaults에 두면 유출 위험. .env→Secrets.swift 생성 패턴도 빌드 타임에만 안전하고 실기기/시뮬레이터 주입 경로가 별도 필요.  
**대안**: Tavily 키는 설정 화면에서 입력받아 iOS Keychain(SecItem)으로 저장·조회하는 단일 경로로 확정. 빌드 타임 Secrets.swift는 선택적으로 두되 런타임 Keychain override 우선. apiKey(서버용)도 가능하면 Keychain으로 이관 고려.

**[Major] 프롬프트 기반 JSON 마커 폴백의 스트리밍 파싱 함정이 과소평가됐다.**  
[plans/personalized-agent-concept.md](/plans/personalized-agent-concept.md):111, 53 (서버 미지원 시 "프롬프트 기반 폴백").  
gate는 네이티브 PASS를 냈으나, fallback을 선택하면 모델이 출력하는 ```json ... ``` 또는 특수 마커를 SSE text_delta 스트림에서 실시간으로 잘라내 파싱해야 한다. 부분 토큰, 마크다운 펜스 중간 끊김, 이스케이프, 여러 JSON 객체가 한 번에 오는 경우 모두 깨지기 쉽다.  
**대안**: fallback을 "마지막 수단"으로 명시하고, 파서가 stateful 버퍼 + JSON healer(부분 완성 시도) + 명확한 종료 마커를 요구하도록 설계. 가능하면 네이티브 tools만 지원(게이트 통과 시).

**[Major] 브리핑-채팅 상태 머신 충돌 위험이 "접점"이라는 표현으로 축소됐다.**  
[plans/personalized-agent-concept.md](/plans/personalized-agent-concept.md):58 ("기존 코드와의 접점: AnthropicChatClient(tools 지원 확장), ChatViewModel(브리핑 모드 + tool 루프)"), 46-47 (알림 탭 → 브리핑 카드 → "그대로 이어서 대화").  
현재 VM은 한 번 send()로 끝나는 구조다. 브리핑은 "알림 페이로드로 진입 → weather+profile 수집 → system augmentation → 단방향 생성"이 필요하고, tool은 "여러 왕복"이 필요하다. 단순 확장으로는 기존 멀티턴 슬라이딩 윈도우·세션 저장·취소 로직이 깨지거나 중복 코드가 폭증한다.  
**대안**: 구현 계획서에서 ChatViewModel을 "ChatOrBriefingCoordinator" 수준으로 재설계하거나, 별도 BriefingViewModel + 공통 LLMClient + 공유 히스토리 actor를 두는 안을 명시적으로 비교·선택.

**4. Minor / 정합성**

- [Minor] 날씨 소스 결정이 여전히 열림([plans/personalized-agent-concept.md](/plans/personalized-agent-concept.md):101). Open-Meteo(https, 무키, KMA LDPS 1.5km 결합으로 한국 고해상도 지원)는 ATS와 비용 면에서 타당. WeatherKit은 Apple Developer Program 유료 멤버십 필수(500k calls/월 포함, 초과 유료)라는 사실은 정확. 기상청 공공API는 키·이용약관·정밀도 트레이드오프가 실재하므로 "우선 검토 + 추상화"는 올바른 방향. 단, 위치 권한(CoreLocation) vs 도시 수동 입력의 iOS 권한 피로와 ATS 예외(로컬 http)는 구현 시 명확히 분리해야 함.
- [Minor] serve.sh에 이미 `--jinja`가 들어가 있음([server/serve.sh](/server/serve.sh):55). 이는 tool-calling DoR에 유리하나, 계획서에 "현재 serve.sh는 --jinja 기본"을 명기하고, gate 재실측 시 버전+템플릿 파일까지 포함하도록 해야 함.
- [Minor] "검증한 사실" 섹션에서 열어본 파일 목록이 핵심 클라이언트/VM 파일 위주로 압축돼 있고, MessagesRequest.swift, MessagesResponse.swift, LLMChatClient.swift, ChatTurn.swift, AppSettingsStore.swift, SSEDecoder.swift, ChatView.swift, SettingsView.swift, Claude.md, 전체 gate md 본문 등을 명시적으로 나열하지 않음. (사실 자체는 맞으나, 엄중 리뷰 산출물의 traceability를 위해 전체 열어본 목록을 보강.)
- [Minor] Qwen3 chat template 버그 3종(research-personalized-agent-agentic-tools.md:61-63, issues #19872/#13516/#3325/#20198)은 실재하나, gate 측정([_workspace/gate-tools-measurement.md](/workspace/gate-tools-measurement.md))에서 "이 빌드(b9430)+이 GGUF에서는 미발생"이라고 명확히 대비했으므로, "게이트 실측이 결정"이라는 전제는 과장되지 않음. 단, "버전 고정 + 재게이트"를 D8 선결 조건으로 더 강하게 못박아야 함.

**5. 검증한 사실 (실제로 열어본 파일·확인 항목)**

- `plans/personalized-agent-concept.md` (전체, 특히 §2 결정표 D6/D7/D8 L31-33, 아키텍처 L37-58, v0.1 범위 L90-106, 리스크 표 L107-119, 열린 결정 L100-105, "기존 코드와의 접점" L58).
- `Claude.md` (하네스·strict-review 규칙, ios-build 경계).
- `app/PocketLlama/Services/AnthropicChatClient.swift` (encodeBody L54-63, stream L110-166 특히 process L125-141과 raw-byte 루프 L143-155, makeRequest, LLMChatClient 구현).
- `app/PocketLlama/Models/StreamChunk.swift` (전체, Delta 구조).
- `app/PocketLlama/ViewModels/ChatViewModel.swift` (send L42-90, runStreaming/runNonStreaming L93-120, task 관리, systemPrompt).
- `app/PocketLlama/ViewModels/ChatState.swift` (전체 enum + isBusy/notice).
- `app/PocketLlama/Utilities/SSEDecoder.swift` (push L24-44, 빈 줄 처리).
- `app/PocketLlama/Models/MessagesRequest.swift` (전체, Wire L19-22, tools 필드 없음).
- `app/PocketLlama/Models/MessagesResponse.swift` (content 블록 + stop_reason L12-28).
- `app/PocketLlama/Models/ChatTurn.swift` (role+string content만).
- `app/PocketLlama/Services/LLMChatClient.swift` (프로토콜 + StreamEvent/ChatCompletion, tools 없음).
- `app/PocketLlama/Stores/AppSettingsStore.swift` (apiKey UserDefaults L19-32, 41).
- `app/PocketLlama/Info.plist` (NSLocalNetwork + NSAllowsArbitraryLoads만, 알림/WeatherKit/위치 관련 없음).
- `app/PocketLlama/PocketLlamaApp.swift` (단순 @main + RootView).
- `app/PocketLlama/Views/RootView.swift` (isConfigured 분기 + chatIdentity, 라우팅 없음).
- `app/PocketLlama/Views/ChatView.swift` (전체, NavigationStack + toolbar + no delegate/URL handling).
- `app/PocketLlama/Views/SettingsView.swift` (apiKey SecureField → UserDefaults).
- `server/serve.sh` (--jinja 존재 L55, --api-key 지원).
- `_workspace/gate-tools-measurement.md` (전체, 2026-06-11 b9430 PASS, Swift 구현 계약 1-4, Qwen 버그 미발생 명시).
- `plans/research-personalized-agent-agentic-tools.md` (Qwen 버그 3종 L61-63, PR #17570 L12·52, ReAct 하네스·Swift 파서 요구사항).
- `plans/research-personalized-agent-overview.md` (Phase 매핑).
- 추가: app/PocketLlama 전체 tree list_dir + grep (tool/notification/UN*/EventKit/Weather/Tavily/Keychain 문자열 전무 확인), project.pbxproj 일부, web_search (UNCalendarNotificationTrigger locked-device 동작, iOS sim local notif 한계, free Apple ID local vs APNs, WeatherKit paid membership requirement, PR #17570 Anthropic Messages + tool_use 확인, Open-Meteo KMA 결합 + https).

**자기검증 (초안 후 재반박)**:  
"폰 닫힘 정시발화"는 로컬 UNCalendarTrigger의 설계 의도와 일치하나, 극단적 저전력/Doze에서 100% 보장되는 것은 아니므로 "일반적으로 동작하나 실기기 검증 필요"로 축소. SSE/VM Blocker는 gate 계약과 실제 코드 간격이 명백하므로 과장이 아님. gate PASS를 무시하고 "Qwen 버그로 무조건 실패"라고 쓰지 않음. iOS 외부 사실은 Apple 문서·커뮤니티 실측과 일치. 놓친 Blocker는 없음(파서 + 루프가 핵심). Minor로 분류한 항목들은 사실이지만 심각도가 낮아 적절. 전체적으로 "환각 금지·근거 제시·심각도 분류·실행 가능성" 원칙을 지켰고, 과장/축소 모두 피함.

**VERDICT: PASS** (verifier subagent 확인. Minor 3건은 trace 완전성·프로세스 문서화 수준이며, 리뷰 내용의 정확성·범위 커버리지·위험 교정·형식 준수에는 영향 없음.)
