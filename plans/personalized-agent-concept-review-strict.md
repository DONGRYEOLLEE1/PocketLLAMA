# PocketLlama 개인화 에이전트 컨셉(v1.1) — 통합 엄중 리뷰

- 리뷰일: 2026-06-11
- 대상: `plans/personalized-agent-concept.md` (v1.1, 2026-06-11 갱신)
- 입력: 내부(Claude, 코드·게이트·리서치 직접 검증) + 외부(grok=grok-build, agy=Gemini)
- 외부 원본: `plans/personalized-agent-concept-review-grok.md` · `plans/personalized-agent-concept-review-gemini.md`
- 엄중도: max (grok는 model 제약으로 strengthened로 하향 — 아래 ⑥ 참조)
- 모드: 초기(이 대상에 대한 기존 리뷰 없음)
- 교차참조: 현 코드 `app/PocketLlama/`(전체 Swift 소스 + Info.plist + pbxproj), `_workspace/gate-tools-measurement.md`(게이트 실측), `server/serve.sh`, 리서치 5종, `CLAUDE.md`

---

## ① 총평 + Go / No-Go

**판정: 조건부 Go (Conditional Go).** 컨셉의 **방향·범위 통제는 타당**하다 — v0.1을 날씨 브리핑 + 단일 tool(web_search)로 좁히고 EventKit(D6)·백엔드(D7)를 명시적으로 이연한 것은 YAGNI에 맞다. "벨/내용 분리"(D3)로 무료 Apple ID·iOS 백그라운드 제약을 우회한 설계도 iOS 사실에 부합한다(아래 ③ 검증).

그러나 컨셉이 **기존 코드와의 통합 비용을 한 줄("기존 코드와의 접점", §3 L58)로 과소평가**한 것이 핵심 결함이다. 현 `AnthropicChatClient`/`StreamChunk`/`ChatViewModel`/`ChatState`/`ChatTurn`은 **단방향 텍스트 수신·단일 request-response만 지원**하며, tool_use/tool_result content block·멀티라운드 루프·알림 탭 라우팅·브리핑 진입점이 **전부 0**이다(코드 직접 확인). 이대로 착수하면 첫 tool_use SSE 이벤트에서 화면 무반응 또는 디코드 실패가 나고, 알림을 눌러도 일반 채팅만 뜬다.

따라서 **컨셉을 거부할 결함은 없으나**, 아래 Blocker 2건과 Major 4건을 **구현 계획서에서 구체 설계로 해소하는 것을 Go의 조건**으로 한다. 컨셉 문서 자체는 §3·§6·§7에 "통합 외과수술 비용"을 명시하도록 갱신 권고(④).

**가장 중요한 사실 갱신:** 컨셉 v1.1은 D8·§3·§7에서 tool 계약을 "게이트 실측 선행(DoR) → 실패 시 프롬프트 폴백"이라고 미래형으로 쓰고 있으나, **게이트는 이미 실측됐고(2026-06-11, `_workspace/gate-tools-measurement.md`) 네이티브 Anthropic tools가 PASS**했다(b9430 빌드, 본 모델 GGUF). 즉 "프롬프트 폴백"은 더 이상 1차 경로가 아니라 **최후 수단으로 강등**되어야 하며, 리서치가 경고한 Qwen3 템플릿 버그 3종은 **이 빌드에서 미발생**으로 확인됐다. 컨셉은 이 실측 결과를 반영해야 한다(④-1).

---

## ② 항목별 판정 표

