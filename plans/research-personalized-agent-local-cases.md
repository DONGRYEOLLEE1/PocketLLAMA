# 리서치: 로컬·온디바이스 개인 비서 실제 사례

> 작성일 2026-06-08 · 대상 **PocketLlama** (iOS SwiftUI 앱 ↔ Mac llama.cpp/llama-server, Qwen3.6-35B-A3B MoE 원격 추론, Anthropic 호환 `/v1/messages` SSE, UserDefaults 영속, 단일 사용자·1인 개발)
>
> 목적: "순수 채팅 클라이언트"인 현 PocketLlama를 "개인화된 에이전트"로 고도화할 때, 실제 구축 사례(r/LocalLLaMA·HN·블로그·논문·OSS)에서 검증된 패턴·실패담을 추려 적용성과 우선순위를 정한다.

---

## 한눈에 요약

- **핵심 난제는 "모델"이 아니라 "메모리 계층"과 "보안"이다.** 실전 사례 다수가 같은 결론에 수렴한다 — 메모리는 RAG 검색 문제가 아니라 컨텍스트 엔지니어링 문제이고, 자가호스팅 비서의 최대 실패 모드는 "기본값으로 인증 꺼짐"이다.
- **메모리 최소 레시피는 반복 검증됐다:** (a) 최근 8~10턴 슬라이딩 윈도우 + (b) 백그라운드 비동기 사실 추출 + (c) 영속 저장 + (d) 매 턴 top-k 시맨틱 주입. MemGPT/Letta·Mem0·Zep(Graphiti)·MemMachine이 이 골격을 정교화한 변형들이며, MemoryLLM·Personal_LLM은 프레임워크 없이 같은 레시피를 DIY로 구현한다.
- **저장은 이원화가 정석:** 정확값(이름·생일·주소)은 구조화 KV, 애매한 선호/맥락은 벡터. UserDefaults는 KV층으로는 쓸 만하나 벡터검색엔 부적합 → Mac 서버 측 SQLite-vec/Chroma/Qdrant 권장.
- **보안이 코드보다 먼저다.** ClawdBot/Moltbot 사태(인증 없는 인스턴스 1,862~4,500+개 노출, API 키·대화 전량 유출)는 PocketLlama의 "0.0.0.0 바인딩 + 아이폰 접속" 구조와 동형. 필수: API 키 강제, 공개 인터넷 노출 금지(로컬 WiFi/Tailscale 한정), 키 평문 저장 금지(Keychain).
- **온디바이스 환상은 버린다.** iPhone 천장은 3B/4bit(VLM도 16 Pro에서 간신히)라 35B-A3B는 온디바이스 불가 → "얇은 Swift 클라이언트 + Mac 원격 추론" 설계는 옳다. 온디바이스는 오프라인/저지연 폴백 또는 iOS 26 Foundation Models 라우팅(쉬운 질의)으로만 보조.
- **도구호출 신뢰성이 최대 리스크.** Qwen3계열은 tool_call을 표준 `tool_calls` 필드가 아닌 content 내 JSON 텍스트로 뱉을 수 있고, 활성 ~3B MoE는 함수호출이 본질적으로 불안정할 수 있다. 신뢰성은 모델 교체가 아니라 GBNF/JSON 그래머 강제 + 2-tier 라우팅(결정적 1차 게이트 → LLM fallback) + 시스템 프롬프트 튜닝으로 확보한다.

---

## 조사한 접근·사례


