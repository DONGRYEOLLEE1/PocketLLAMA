# 리서치 통합: PocketLlama 개인화 에이전트 고도화

> 작성일: 2026-06-08 · 대상: **PocketLlama** (iOS SwiftUI 클라이언트(URLSession) + Mac `llama.cpp`(`llama-server`)로 서빙하는 Qwen3.6-35B-A3B(MoE, 활성 ~3B), Anthropic 호환 `/v1/messages` SSE)
> 목표: 현재의 "순수 채팅 클라이언트(메모리·툴·RAG 전무, UserDefaults 수준 영속)"를 **단일 사용자·로컬·프라이버시 우선의 개인화 에이전트**로 점진 고도화.
> 본 문서는 4개 테마 리서치(아래 §세부 리서치 문서)의 종합 결과를 받아 통합 개요 + 단계별 채택 로드맵으로 압축한 SSOT다.

---

## 한 장 요약

개인화 에이전트는 5개 축으로 분해되며, 4개 테마 리서치는 우리 맥락(1인·로컬·원격추론·프라이버시)에서 다음과 같이 수렴했다.

**① 기억/개인화 (Memory & Personalization).**
거의 모든 프로덕션 시스템(Mem0·Letta·Zep·Generative Agents)이 동일 루프 — "대화에서 salient fact를 **추출 → 저장 → relevance·recency·importance로 검색 → system 프롬프트에 주입**" — 로 수렴했다. 우리에겐 무거운 그래프 메모리(Neo4j) 대신 **SQLite(FTS5 + sqlite-vec) + llama.cpp 로컬 임베딩(`/v1/embeddings`)** 으로 완전 에어갭 메모리가 프라이버시 제약에 정확히 부합한다. 단일 사용자라 collection-reconcile보다 **in-place profile**(Letta core block / LangMem profile)이 정답이며, 추출/요약/reflection은 채팅 응답을 막지 않게 **세션 종료·유휴 배치**로 돌린다.