| # | 지적 | 위치 | 심각도(재조정) | 출처 | 판정 |
|---|------|------|----------------|------|------|
| B1 | SSE 파서·StreamChunk가 tool_use/input_json_delta를 무시 → tool 발생 시 무반응/디코드 실패 | `AnthropicChatClient.swift:125-141`, `StreamChunk.swift:13-22`, `SSEDecoder.swift` | **Blocker** | grok+agy 합의, 내부 확인 | 채택 |
| B2 | ChatViewModel/ChatState 단일 Task·단일 루프 → 2라운드 tool 루프 불가 | `ChatViewModel.swift:70-90`, `ChatState.swift:11-17` | **Blocker** | grok+agy 합의, 내부 확인 | 채택 |
| M1 | 알림 탭 → SwiftUI 라우팅/브리핑 트리거 메커니즘 전무 | `PocketLlamaApp.swift:10-18`, `RootView.swift:11-36`, `ChatView.swift`, Info.plist | **Major** | grok+agy 합의, 내부 확인 | 채택 |
| M2 | 브리핑 진입 시 기존 채팅 세션과 히스토리 충돌(슬라이딩 윈도우 오염 또는 소실) | `ChatViewModel.swift:14-29,60-66`, 컨셉 §1 L42-46/§6 L92 | **Major** | grok+agy 합의, 내부 확인 | 채택 |
| M3 | Tavily 키 주입 미확정 + 현 apiKey가 UserDefaults 평문 | 컨셉 L103, `AppSettingsStore.swift:30-32,41`, `SettingsView.swift:158-168` | **Major** | grok+agy 합의, 내부 확인 | 채택 (권고: Keychain 확정) |
| M4 | 프롬프트 폴백 JSON 마커 스트리밍 파싱 함정 과소평가 + Qwen3 템플릿/`preserve_thinking` 대책 | 컨셉 L53/L104/L111, 리서치 agentic-tools L61-63 | **Major→Minor로 일부 하향** | grok+agy 합의 | 부분 채택 (게이트 PASS로 위험 축소 — ⑤ 참조) |
| m1 | 날씨 소스 미확정 + `WeatherServiceProtocol` 추상화 권고, WeatherKit 유료 정확 | 컨셉 L101 | Minor | grok+agy 합의 | 채택 |
| m2 | 로컬 네트워크 권한 거부 시 안내 부재(서버 다운으로 오인) | `Info.plist:5-18`, `AnthropicChatClient.swift:222-228` | Minor | agy 단독 | 채택(타당) |
| m3 | serve.sh에 `--jinja` 이미 존재 — 컨셉에 "현재 기본"임을 명기 + 버전 고정 | `server/serve.sh:55` | Minor | grok 단독 | 채택(사실 확인됨) |
| m4 | 컨셉이 게이트 PASS 결과를 미반영(미래형 서술) | 컨셉 D8/§3/§7 vs `_workspace/gate-tools-measurement.md` | Minor(정합성) | 내부 단독 | 채택 |

---

## ③ 사실성 검증 (맞음 / 틀림 / 미확인)