| 이름                                | 종류     | 핵심 메커니즘                                                                    | 성숙도                  | PocketLlama 관련성                            |
| --------------------------------- | ------ | -------------------------------------------------------------------------- | -------------------- | ------------------------------------------ |
| MemGPT / Letta                    | 논문+런타임 | LLM 컨텍스트를 OS 가상메모리처럼 3계층(core/recall/archival)으로, 모델이 tool call로 self-edit | production           | 메모리 청사진. 단 self-edit는 tool-calling 신뢰도에 좌우 |
| Mem0 / Mem0g                      | 프레임워크  | 추출(passive)→통합(ADD/UPDATE/DELETE/NOOP) 2단계, 벡터+그래프, top-k 주입               | production           | 비용효율 최고: 전체 대화 대신 추출 사실만 주입                |
| Zep / Graphiti                    | 프레임워크  | 시간 지식그래프 — 관계마다 유효구간(타임스탬프), 덮어쓰기 대신 과거 보존                                 | production           | "예전엔 X 지금은 Y" 구분 → 구식정보 환각 감소              |
| MemMachine                        | 논문/OSS | STM/LTM/Profile 3계층, raw 에피소드 보존(추출 최소화), 벡터+그래프+컨텍스트화 검색                  | experimental         | 로컬 ~3B엔 raw 보존형이 추출형보다 적합                  |
| MemoryLLM                         | 프로젝트   | 슬라이딩 윈도우 + ChromaDB + 비동기 사실 추출 + top-5 주입 (프레임워크 無)                       | experimental         | PocketLlama가 그대로 베낄 최소 DIY 레시피             |
| Personal_LLM / llm-assistant      | 프로젝트   | 벡터+KV 하이브리드 / LangChain+Ollama 모듈형                                         | experimental         | "시맨틱+KV 이원화"가 실전 정석임을 보여줌                  |
| localLLM (iOS)                    | 프로젝트   | 온디바이스 llama.cpp + HealthKit/PDFKit/Vision으로 개인 데이터 라이브 주입                  | emerging             | "tool 없이" OS 프레임워크로 개인화하는 결정론적 경로          |
| ClawdBot/Moltbot 참사               | 안티패턴   | 원클릭 설치가 기본 포트 18789를 공개 노출, 인증 optional→유출                                 | (사건)                 | PocketLlama 0.0.0.0 바인딩과 동형 위험 — 필독        |
| Apple Foundation Models (iOS 26)  | 프레임워크  | OS 내장 ~3B 온디바이스, `@Generable`/Tool 프로토콜/constrained decoding               | production           | 무료 온디바이스 라우팅. 단 iOS 26+ 요구                 |
| App Intents + IndexedEntity       | 프레임워크  | 앱 데이터를 OS 시맨틱 인덱스에 노출, Siri/Shortcuts 양방향                                  | production           | 클라우드 없이 OS 개인 컨텍스트 통합하는 Apple-native 경로    |
| LocalLLMClient (Swift)            | 프레임워크  | llama.cpp+MLX 백엔드를 단일 Swift API로, async textStream()                       | emerging/exp.        | 온디바이스 폴백 후보. 단 API 실험 상태                   |
| SwiftMCP / MCP Swift SDK          | 프로젝트   | Foundation Models ↔ MCP 브리지, JSON Schema→DynamicGenerationSchema           | experimental         | 도구를 표준 프로토콜로. JSON-text 추출/주입 메커니즘 참고      |
| Home Assistant LLM API            | 패턴     | intent→tool 동적 주입, expose 권한통제, 2-tier 라우팅, prompt-caching                 | widely-used          | tool-calling 설계의 직접 레퍼런스(3대 패턴)            |
| Open WebUI                        | 프로젝트   | self-host RAG(청킹/임베더/top-k/벡터DB) + BYOF 파이썬 함수 + MCP                       | widely-used          | 서버측 지식 파이프라인 청사진                           |
| text-to-SQL 비서 (DEV)              | 기법     | 벡터 없이 SQLite + 스키마 introspection 주입 + 키워드 정확매칭 grounding                   | experimental         | RAG 회피 경량 개인화 — 1차 후보로 현실적                 |
| Enchanted / Reins / Local_LLM_App | 프로젝트   | Swift↔자체호스팅 채팅 클라이언트(음성·이미지·마크다운/대화별 프리셋/QR 페어링·SwiftData)                 | widely-used~emerging | PocketLlama와 같은 카테고리의 UX·영속 청사진            |
| MLX Swift + LoRA                  | 기법     | 어댑터만 학습→safetensors 핫스왑, quantized training                                | emerging             | 야간 LoRA 개인화. 단 35B MoE엔 무거움                |
| 소형 모델 툴콜링(Qwen3/Hermes)           | 기법     | Qwen은 tool_call을 content JSON 텍스트로 반환, Qwen-Agent 파서, LoRA 스키마 적응          | production           | 서버 모델이 바로 Qwen3-MoE라 직결                    |
| 2-tier + GBNF tool-calling        | 기법     | GBNF 그래머로 출력 형식 강제, 결정적 1차 게이트 후 LLM fallback, prompt caching              | emerging             | "신뢰성은 모델이 아니라 튜닝"의 실전 교훈                   |