**② 도구·함수호출 (Agentic Tool-Calling).**
Qwen3-30B-A3B류의 tool-use 역량 자체는 BFCL-v2 ~76%로 70B급과 동급 — **병목은 모델 지능이 아니라 운영층**(llama.cpp chat template·thinking 보존·인자 직렬화)과 **클라이언트 측 에이전트 루프 하네스**다. 우리 모델 계열(Qwen3.5/3.6-35B-A3B)을 직격하는 실재 버그 3종(템플릿 `| items` 크래시 #19872, `preserve_thinking` 누락 시 빈-인자 `{}` 루프 #3325, arguments string↔object 직렬화 회귀 #20198)이 있어 `--jinja` + 패치 템플릿(`--chat-template-file`) + 버전 고정 + Swift 방어 디코딩으로 먼저 잡아야 한다. `/v1/messages`는 `tool_use`/`tool_result` content block을 이미 지원(PR #17570)하므로 **서버 재작성 없이 Swift 디코딩만** 추가하면 tool-use로 승급된다.

**③ 개인 RAG (Personal Retrieval).**
실전 스택은 **SQLite(FTS5 BM25 + sqlite-vec) + llama.cpp 임베딩**으로 수렴한다. dense 단독은 고유명사·ID·날짜에 취약하므로 **dense+BM25 하이브리드(RRF) + Contextual Retrieval**(청크당 50~100토큰 문맥 prepend, recall 실패율 최대 67%↓)이 짧은 개인 노트·메시지에 특효다. 단일 사용자 cold-start에선 **RAG가 PEFT(파인튜닝)보다 우월**(LaMP: RAG +14.92% vs PEFT +1.07%). 임베딩은 EmbeddingGemma 308M(256d truncate)·Arctic-embed-M 등으로 온디바이스화 가능하나, 우선은 Mac `--embeddings` 인스턴스 + Swift `/v1/embeddings` 호출이 가장 단순하다.

**④ UX·능동성 (Personalization UX & Proactivity).**
개인화 UX는 "**구조화 상태 → 관련 슬라이스만 system 주입 → 갱신**"의 컨텍스트 엔지니어링 루프다. 가장 싼 적응형 톤은 **PROSE식 자연어 선호문**(북마크한 응답 demonstration 1회로 생성·영속, ICL 대비 ~1/10 토큰, 벡터DB 불필요)이다. 능동성(선제 알림)은 "언제 끼어들지"의 **게이팅**이 핵심 — proactive score(≥3)·효용(>0.75)으로 일정 충돌·명시 리마인더 같은 **좁은 고신뢰 케이스만** 트리거하고, iOS 백그라운드 제약 때문에 **Mac 서버 cron 백엔드**에서 추론한 뒤 notify/question/review **HITL '제안함' UI**로 승인 게이트를 둔다.

**⑤ 평가·안전 (Eval & Safety).**
메모리가 아직 전무한 지금이 안전장치를 **도입 시점부터** 심을 절호의 기회다. SQLite 스키마에 `type/created_at/source_turn_id/confidence/verified/valid_from/valid_to` 컬럼을 선설계해 stale(낡은 기억)·자기오염(MINJA식)·hallucinated fact를 막는다: 쓰기 시 모순 검사(SSGM), update-on-write(mem0), bi-temporal "삭제 대신 무효화"(Zep), TTL/감쇠 자연 망각. **AirGapAgent식 최소 주입**(현재 질의에 필요한 최소 기억만 system에 실어 원격 전송 누출면 축소) + **자체 회귀 게이트**(LoCoMo 미니셋 회상률, Memora/FAMA식 무효기억 재사용 감점)를 ios-qa 루브릭으로 채택한다. 2026 최신 arXiv(SSGM·TierMem·Memora 등)는 재현 부족이라 "참조 설계"로만 채택하고 자체 테스트로 검증한다.

**관통하는 원칙:** 무거운 개인화 인프라(기억·RAG·도구 실행·추출 LLM 호출)는 **Mac 서버에 두고**, Swift 앱은 **얇은 스트리밍 클라이언트**로 남긴다 — 조사한 모든 프로덕션 사례(HA·Open WebUI·mem0/Letta 서버·text-to-SQL)와 일치하고 1인·단일 사용자 제약에 맞는다. 그리고 **코드보다 보안이 먼저다**(ClawdBot 무인증 노출 사태 = 우리 `0.0.0.0` 바인딩 구조와 동형).

---

## 세부 리서치 문서

| # | 테마 | 문서 | 한 줄 요약 | 출처 |
|---|---|---|---|---|
| 1 | 장기 기억·개인화 아키텍처 | [./research-personalized-agent-memory.md](./research-personalized-agent-memory.md) | 분야는 "추출→저장→relevance·recency·importance 검색→주입" 한 루프로 수렴했고, SQLite(FTS5+sqlite-vec)+llama.cpp 로컬 임베딩 기반 완전 로컬 메모리가 프라이버시 제약에 가장 부합. | 49 |
| 2 | 로컬·온디바이스 개인 비서 실제 사례 | [./research-personalized-agent-local-cases.md](./research-personalized-agent-local-cases.md) | 진짜 난제는 모델이 아니라 메모리 계층과 보안 — 얇은 Swift 클라이언트 + Mac 원격 추론을 유지한 채 서버측 메모리/도구를 붙이는 게 정답. | 49 |
| 3 | 에이전틱 능력 — 툴·RAG·함수호출 | [./research-personalized-agent-agentic-tools.md](./research-personalized-agent-agentic-tools.md) | 35B-A3B의 tool-use 역량은 70B급으로 충분하며, 신뢰성 병목은 운영층(chat template·thinking·직렬화)과 클라이언트 에이전트 루프 하네스. | 56 |
| 4 | 개인화 UX·프롬프트·평가/안전 | [./research-personalized-agent-ux-eval.md](./research-personalized-agent-ux-eval.md) | 개인화는 "구조화 상태→관련 슬라이스 주입→갱신" 컨텍스트 엔지니어링 루프이며, 프롬프트/RAG 계열이 최적이고 선제성·메모리엔 게이팅·안전장치를 도입 시점부터 심어야. | 52 |

---

## PocketLlama 단계별 로드맵

현재(순수 채팅 클라이언트)에서 출발하는 점진 Phase 제안. **작은 것부터 — 인프라 0인 프롬프트 개인화 → 영속 격상 → 요약 메모리 → tool-calling 신뢰성 → 장기 메모리/개인 RAG → 능동성.** 과대망상 금지: 풀그래프 메모리·LoRA·온디바이스 35B·활성치 steering은 1인·로컬 제약에 과설계라 채택하지 않거나 장기 옵션으로만 둔다.

> 표기 — **Swift측**: iOS 앱(ChatState·URLSession·SwiftUI). **서버측**: Mac `llama-server`/사이드카(플래그·템플릿·SQLite·임베딩·cron). 난이도 하/중/상.

### Phase 0 — 보안 락다운 + 영속 격상 (선결, 코드보다 먼저)
- **목표:** 개인 데이터를 쌓기 전에 노출·유실 경로를 막고, 영속 토대를 마련.
- **접근:** *서버측* — `llama-server` API 키 강제, `0.0.0.0` 공개망 노출 금지(로컬 WiFi/Tailscale 한정), `server-gate`에 "무인증 200=실패" 단정 추가. *Swift측* — API 키 Keychain 저장(평문 금지), **UserDefaults → SwiftData 이행**(멀티 스레드·대화별 시스템 프롬프트/샘플링 프리셋·자동 제목·연결 상태·스트리밍 중단; Local_LLM_App/Reins 패턴 차용).
- **난이도:** 하~중. **의존성:** 없음(server-gate 인증 재검증 이미 존재). **적합성:** 매우 높음 — ClawdBot 사태와 동형 위험 차단 + 단일 사용자라 멀티테넌시 복잡성 0이라 SwiftData ROI 최대.

### Phase 1 — 시스템 프롬프트 개인화 (PROSE 선호문 + core block)
- **목표:** 벡터·DB 없이 순수 프롬프트만으로 "앱이 나를 안다"는 최소 개인화 체감.
- **접근:** *Swift측* — 사용자가 별표/북마크한 응답 몇 개를 demonstration으로 모아 `llama-server`로 **선호문(자연어 한 단락)** 1회 생성(PROSE) → SwiftData에 영속 → 매 `/v1/messages`의 `system` 필드에 짧게 주입. *Swift측* — 고정 스키마 **profile JSON**(이름/직업/말투선호/금기 = Letta human·persona core block) 상주 주입 + 투명 편집 페이지(조회·편집·삭제).
- **난이도:** 하. **의존성:** Phase 0의 SwiftData(또는 UserDefaults로도 가능). **적합성:** 매우 높음 — 현 아키텍처 거의 그대로(스키마·프롬프트 변경뿐), 추가 LLM 호출은 선호문 생성 1회.

### Phase 2 — 대화 요약 메모리 (슬라이딩 윈도우 + 요약 버퍼)
- **목표:** 컨텍스트 초과를 막고 멀티턴 연속성을 확보(장기 기억 전 베이스라인).
- **접근:** *Swift측* — 최근 k턴은 결정적(무LLM) verbatim 유지, 토큰 임계 초과 시 *서버측* `llama-server` 1회 호출로 과거를 재귀 요약 압축(LangChain ConversationSummaryBufferMemory 패턴). 토큰 카운팅은 `count_tokens` 엔드포인트 활용 가능.
- **난이도:** 하. **의존성:** 없음(Phase 1 위 자연 확장). **적합성:** 높음 — 인프라 0, 슬라이딩은 무LLM, 요약만 1회 호출이라 35B-A3B 비용 미미.

### Phase 3 — Tool-calling 신뢰성 기반 (장기 메모리·능동성의 선결 조건)
- **목표:** 소형 MoE에서 함수호출을 신뢰성 있게 만들어 이후 모든 에이전틱 기능(검색 tool·메모리 self-edit·능동성)의 토대 확보.
- **접근:** *서버측* — `--jinja` 기동 + 검증된 `--chat-template-file`(froggeric/unsloth 패치본) 명시 주입 + llama.cpp **버전 고정** + GBNF/`json_schema` 제약 디코딩으로 형식 위반 서버단 1차 차단. 요청에 `preserve_thinking=true` 전달. `server-gate`를 tool-calling까지 확장(tools 포함 1턴 왕복·arguments 직렬화 형태 검증). *Swift측* — `/v1/messages`의 `tool_use`/`tool_result` content block 디코딩 추가 + **방어적 파서**(arguments string/object 이중 허용, 미완 JSON 안전 처리) + **루프 컨트롤러 하네스**를 ChatState에 이식(consecutive-call 카운터·dedup 캐시·per-tool circuit breaker·hard cap·repetition detector). 비가역 tool은 HITL 게이팅.
- **난이도:** 중~상. **의존성:** Phase 0(버전 고정·게이트). **적합성:** 높음 — 서버 재작성 없이 플래그+패치+Swift 디코딩으로 가능. 단 우리 모델 계열 직격 버그 3종이 있어 실측(server-gate) 필수.

### Phase 4 — 장기 메모리 + 개인 RAG (Mem0 패턴 + Generative Agents 검색 on SQLite)
- **목표:** 세션을 넘어 사실·선호·일화를 영속 기억하고 질의 시 관련 기억만 끌어와 주입.
- **접근:** *서버측* — 별도 `--embeddings` 인스턴스로 llama.cpp 로컬 임베딩. *Swift측 또는 Mac SQLite* — **세션 종료 시 salient fact 배치 추출**(JSON) → **SQLite(sqlite-vec + FTS5)** 저장(float32 BLOB이라 Mac DB를 iPhone에서 그대로 읽음), 검색 = **relevance(코사인)+recency(지수감쇠)+importance(저장 시 사전부여)** top-N + **dense+BM25 하이브리드(RRF)** + Contextual Retrieval(짧은 노트에 50~100토큰 문맥 prepend). 안전 컬럼 선설계: `type/created_at/source_turn_id/confidence/verified` + bi-temporal `valid_from/valid_to`(모순 사실은 삭제 대신 무효화). ADD/UPDATE/DELETE/NOOP는 코사인 임계치(룰) 1차 필터 후 모호 케이스만 LLM. 추출 결과 1차 HITL 확인. 시간·필드 질의(`지난주 메일`)는 Phase 3 tool-calling으로 검색 함수 정의(에이전틱 RAG).
- **난이도:** 중~상. **의존성:** Phase 3(검색·추출 tool 신뢰성), 임베딩 인스턴스, SQLite 스키마. **적합성:** 높음(ROI 최고) — 모든 추출/임베딩/검색이 Mac+iOS 로컬 완결로 클라우드 0. 단 로컬 ~3B 추출 품질 한계로 raw 보존형 + HITL + 배치(응답 지연 0) 필수.

### Phase 5 — Consolidation + 능동성 (프로필 형성 + 좁은 선제 게이팅)
- **목표:** 누적 기억을 자동 정제해 프로필로 승급하고, 좁은 고신뢰 케이스에 한해 선제 알림.
- **접근:** *서버측/배치* — 앱 유휴·충전 중 배치 요약(ChatGPT "dreaming"의 로컬판), heat 카운터(무LLM)로 자주 언급 사실을 long-term 프로필 승급(MemoryOS), Generative Agents reflection으로 raw→추상 계층화, decay/reinforce·프루닝으로 무한 비대화 통제. *서버측 cron* — `llama-server` 옆 cron 잡이 일정/시간 이벤트 폴링 → proactive score(≥3)·효용(>0.75)로 일정 충돌·명시 리마인더만 트리거 → 추론. *Swift측* — notify/question/review **HITL '제안함' UI** + 로컬/푸시 알림(EventKit 권한). 선제성은 좁은 범위로 제한(SOTA도 end-to-end 40% 천장).
- **난이도:** 상. **의존성:** Phase 4(메모리 가동), iOS 백그라운드/알림·EventKit, Mac 상시 가동. **적합성:** 중 — consolidation은 자연 확장이나, 능동성은 iOS 백그라운드 제약으로 Mac cron 분리 + 좁은 게이팅 필수. 잘못된 타이밍 끼어들기가 최대 UX 리스크.

> **선택/장기 옵션 (현재 채택 안 함):** Mac 사이드카 셀프호스트(mem0/OpenMemory, 직접 구현이 한계에 부딪힐 때만, 상). iOS 26.5 실기기 확보 후 — Apple Foundation Models 온디바이스 라우팅(쉬운 질의)·App Intents+IndexedEntity(OS 개인 컨텍스트·Siri/Shortcuts)·SwiftMCP·LocalLLMClient 온디바이스 폴백·온디바이스 임베딩(EmbeddingGemma). **채택 안 함:** 풀 그래프 메모리(Neo4j, 단일 사용자엔 과설계), LoRA 온디바이스 개인화(35B MoE엔 무거움), 활성치 steering(Persona Vectors/EasySteer, llama.cpp 추론 루프 개입·능력 저하·vLLM 불일치), reward model 풀 학습(1인 과투자).

---

## 리스크·오픈 퀘스천

**1. Qwen3.6-35B-A3B의 tool/JSON 신뢰성 (최대 리스크).**
역량 자체는 충분하나(BFCL ~76%) 우리 모델 계열 직격 버그 3종 — 템플릿 `tool_call.arguments | items` 크래시(#19872·#13516, `--jinja` 시 500), `preserve_thinking` 누락 시 멀티턴 빈-인자 `{}` 무한 루프(#3325), arguments string↔object 직렬화 회귀(#20198) — 이 있다. 추가로 20K 토큰 초과 시 형식 표류, 툴 반복 취약성, 극단적 KV 양자화(`q4_0`) 시 tool-calling 성능 급락. **오픈 퀘스천:** 패치 템플릿 + 버전 고정 + 방어 디코딩으로 server-gate 통과율이 실제 얼마인가? self-edit(`core_memory_replace`)류 호출이 활성 ~3B에서 안정적인가? → **메모리 self-edit는 server-gate 실측 후에만 의존**, 그 전엔 evict/요약/승급 트리거를 Swift 결정적으로.

**2. 메모리 stale·오염·hallucination.**
자동 추출 메모리는 (a) 낡음(stale, 선호·직장·거주 변화), (b) 모델이 환각한 사실 자율 저장 시 자기오염(MINJA ISR 98%와 동일 메커니즘, 단일 사용자라 외부 공격은 낮음), (c) 로컬 ~3B 추출 품질 한계로 노이즈 누적 위험. **완화:** bi-temporal "삭제 대신 무효화", 쓰기 시 모순 검사(SSGM NLI 근사), provenance(`source/confidence/verified` 컬럼), TTL/감쇠 자연 망각, 1차 HITL 확인, 그리고 **사용자가 항상 조회·편집·삭제 가능한 투명 메모리 페이지**(ChatGPT audit-trail 논란 교훈). **오픈 퀘스천:** 어느 TTL 밴드/감쇠 곡선이 우리 사용 패턴에 맞는가는 자체 회귀(LoCoMo 미니셋·Memora/FAMA 루브릭)로 측정.

**3. 프라이버시 / 노출 경로.**
`0.0.0.0` 바인딩 + 아이폰 접속 구조는 ClawdBot 무인증 노출 사태(1,862~4,500+ 인스턴스 유출)와 동형이다. 원격 추론이라 **system에 실어 보내는 모든 기억이 곧 전송 누출면**이다. **완화:** API 키 강제 + 로컬 WiFi/Tailscale 한정 + Keychain + server-gate "무인증 200=실패" 단정 + **AirGapAgent식 최소 주입**(현재 질의에 필요한 최소 기억만). 모든 추출/임베딩/검색을 Mac+iOS 로컬에서 완결해 클라우드 0 유지.

**4. Swift측 저장소·실행 한계.**
UserDefaults는 KV엔 쓸 만하나 **벡터 저장·검색엔 부적합** → SQLite 이행 선행. 온디바이스 임베딩·추출은 UI를 막으면 안 되므로 백그라운드 actor/Task 필수. iOS는 **MCP를 직접 말하지 않고**(MCP는 Mac에 격리) HTTP/REST·`/v1/messages` tool만 본다. 추출/요약/reflection의 추가 LLM 호출은 채팅 응답 지연·배터리에 직접 비용 → **세션 종료·유휴·충전 중 배치**로 숨김. iOS 백그라운드 제약으로 상시 센싱·선제 폴링은 불가 → Mac cron 백엔드 분리(Mac 상시 가동 전제).

**5. 운영·플랫폼 제약.**
- **Mac 상시 가동 전제:** 메모리 추출·RAG·임베딩·cron이 모두 Mac 서버에 있어 Mac이 꺼지면 개인화 기능이 멈춘다(현 원격 추론과 동일 제약).
- **iOS 26.5 미설치:** Apple Foundation Models·App Intents·SwiftMCP·MLX 등 고급 경로는 이 맥에 플랫폼 미설치(Phase 9 실기기 미완과 동일 제약)라 현 MVP 즉시 불가 → 장기 옵션.
- **벤치마크·최신 논문 신뢰성:** 벤더 LoCoMo 점수(Zep 84% ↔ mem0 58%)는 방법론 논쟁이라 절대 수치 비신뢰(아키텍처 특성으로 판단). 2026 arXiv(SSGM·TierMem·Memora·SwiftMem 등)는 재현·동료평가 부족 → "참조 설계"로만 채택하고 **자체 회귀 테스트로 검증**.
- **1인 개발:** fine-tuning(PEFT/LoRA/reward model) 불가 전제 → Structured Reflection 등은 학습이 아닌 **프롬프트 레벨 패턴으로만** 차용.