| 주장 | 출처 | 검증 | 판정 |
|------|------|------|------|
| 현 SSE 파서가 text_delta만 처리, tool_use/input_json_delta 무시 | grok+agy | `AnthropicChatClient.swift:130-140` + `StreamChunk.swift` 직접 확인 — Delta에 content_block_start/input_json_delta/partial_json 필드 없음 | **맞음** |
| ChatViewModel이 단일 Task로 끝남(2라운드 불가), ChatState에 tool 상태 없음 | grok+agy | `ChatViewModel.swift:70-90`(defer task=nil) + `ChatState.swift:11-17`(idle~failed만) 확인 | **맞음** |
| 알림 탭 라우팅·UNUserNotificationCenterDelegate·onOpenURL 전무 | grok+agy | `PocketLlamaApp.swift`(bare WindowGroup), `RootView.swift`(isConfigured 분기만), `ChatView.swift`(NavigationStack+sheet만), Info.plist·pbxproj에 notification/background/URL scheme 없음 — grep 확인 | **맞음** |
| ChatTurn/Wire content가 String only → tool block 표현 불가 | grok | `ChatTurn.swift:12-24`, `MessagesRequest.swift:19-22` 확인 | **맞음** (내부 추가 강조) |
| apiKey가 UserDefaults 평문 저장 | grok+agy | `AppSettingsStore.swift:30-32,41` 확인(SecureField는 입력 가림만) | **맞음** |
| **게이트가 이미 네이티브 tools PASS** (Qwen 버그 미발생) | 내부 | `_workspace/gate-tools-measurement.md` 직접 확인 — b9430, 4 시나리오 ✅, "프롬프트 폴백 불필요" 명시 | **맞음(결정적)** |
| serve.sh에 `--jinja` 존재 | grok | `server/serve.sh:55` 확인 | **맞음** |
| llama.cpp `/v1/messages`가 tool_use/tool_result 지원(PR #17570) | 리서치+grok+agy | 리서치 agentic-tools L12/L52/L142 인용 + 게이트 실측이 동작 입증 | **맞음(실측으로 확정)** |
| WeatherKit은 Apple Developer Program 유료 멤버십 필수 | 컨셉 L101, grok, agy | 안정적 플랫폼 사실(WeatherKit는 유료 멤버십·entitlement 필요). 무료 Apple ID로는 사용 불가 | **맞음** — 컨셉의 WeatherKit 제외 판단 타당 |
| UNCalendarNotificationTrigger(repeats)는 폰 닫힘/잠금에서도 시스템이 정시 발화 | 컨셉 D3 | 로컬 알림은 앱 백그라운드 실행 불요(시스템 스케줄러가 발화). 설계 의도와 일치 | **대체로 맞음** — 단 저전력/Doze·시스템 합치(coalescing)에서 분 단위 지연 가능 → "실기기 검증 필요"로 한정(grok 자기검증과 일치) |
| 시뮬레이터는 로컬 알림 검증에 한계 | 컨셉 L117 | 시뮬레이터는 백그라운드 발화·일부 트리거 타이밍이 실기와 다름 → 단축 트리거 스모크만 가능, 정시·잠금화면 동작은 실기 필수 | **맞음** — 컨셉의 "단축 트리거 + 실기 체크리스트" 대응 적절 |
| 무료 Apple ID 7일 재서명 후 알림 재등록 필요 | 컨셉 L115 | 앱 삭제·재설치 시 예약된 알림 소멸 → 첫 실행 재등록 설계 필요. 타당 | **맞음** |
| 리서치 권고는 "선제 알림은 Mac cron 백엔드"인데 컨셉은 백엔드 없이 폰 로컬 알림 | 내부 | 리서치 overview L76·ux-eval L15/L103가 "iOS 백그라운드 제약 → Mac cron이 추론·푸시"를 정석으로 제시. 컨셉 D3/D7은 정반대(폰 로컬 알림, 백엔드 보류) | **상충 아님 — 판정: 양립** (아래 ⑤-3) |

**환각 점검:** 두 외부 리뷰가 인용한 `_workspace/gate-tools-measurement.md`와 `server/serve.sh:55 --jinja`를 직접 열어 **모두 실존·정확** 확인. 존재하지 않는 API·파일·플래그를 단정한 환각은 **없음**. (참고: grok 출력 상단 절반은 자체 메타-검증 로그(`/check-work` verifier·Action Trace)가 섞여 들어왔으나, 하단 "1. 총평~5. 검증한 사실"이 실제 리뷰 본문이며 내용은 정확함.)

---

## ④ 수정 권고 (컨셉 문서 `personalized-agent-concept.md`에 반영할 것)

1. **[정합성·중요] 게이트 실측 결과를 반영해 D8·§3·§7을 현재형으로 갱신.** 현 문구 "서버 tools 계약은 server-gate 실측 선행(DoR)"·"실패 시 프롬프트 폴백"은 **이미 실측 PASS**(`_workspace/gate-tools-measurement.md`, b9430)됐으므로:
   - D8/§7 리스크 표를 "**게이트 실측 완료(2026-06-11): 네이티브 Anthropic tools PASS, 프롬프트 폴백 불필요. 단 llama.cpp 빌드·GGUF 고정, 버전 변경 시 재게이트**"로 수정.
   - "프롬프트 기반 폴백"은 1차 경로에서 빼고 "**버전 변경/회귀 시에만 쓰는 최후 수단**"으로 강등. (없애지는 말 것 — 버전 드리프트 대비.)

2. **[Blocker 명시] §3 L58 "기존 코드와의 접점" 한 줄을, 실제 외과수술 항목으로 확장.** 최소: (a) StreamChunk/SSE 파서에 tool_use·input_json_delta·content_block_start/stop 디코딩 추가, (b) ChatViewModel을 2라운드 hard-cap 루프 + tool 실행 단계로 재설계, (c) ChatTurn/Wire의 String content → tool block 표현 가능 모델로 확장(또는 병렬 typed 경로), (d) 알림 탭 라우팅 배선. "단순 확장"이 아니라 **구조 변경**임을 못박을 것.

3. **[Major 명시] 브리핑-채팅 세션 격리 정책을 §3 또는 §6에 추가.** "브리핑 카드 → 그대로 채팅으로 이어짐"(L18/L46)이 기존 `messages` 슬라이딩 윈도우와 충돌하지 않도록: 브리핑은 별도 entry point에서 weather+profile을 system에 주입하고, 기존 대화 히스토리의 브리핑 컨텍스트 침범을 차단(세션 격리/아카이빙)하는 규칙을 명시.

4. **[Major 명시] Tavily 키 주입을 "열린 결정"에서 빼고 Keychain으로 확정.** L103을 "**설정 화면 입력 → iOS Keychain 저장·런타임 조회**(.env→Secrets.swift는 개발 편의용 선택, 런타임 Keychain 우선)"로 고정. 동시에 현 서버 apiKey(UserDefaults 평문)의 Keychain 이관도 Phase 0 보안 항목으로 메모.

5. **[Minor] 날씨를 `WeatherServiceProtocol`로 추상화**한다는 결정을 §6에 못박고, v0.1=Open-Meteo(무키·https·KMA 결합으로 한국 고해상도), 정확도 불만 시 기상청 공공API로 스위칭 가능하게. WeatherKit 제외 사유(유료 멤버십)는 정확하므로 유지.

6. **[Minor] 로컬 네트워크 권한 거부 안내**를 리스크 표(§7)에 추가 — `notConnected` 에러 시 "설정 → PocketLlama → 로컬 네트워크 확인" 문구 노출(현재 "서버 다운"으로 오인 가능).

7. **[Minor] serve.sh `--jinja` 현재 기본**임을 §5 또는 §7에 명기하고, 게이트 통과 빌드(b9430)·GGUF·템플릿을 **버전 고정**으로 기록(재게이트 트리거 조건 명시).

---

## ⑤ 구현 계획서에 넘길 결정 사항 (열린 결정 권고 포함)

**A. tool-calling 방식 — 권고: 네이티브 Anthropic tools 확정.**
근거: 게이트 실측 PASS(4 시나리오 ✅, `_workspace/gate-tools-measurement.md`). 프롬프트 폴백은 버전 회귀 대비 최후 수단으로만 문서화. 구현 계약은 게이트 문서의 "Swift 구현에 주는 계약 1~4"를 그대로 채택:
- 요청에 `tools:[{name,description,input_schema}]` 인코딩 추가.
- 스트림 파서: `content_block_start`(tool_use면 id/name 캡처) → `input_json_delta.partial_json` 누적 → `content_block_stop`에서 JSON 완성 → `message_delta.stop_reason=="tool_use"` 분기. `input`은 object로 옴(실측), 단 방어적 디코딩.
- 루프: tool_use → Tavily 실행 → assistant(tool_use)+user(tool_result) append → 재요청. **하드캡 2라운드 + 동일 쿼리 dedup**(컨셉 §7 리스크 표와 일치).
- 비스트림 send()도 MessagesResponse에 tool_use 블록 디코딩.

**B. 날씨 소스 — 권고: Open-Meteo + `WeatherServiceProtocol` 추상화.**
Open-Meteo는 무키·https(ATS 무탈)·한국 고해상도(KMA 모델 결합) 지원으로 v0.1에 최적. 정확도 리스크는 추상화로 흡수(추후 기상청 스위칭). WeatherKit은 무료 계정으로 사용 불가라 제외가 옳다. 위치는 **도시 수동 입력(지오코딩)을 우선** 권고 — CoreLocation 권한 피로를 v0.1에서 회피(D6의 "권한 부담 축소" 기조와 일치).

**C. Tavily(및 서버 apiKey) 키 주입 — 권고: Keychain 단일 경로.**
`.env→Secrets.swift`는 (1) 디컴파일 평문 노출, (2) 실기기/배포 시 키 변경 불가, (3) 시뮬레이터/실기 주입 경로 이원화 문제가 있어 단독 채택 부적합. **설정 화면 입력 → Keychain(SecItem) 저장·런타임 조회**로 확정. `.env`는 개발자 자동입력용 옵션으로만(런타임 Keychain override 우선). 외부 전송 키(Tavily)는 절대 번들에 평문 미포함.

**D. 알림 탭 라우팅 — 구현 계획서 선결 설계.**
`UIApplicationDelegateAdaptor` + `UNUserNotificationCenterDelegate`로 탭 캡처 → 커스텀 URL scheme 또는 `@Environment`/`NavigationPath` "briefingTrigger" 상태를 RootView/ChatViewModel까지 전달 → 날씨 수집·브리핑 생성 자동 호출. Info.plist에 알림 권한 문구·(필요 시)URL scheme 추가. 시뮬레이터 단축 트리거 스모크 + **실기 체크리스트**(정시·잠금화면·재설치 후 재등록)로 검증.

**E. 브리핑 생성 시점(L105 열린 결정) — 권고: "하루 첫 진입 시 생성 + 당일 캐시".**
알림 탭뿐 아니라 사용자가 알림을 놓치고 앱을 직접 열어도 브리핑이 떠야 하며, 같은 날 재진입 시 재생성 비용(35B TTFT)을 피하려면 당일 캐시가 합리적. 단 D2(실시간성 필수)와의 균형 — 캐시는 "당일 첫 생성분"을 재사용하되 사용자 수동 새로고침 허용.

**F. 상태머신 재설계 범위 — 구현 계획서에서 ChatViewModel 분해 방식 선택.**
옵션 비교 명시 권고: (1) ChatViewModel을 ChatOrBriefingCoordinator로 승격 vs (2) 별도 BriefingViewModel + 공통 LLMClient + 공유 히스토리 actor. 취소(§8.5)·세션 저장(Phase 8)·슬라이딩 윈도우(§7.2) 로직 재사용을 깨지 않는 안을 택할 것.

---

## ⑥ 외부 리뷰 통합 / 스킵 사유

- **agy(Gemini): 성공.** rigor max로 실행. 코드(`AnthropicChatClient`/`StreamChunk`/`ChatViewModel`/`ChatState`/`PocketLlamaApp`/`RootView`/Info.plist)와 리서치를 직접 열어 검증, web 사실확인 수행. Blocker 2·Major 4·Minor 2 제시 — 내부 검증과 1:1 일치. 원본: `plans/personalized-agent-concept-review-gemini.md`.
- **grok: 성공(단, 모델 제약으로 rigor 하향).** 1차 시도(rigor max → `--effort xhigh`)는 기본 모델 `grok-composer-2.5-fast`가 `reasoningEffort` 파라미터를 거부(HTTP 400)해 실패. 이 로그인에서 사용 가능한 reasoning 모델이 없어(`grok models` = composer-fast + grok-build뿐), **1회 재시도 시 `-m grok-build` + rigor strengthened(`--effort high --check`)로 하향**해 성공. 내용은 자체 verifier 루프(PASS)까지 포함해 충실 — Blocker 2·Major 5·Minor 4, 내부 검증과 합의. 원본: `plans/personalized-agent-concept-review-grok.md`. (주: grok 출력 상단에 verifier 메타로그가 섞였으나 하단 본문이 실 리뷰이며 정확.)
- **상충 항목:** 두 외부 리뷰 간 직접 상충 없음(드물게 강한 합의). 유일한 잠재 상충은 **리서치 권고(Mac cron 백엔드) vs 컨셉(폰 로컬 알림·백엔드 보류)** — 내부 판정으로 처리(⑤-3 아래).

**⑤-3 [상충 판정] 리서치 "선제 알림 = Mac cron 백엔드" vs 컨셉 "폰 로컬 알림·백엔드 보류(D7)".**
- 리서치 주장(overview L76, ux-eval L15/L103): iOS 백그라운드 제약으로 상시 센싱·정시 추론은 불가 → Mac cron이 추론 후 푸시하는 백엔드 분리가 정석.
- 컨셉 주장(D3/D7): v0.1은 "벨/내용 분리"로 폰 로컬 알림(발화만)+앱 진입 시 실시간 생성 → 백엔드 불요.
- **판정: 양립(둘 다 옳음, 적용 범위가 다름).** 리서치가 옳은 것은 "**잠금화면에 내용까지 사전 푸시**"하는 경우다(그건 백그라운드 추론이 필요 → Mac cron/APNs 필수). 컨셉은 바로 그 경우를 D4(잠금화면 문구 고정)·D5(ntfy/APNs 업그레이드)로 **의도적으로 양보**했고, 발화만 하는 로컬 알림은 시스템 스케줄러가 처리하므로 백그라운드 추론이 필요 없다 — **이 우회는 iOS 사실에 부합**한다. 따라서 컨셉의 D3/D7은 리서치 위반이 아니라 "리서치가 요구하는 백엔드를 v2로 미루는 합법적 다운스코프"다. 단 컨셉은 이 양립 관계를 §5에 한 줄로 명시하는 게 좋다(리서치와의 의도적 분기임을 기록).

---

## 부록: 외부 리뷰 원본
- grok: `plans/personalized-agent-concept-review-grok.md`
- gemini: `plans/personalized-agent-concept-review-gemini.md`
- 게이트 실측(결정적 사실): `_workspace/gate-tools-measurement.md`