### 1) 메모리 — MemGPT/Letta · Mem0 · MemMachine (수렴하는 한 가지 골격)

세 시스템 모두 핵심은 같다: **컨텍스트 윈도우에 전체 대화를 넣지 않고, 계층화된 외부 저장에서 관련 기억만 끌어와 주입한다.**

- **Letta(MemGPT)**: core memory(컨텍스트에 핀 고정된 구조화 블록) / recall memory(전체 이력 자동 디스크 영속) / archival memory(외부 벡터·그래프DB, 전용 검색 tool). 컨텍스트 한계 시 오래된 메시지 ~70%를 evict 후 recursive summarization. **Sleep-time compute** — 유휴 시간에 별도 에이전트가 비차단·비동기로 메모리 재정리. Docker 셀프호스팅, 모델 provider 무관.
- **Mem0**: extraction(LLM이 사실/선호 추출) → update(기존과 비교해 ADD/UPDATE/DELETE/NOOP로 일관성 유지). 임베딩 후 Qdrant(기본, 디스크 영속) 등 self-host 백엔드에 저장, 질의 시 top-k. LOCOMO 벤치에서 full-context 대비 p95 지연 91%↓·토큰비용 90%+↓·LLM-as-Judge 26% 상대 개선 보고.
- **MemMachine**: STM(최근 윈도+요약) / LTM(raw 에피소드 보존, 문장 추출+메타데이터+임베딩) / Profile(사용자 사실·선호). **raw-episode 보존**으로 LLM 추출 호출을 최소화 — 로컬 소형 모델 환경에 특히 적합. (LoCoMo 0.9169는 gpt-4.1-mini 기준이므로 로컬 ~3B엔 그대로 적용되지 않음.)

**장점**: 개인화 체감이 즉각적(프로파일을 시스템 프롬프트에 주입). 토큰·지연 절감이 로컬 추론에서 특히 큼.
**단점/위험**: Letta·Mem0의 self-edit/extraction은 추가 LLM 호출 또는 tool-calling 정확도에 의존 → **활성 ~3B MoE에선 추출 노이즈가 누적될 수 있음.** 완화책: 추출형보다 raw 보존형(MemMachine)을 우선하고, 추출 결과를 사용자에게 확인받는 HITL을 1차로 둔다.

### 2) 경량 대안 — text-to-SQL over 개인 데이터 (RAG 의도적 회피)

임베딩/벡터DB 인프라 없이 **로컬 LLM이 개인 구조화 데이터(git 이력·PM 데이터)를 SQLite에 모아 text-to-SQL로 질의**한 ~400줄 자작 비서. 시작 시 스키마 auto-introspection→시스템 프롬프트 포함, 질의 시 DB에서 키워드(repo·브랜치·ID)를 먼저 정확매칭해 실제 값을 LLM에 주입(**엔티티 grounding**)→LLM이 읽기전용 SQL 생성→결과를 산문 요약. 의존성은 `rich`·`requests` 둘뿐.

**장점**: 벡터 인프라 불필요, 의존성 극소, 읽기전용 로컬 SQLite로 프라이버시·구현 단순성 모두 1인 개발에 이상적. Qwen3계열은 코드/SQL 생성력이 있어 적합.
**단점**: 비정형(애매한 선호) 질의엔 약하고, SQL 생성 실패/오류 처리 필요. → **RAG 도입 전 1차 후보**로 가치.

### 3) 도구호출 신뢰성 — Home Assistant · 2-tier + GBNF · Qwen tool-calling

작은 로컬 MoE로 신뢰성 있는 함수호출을 내는 핵심은 **모델 선택이 아니라 튜닝**이라는 데 여러 사례가 일치한다.

- **Home Assistant LLM API**: ① tool 스키마+사용지침을 시스템 프롬프트로 **동적 주입**, ② 사용자가 노출(`expose`)할 도구를 **명시 통제**(프라이버시), ③ 네이티브 intent가 인식 가능한 명령을 먼저 처리하고 미인식만 LLM에 넘기는 **2-tier 라우팅**(지연·신뢰성 최적화).
- **2-tier + GBNF(llama.cpp HA 빌드)**: Qwen3-30B-A3B를 24GB GPU에서 1~2초로 운용. 신뢰성의 핵심은 양자화/모델이 아니라 **시스템 프롬프트 규칙 + 회귀 벤치**. 구조화 출력은 **llama.cpp GBNF 그래머로 강제**해 파싱 실패를 제거. prompt-caching으로 멀티턴 지연 절감.
- **Qwen tool-calling**: Qwen3는 Hermes-style로 **tool_call을 응답 content 내 JSON 텍스트로 반환**(표준 OpenAI `tool_calls` 필드가 아님)할 수 있어, **클라이언트가 직접 파싱**하거나 llama.cpp `--jinja` 툴 파서에 의존하는 두 경로 중 선택해야 한다.

**PocketLlama 직결**: 서버 모델이 바로 Qwen3.6-35B-A3B(활성 ~3B MoE). Swift SSE 파서가 Anthropic `/v1/messages`의 `tool_use`/`tool_result` 블록(또는 content 내 JSON tool-call)을 **안정적으로 파싱·실행·재주입**하도록 보강이 필요하다. "기억" 도입 전에 GBNF+2-tier로 **도구호출 신뢰성을 먼저 확보**하는 순서를 권장.

### 4) 보안 실패담 — ClawdBot/Moltbot (필독 안티패턴)

2025년 말 출시 후 수주 만에 60K+ stars를 얻은 자가호스팅 자율 비서가 **기본값 인증 부재**로 대규모 유출. 원클릭 설치가 기본 포트 18789를 공개 인터넷에 열어두고 인증을 'optional'로 두자, 개발자들이 'unnecessary'로 취급 → 스캔 결과 무인증 인스턴스 1,862개(Knostic)~4,500+개 노출, API 키·봇 토큰·OAuth 시크릿·전 대화 접근으로 수 분 내 완전 장악. 관련 CVE: MCP Inspector CVE-2025-49596(9.4), mcp-remote 명령주입 CVE-2025-6514(9.6), Claude Code 확장 WebSocket CVE-2025-52882(8.8).

**PocketLlama 직접 교훈**: (1) llama-server에 **API 키/인증 강제**(server-gate의 "인증 켜고 재검증" 활용), (2) 0.0.0.0을 **공개망에 노출 금지** — 로컬 WiFi 한정 또는 Tailscale/WireGuard, (3) 키 **평문 저장 금지(Keychain)**, (4) 기본값을 "안전 우선"으로. **게이트에 "인증 없이 200 응답하면 실패" 단정을 추가할 가치**가 있다.

### 5) UX·영속 청사진 — Enchanted · Reins · Local_LLM_App

PocketLlama와 같은 카테고리(Swift 앱 ↔ 자체 호스팅 서버)의 성숙한 레퍼런스.

- **Enchanted**: ChatGPT 풍 SwiftUI 네이티브, 음성 프롬프트·이미지 첨부·마크다운 렌더링. UX 확장의 검증된 우선순위.
- **Reins**: 대화별 시스템 프롬프트·모델·샘플링(temperature) 개별 구성. OpenAI 호환 포크(`reins-openai`)는 같은 코드베이스가 다중 백엔드를 추상화하는 패턴을 보여줌.
- **Local_LLM_App**: **QR 페어링**으로 서버 URL 자동 설정(IP·포트 수동 입력 마찰 제거), **SwiftData** 기반 멀티 스레드·자동 제목·연결 상태 색 점·스트리밍 중단 버튼.

**교훈**: UserDefaults → **SwiftData 이행**이 비용 대비 효과가 가장 크다. 다만 이들 대부분 TLS/인증 미문서화 — 보안은 별도로 챙겨야 한다.

---

## PocketLlama 환경 적용성

우리 스택: **Swift 클라이언트(URLSession/SSE) + llama.cpp(llama-server) + Qwen3.6-35B-A3B(MoE, 활성 ~3B) + UserDefaults + 단일 사용자·1인 개발 + Anthropic 호환 `/v1/messages`.**

원칙: **무거운 개인화 인프라(기억·RAG·도구 실행)는 Mac 서버에 두고, Swift 앱은 얇은 스트리밍 클라이언트로 남긴다.** 이는 조사한 모든 프로덕션 사례(HA·Open WebUI·mem0/Letta 서버·text-to-SQL)와 일치하며 1인 개발·단일 사용자 제약에도 맞는다.

### 쉬운 것 (낮은 비용·높은 효과)

- **영속 격상(UserDefaults → SwiftData)**: Local_LLM_App·Reins 패턴을 거의 그대로 차용. 멀티 스레드·대화별 시스템 프롬프트/샘플링 프리셋·자동 제목·연결 상태 표시·스트리밍 중단. **단일 사용자라 멀티테넌시 복잡성 없음.**
- **보안 락다운**: API 키 강제 + 로컬 WiFi/Tailscale 한정 + Keychain. 이미 server-gate에 인증 재검증이 있으므로 게이트에 "무인증 200=실패" 단정 추가만 하면 됨.
- **경량 개인화(text-to-SQL)**: 개인 구조화 데이터(대화 로그·캘린더·노트)를 서버 SQLite에 모으고 스키마 주입 + 키워드 정확매칭 grounding. 임베딩 인프라 불필요, 의존성 극소.
- **KV 사실 저장**: 이름·생일·주소 같은 정확값은 UserDefaults(또는 서버 SQLite KV)로 충분. 시스템 프롬프트에 프로파일로 주입하면 즉시 "개인화" 체감.

### 중간 (서버측 인프라 필요·검증 필요)

- **메모리/RAG**: MemoryLLM/MemMachine 레시피를 경량화 — llama.cpp `/embeddings` 엔드포인트 + 서버측 SQLite-vec/Chroma/Qdrant. 슬라이딩 윈도우(최근 N턴) + 비동기 사실 추출 + top-k 주입. **단 임베딩 모델 별도 서빙이 필요하고, 추출 LLM 호출 비용은 응답 후 비동기(야간 배치)로 숨겨야 함.**
- **벡터 저장**: UserDefaults는 벡터검색에 부적합 → Mac 측 SQLite-vec/Chroma. 애매한 선호/맥락 전용.

### 어려운 것 / 막히는 지점

- **도구호출 신뢰성(최대 리스크)**: Qwen3.6-35B-A3B는 활성 ~3B라 tool-calling이 본질적으로 불안정할 수 있고, tool_call이 표준 필드가 아닌 **content 내 JSON 텍스트**로 올 위험. → **GBNF/JSON 그래머 강제 + 2-tier 라우팅(결정적 1차 게이트) + 시스템 프롬프트 튜닝 + 회귀 벤치**로 먼저 확보. Letta식 self-edit 메모리는 이 신뢰성이 확보된 **다음** 단계.
- **온디바이스 35B**: 불가(iPhone 천장 3B/4bit). → 현 원격 설계 유지. 온디바이스는 폴백/라우팅 보조로만.
- **iOS 26 의존 경로 차단**: Apple Foundation Models·SwiftMCP·MLX·App Intents 고급 기능은 모두 **iOS 26+ 요구 → 이 맥 미설치(Phase 9 실기기 미완과 동일 제약)**. 현 MVP엔 즉시 불가, 향후 옵션.
- **LoRA 온디바이스 개인화**: 35B MoE엔 무겁고 llama.cpp↔MLX 포맷 변환 비용. → 소형 보조 모델/어댑터 핫스왑으로 한정.
- **메모리 추출 품질**: 로컬 ~3B는 추출·요약 품질이 떨어져 노이즈 누적 위험 → raw 보존형(LLM 호출 최소화) + HITL 확인이 안전.

---

## 권장 채택안


| 우선순위 | 채택안                                                                                                                                                  | 난이도 | 선행조건                                              |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | --- | ------------------------------------------------- |
| 1    | **보안 락다운** — API 키 강제 + 로컬 WiFi/Tailscale 한정 + Keychain 저장. server-gate에 "무인증 200=실패" 단정 추가                                                          | 하   | 없음(server-gate 인증 재검증 이미 존재). 코드보다 먼저             |
| 2    | **영속 격상** — UserDefaults → SwiftData(멀티 스레드·대화별 프리셋·자동 제목·연결 상태·스트리밍 중단)                                                                             | 하~중 | iOS 17+ SwiftData. Local_LLM_App/Reins 패턴 차용      |
| 3    | **도구호출 신뢰성 기반** — llama.cpp GBNF/JSON 그래머로 tool 출력 형식 강제 + 2-tier 라우팅(결정적 1차 게이트 → LLM fallback) + Swift SSE `tool_use` 파서 보강                        | 중~상 | llama.cpp `--jinja`/그래머 검증, 회귀 벤치 셋. 기억 도입의 선결 조건 |
| 4    | **경량 개인화(KV + text-to-SQL)** — 정확값은 KV 프로파일 주입, 구조화 개인 데이터는 서버 SQLite + 스키마 주입 + 키워드 grounding                                                       | 중   | 서버측 SQLite, 읽기전용 SQL 실행, Qwen SQL 생성력 검증          |
| 5    | **메모리 계층(raw 보존형)** — 슬라이딩 윈도우 + 비동기 사실 추출 + top-k 시맨틱 주입. MemMachine/MemoryLLM 레시피 경량화(SQLite-vec + llama.cpp `/embeddings`), 추출은 야간 배치, 1차 HITL 확인 | 상   | 임베딩 모델 별도 서빙, 벡터 저장소, #3 신뢰성 선행                   |


> 향후(iOS 26 플랫폼 설치 후) 옵션: Apple Foundation Models 온디바이스 라우팅(쉬운 질의), App Intents+IndexedEntity로 OS 개인 컨텍스트(캘린더·노트)·Siri/Shortcuts 양방향, SwiftMCP/MCP Swift SDK로 도구 표준화, LocalLLMClient(llama.cpp+MLX) 온디바이스 폴백.

---

## 참고자료

- [MemGPT: Towards LLMs as Operating Systems (arXiv 2310.08560)](https://arxiv.org/abs/2310.08560)
- [MemGPT research page](https://research.memgpt.ai/)
- [Mem0 vs Letta (MemGPT): AI Agent Memory Compared](https://vectorize.io/articles/mem0-vs-letta)
- [Mem0: Building Production-Ready AI Agents with Scalable Long-Term Memory (arXiv 2504.19413)](https://arxiv.org/abs/2504.19413)
- [Mem0: An open-source memory layer for LLM applications and AI agents (InfoWorld)](https://www.infoworld.com/article/4026560/mem0-an-open-source-memory-layer-for-llm-applications-and-ai-agents.html)
- [Adding Persistent Memory to Local AI Agents with Mem0 and Ollama](https://mem0.ai/blog/adding-persistent-memory-to-local-ai-agents-with-mem0-openclaw-and-ollama)
- [State of AI Agent Memory 2026 - Mem0](https://mem0.ai/blog/state-of-ai-agent-memory-2026)
- [Agent Memory at Scale 2026: Letta, Zep, Mem0, LangMem Compared](https://agentmarketcap.ai/blog/2026/04/10/agent-memory-vendor-landscape-2026-letta-zep-mem0-langmem)
- [Agent Memory: How to Build Agents that Learn and Remember (Letta)](https://www.letta.com/blog/agent-memory)
- [Rearchitecting Letta's Agent Loop: ReAct, MemGPT & Claude Code](https://www.letta.com/blog/letta-v1-agent)
- [MemMachine: A Ground-Truth-Preserving Memory System for Personalized AI Agents (arXiv)](https://arxiv.org/html/2604.04853v1)
- [GitHub - maranone/MemoryLLM](https://github.com/maranone/MemoryLLM)
- [GitHub - srikarpunna/Personal_LLM (Personal AI Assistant with Persistent Memory)](https://github.com/srikarpunna/Personal_LLM)
- [GitHub - mauricekastelijn/llm-assistant (LangChain + Ollama)](https://github.com/mauricekastelijn/llm-assistant)
- [GitHub - leonickson1/localLLM (privacy-first iOS, llama.cpp)](https://github.com/leonickson1/localLLM)
- [We Scanned 1 Million Exposed AI Services (The Hacker News)](https://thehackernews.com/2026/05/we-scanned-1-million-exposed-ai.html)
- [MCP shipped without authentication. Clawdbot shows why that's a problem (VentureBeat)](https://venturebeat.com/security/mcp-shipped-without-authentication-clawdbot-shows-why-thats-a-problem)
- [Clawdbot Security Issues: Over 1,000 AI Agent Servers Exposed (BeyondMachines)](https://beyondmachines.net/event_details/clawdbot-security-issues-over-1000-ai-agent-servers-exposed-to-unauthenticated-access-6-y-a-t-e)
- [Meet the Foundation Models framework - WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Updates to Apple's On-Device and Server Foundation Language Models - Apple ML Research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [Apple's Foundation Models Framework: Run AI On-Device With Just a Few Lines of Swift (DEV)](https://dev.to/arshtechpro/apples-foundation-models-framework-run-ai-on-device-with-just-a-few-lines-of-swift-lbp)
- [LocalLLMClient: A Swift Package for Local LLMs Using llama.cpp and MLX (DEV)](https://dev.to/tattn/localllmclient-a-swift-package-for-local-llms-using-llamacpp-and-mlx-1bcp)
- [AnyLanguageModel: One API for Local and Remote LLMs on Apple Platforms (HF)](https://huggingface.co/blog/anylanguagemodel)
- [SwiftMCP - GitHub](https://github.com/sutheesh/SwiftMCP)
- [modelcontextprotocol/swift-sdk (official Swift SDK)](https://github.com/modelcontextprotocol/swift-sdk)
- [Using Model Context Protocol in iOS apps - Artem Novichkov](https://artemnovichkov.com/blog/using-model-context-protocol-in-ios-apps)
- [Creating MCP Clients in Swift: Integrating Model Context Protocol](https://jamesrochabrun.medium.com/creating-mcp-clients-in-swift-integrating-model-context-protocol-278d2d7676a9)
- [Get to know App Intents - WWDC25](https://developer.apple.com/videos/play/wwdc2025/244/)
- [Explore new advances in App Intents - WWDC25](https://developer.apple.com/videos/play/wwdc2025/275/)
- [Integrating actions with Siri and Apple Intelligence - Apple Developer Documentation](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence)
- [gluonfield/enchanted - GitHub](https://github.com/gluonfield/enchanted)
- [Enchanted by Ollama: your personal chatbot on iOS - Medium](https://medium.com/@ggodart/enchanted-by-ollama-your-personal-chatbot-on-ios-77343f498a2e)
- [ibrahimcetin/reins - GitHub](https://github.com/ibrahimcetin/reins)
- [xor22h/reins-openai (OpenAI-compatible fork) - GitHub](https://github.com/xor22h/reins-openai)
- [Shun0212/Local_LLM_App - GitHub](https://github.com/Shun0212/Local_LLM_App)
- [WWDC 2025 - Explore LLM on Apple silicon with MLX](https://dev.to/arshtechpro/wwdc-2025-explore-llm-on-apple-silicon-with-mlx-1if7)
- [The Magic of LoRA Fine-Tuning with MLX (Part 4)](https://dev.to/prashant/the-magic-of-lora-fine-tuning-with-mlx-part-4-367p)
- [Function Calling - Qwen (official docs)](https://qwen.readthedocs.io/en/latest/framework/function_call.html)
- [5 Small Language Models for Agentic Tool Calling - KDnuggets](https://www.kdnuggets.com/5-small-language-models-for-agentic-tool-calling)
- [Home Assistant API for Large Language Models (Developer Docs)](https://developers.home-assistant.io/docs/core/llm/)
- [AI agents for the smart home (Home Assistant blog)](https://www.home-assistant.io/blog/2024/06/07/ai-agents-for-the-smart-home/)
- [Building a Reliable Locally-Hosted Voice Assistant with llama.cpp and Home Assistant (Agent Wars)](https://agent-wars.com/news/2026-03-16-locally-hosted-voice-assistant-llama-cpp-home-assistant)
- [Improve local LLM performance with llama.cpp and custom-conversation (HA Community)](https://community.home-assistant.io/t/improve-local-llm-performance-with-llama-cpp-and-custom-conversation/935476)
- [Retrieval Augmented Generation (RAG) — Open WebUI docs](https://docs.openwebui.com/features/chat-conversations/rag/)
- [open-webui/open-webui (GitHub)](https://github.com/open-webui/open-webui)
- [Building a Local RAG Pipeline with Ollama and Open WebUI](https://localaiops.com/posts/building-a-local-rag-pipeline-with-ollama-and-open-webui/)
- [I Built a Private AI Assistant That Queries My Git History and PM Data — Using Only Local LLMs (DEV)](https://dev.to/pouria_zand/i-built-a-private-ai-assistant-that-queries-my-git-history-and-project-management-data-using-only-39mn)
- [tdi/awesome-private-ai (GitHub README)](https://github.com/tdi/awesome-private-ai/blob/main/README.md)
- [10 Best Private Personal AI Assistants in 2026 (Vellum)](https://www.vellum.ai/blog/best-private-personal-ai-assistants)

