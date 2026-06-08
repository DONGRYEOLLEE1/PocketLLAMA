# 리서치: 장기 기억·개인화 아키텍처

> 작성일: 2026-06-08 · 대상: **PocketLlama** (iOS SwiftUI 클라이언트 + Mac `llama.cpp`(`llama-server`)로 서빙하는 Qwen3.6-35B-A3B, Anthropic 호환 `/v1/messages` SSE)
> 목표: "순수 채팅 클라이언트(메모리/툴/RAG 전무, UserDefaults 수준 영속)"를 **개인화 에이전트**로 고도화. 제약: 단일 사용자 · 프라이버시 우선(외부 클라우드 의존 최소화) · 1인 개발.

---

## 한눈에 요약

- **분야가 4~5개 패턴으로 수렴했다.** (1) 컨텍스트 내 압축(요약 버퍼·슬라이딩 윈도우), (2) OS 가상메모리식 계층화(MemGPT/Letta의 core/recall/archival, MemoryOS의 short/mid/long), (3) 외부 추출-저장-검색 메모리 레이어(Mem0의 fact 추출 + ADD/UPDATE/DELETE/NOOP), (4) 시간성 지식그래프(Zep/Graphiti의 bi-temporal·사실 무효화), (5) 인지과학식 memory stream + reflection(Generative Agents).
- **거의 모든 프로덕션 시스템이 동일 루프를 공유한다.** "LLM이 대화에서 salient fact를 추출 → 벡터/그래프/KV에 저장 → 질의 시 relevance·recency·importance로 검색 → 풀컨텍스트 대비 토큰·지연 ~90% 절감." LoCoMo·LongMemEval·DMR이 사실상 표준 벤치마크.
- **PocketLlama 제약(1인·로컬·프라이버시)에 가장 잘 맞는 스택은 SQLite(FTS5 + sqlite-vec) 기반 로컬 메모리 + llama.cpp 로컬 임베딩(`/v1/embeddings`)이다.** 모든 추출/임베딩/검색이 Mac+iOS 안에서 완결되어 외부 클라우드 의존 0 — 프라이버시 목표와 정확히 부합.
- **두 갈래 UX 중 하이브리드가 최적.** ChatGPT식 "항상 주입(소형 구조화 프로필을 시스템 프롬프트에 상주)" + Claude식 "툴 검색(긴 일화/사실은 `conversation_search`로 온디맨드)". Qwen3.6-35B-A3B는 활성 ~3B MoE라 컨텍스트가 비싸므로 프로필을 짧게 유지.
- **벤더 LoCoMo 점수(Zep 84% ↔ mem0 58% 등)는 방법론 논쟁이 크다.** 절대 수치보다 "아키텍처 특성"으로 판단할 것.
- **핵심 위험은 추출/갱신/편집의 추가 LLM 호출과 tool-calling 신뢰도다.** MemGPT식 "에이전트 자율 self-edit"보다, evict/요약/승급 트리거는 Swift에서 결정적으로 돌리고 LLM은 추출·요약·중요도 판정만 맡기는 **하이브리드(서버측 결정적 파이프라인)**가 35B-A3B 로컬 모델엔 더 안전.

---

## 조사한 접근·사례

| 이름 | 종류 | 핵심 메커니즘 | 성숙도 | PocketLlama 관련성 |
|---|---|---|---|---|
| **Mem0 / Mem0g** | 프레임워크 | 2단계(추출 → ADD/UPDATE/DELETE/NOOP 갱신), 벡터+KV(+선택적 그래프) 저장, OpenAI 호환 LLM/임베딩 | 널리 사용 | 가장 이식성 높은 백엔드 청사진. llama.cpp `/v1/chat`·`/v1/embeddings`를 그대로 연결. 그래프 변형(Mem0g)은 단일 사용자엔 과설계 |
| **Letta (MemGPT)** | 프레임워크 | OS 3계층(core/recall/archival) + 라벨된 메모리 블록을 에이전트가 도구로 self-edit(append/replace) | 널리 사용 | 패턴(human/persona 블록 + 시스템 프롬프트 상주)은 Swift 재현 가능. 본체는 Python 서버. tool-calling 신뢰도가 정확도 좌우 |
| **Zep / Graphiti** | 프레임워크 | bi-temporal 지식그래프(엣지당 4 타임스탬프), 모순 사실은 삭제 대신 `t_invalid` 무효화. 하이브리드 검색(임베딩+BM25+그래프) | 프로덕션 | 시간성 사실(이사·직장·선호 변화)에 강력. Neo4j+Python 풀스택은 1인 환경에 무거움 → valid_from/valid_to만 SQLite로 차용 |
| **cognee** | 프레임워크 | add/cognify/search 3연산, 트리플릿 추출 + memify(사용빈도 기반 재가중·프루닝) | 프로덕션 | memify의 "자주 쓰는 사실 강화, 안 쓰는 것 퇴색" 망각 정책 참고. 그래프DB+Python 의존으로 iOS 단독엔 무거움 |
| **LangMem** | 프레임워크 | semantic/episodic/procedural 3종 + **profile(단일 구조화 문서 in-place)** vs **collection(다수 reconcile)**, hot-path vs background 추출 | 신흥 | "profile vs collection" 구분이 설계 어휘로 직접 차용 가치. 단일 사용자 앱은 profile이 정답. 본체는 LangChain 스택 의존 |
| **A-MEM** | 논문 | Zettelkasten 노트(timestamp/content/keywords/tags/embedding) + LLM 링크 생성 + 메모리 진화 | 실험적 | 노트+링크+진화는 외부 그래프DB 없이 임베딩+관계 테이블만으로 구현 가능해 iOS 친화적. 진화 단계가 LLM 호출 증가 |
| **Generative Agents** | 논문 | memory stream(시간순 episodic) + **relevance+recency+importance** 3요소 검색 + reflection(임계치 초과 시 고차 노드 생성) | 널리 사용 | 3요소 검색 스코어는 SQLite 한 테이블로 즉시 구현 가능한 가장 단순·검증된 공식. importance를 저장 시 사전부여하면 질의 시 무LLM |
| **MemoryOS** | 프레임워크 | short/mid/long 3계층 + 4모듈, heat 기반 eviction·프로필 승급(FIFO/세그먼트 페이징) | 신흥 | short/mid/long + heat 승급이 매우 직관적 이식. long-term을 JSON으로 두는 단순함이 UserDefaults에서 자연 확장. heat는 무LLM 카운터 |
| **ChatGPT Memory** | 제품 | saved memories(명시) + chat history insights(암묵) 2계층, "Dreaming" 백그라운드 합성 프로필을 매 대화 자동 주입 | 널리 사용 | "명시+암묵 2계층" UX와 토글/삭제 컨트롤은 직접 모델. dreaming은 "앱 유휴/충전 중 로컬 배치 요약"으로 비용 0 구현 |
| **Claude Memory** | 제품 | 빈 슬레이트 + `conversation_search`/`recent_chats` 툴 호출 + memory 파일 디렉터리 CRUD(투명·감사 가능) | 프로덕션 | 가장 이식하기 쉬운 패턴. tool-calling으로 모델이 SQLite/파일을 명시 조회 → 토큰 절약 + 투명성 동시 확보 |
| **VecturaKit** | 프로젝트 | Swift 네이티브 온디바이스 벡터DB, 플러그형 저장(파일/SQLite/Core Data), 임베딩 다중(NLContextual·MLX·OpenAI호환), 벡터+BM25 하이브리드 | 신흥 | **가장 직접적인 Swift 부품.** OpenAICompatibleEmbedder로 llama.cpp 임베딩, 오프라인 시 NLContextualEmbedder 폴백. iOS 18+/macOS 15+ |
| **sqlite-memory (sqliteai)** | 프로젝트 | markdown 청킹(512토큰/100 overlap) + content-hash dedup, 하이브리드(벡터 0.6/BM25 0.4), llama.cpp 온디바이스 GGUF 임베딩 | 신흥 | 프라이버시·로컬 제약에 정확히 부합. 구체 파라미터를 그대로 채택 가능. iOS는 SQLite 네이티브 + sqlite-vec/FTS5 |
| **OpenMemory (CaviraOSS)** | 프로젝트 | 5 인지섹터 분류 + SQLite/Postgres + waypoint 그래프 + 시간 그래프(valid_from/valid_to) + decay/reinforce(적응형 망각) | 신흥 | valid_from/valid_to 시간 그래프 + decay/reinforce가 메모리 무한 비대화를 막는 실전 해법. Mac 사이드카로 두고 HTTP 접근 |
| **OpenMemory MCP (mem0)** | 제품 | mem0 엔진을 사용자 머신에서 완전 로컬 운영, LLM/임베딩을 Ollama/로컬 모델로 교체, MCP 노출 + 대시보드 | 신흥 | 프라이버시 제약에 정확 부합. Mac에서 mem0 엔진 로컬 기동 + llama.cpp 지정 → 클라우드 0. mem0 셀프호스트 최단 경로 |
| **Memoria** | 논문 | 동적 세션 요약(단기) + 가중 KG 사용자 모델링(장기) 이원 구조, 토큰 제약 내 운용 명시 | 실험적 | 이름 그대로 PocketLlama 목표와 직결. "세션 요약 + 가중 KG" 이원 분리는 단계적 메모리 설계 레퍼런스 |
| **SwiftMem** | 논문 | 시간 인덱스(로그시간 범위질의) + 시맨틱 DAG-Tag 인덱스 + 주기적 클러스터 재조직(co-consolidation) | 실험적 | (Swift 언어와 무관, 시스템명) 메모리 누적 시 검색 지연 잡는 알고리즘 아이디어. VecturaKit/SQLite 위 효율화 차용 |
| **요약 버퍼/슬라이딩 윈도우** | 기법 | 최근 k턴 verbatim + 토큰 임계 초과 시 과거를 재귀 요약 압축(LangChain ConversationSummaryBufferMemory) | 널리 사용 | 인프라 0으로 즉시 적용 가능한 1단계. 슬라이딩 윈도우는 Swift에서 무LLM 결정적 구현, 요약은 llama-server 1회 호출 |

> **참고 인덱스:** NirDiamant/Agent_Memory_Techniques(30개 실행 노트북), TeleAI-UAGI/Awesome-Agent-Memory(시스템·벤치마크·논문 큐레이션)는 알고리즘 레퍼런스·평가축 조망용. arXiv 2510.07925(영속 메모리+사용자 프로필)는 동일 문제설정의 최신 학술 근거지만 본문 수치 미확보로 차용은 보류.

### 상세 1 — Mem0 / Mem0g (메모리 백엔드 청사진)

**메커니즘.** 2단계 파이프라인. (1) **추출**: LLM 함수 φ가 `[대화 요약 S + 최근 m≈10 메시지 + 현재 교환]`을 받아 원자적(atomic) salient fact 집합 Ω를 생성. (2) **갱신**: 각 후보 fact를 임베딩으로 top-10 유사 기존 메모리와 비교한 뒤 LLM이 **ADD/UPDATE/DELETE/NOOP**를 결정(모순 → DELETE, 보완 → UPDATE) — 이것이 consolidation 메커니즘. 저장은 하이브리드(벡터DB 의미검색 + KV 구조화 + 선택적 그래프). Mem0g 변형은 엔티티 추출 → 관계 트리플릿(source, relation, destination)을 Neo4j 방향그래프로 저장.

**실측(arXiv 2504.19413).** LoCoMo J-score Mem0 66.9% / Mem0g 68.4%, 메모리 풋프린트 ~7k/14k tokens(풀이력 26k 대비), 검색 p95 ~0.2초, 풀컨텍스트(17초) 대비 응답 지연 ~91%↓, 토큰 ~90%↓. OpenAI 메모리 대비 LLM-as-judge 상대 +26%(temporal 격차 큼: 55.5 vs 21.7).

**장점.** OpenAI 호환 엔드포인트 추상화 → llama.cpp 그대로 연결. 'fact 추출 → 저장 → 주입' 루프 전체를 Swift+llama-server로 재현 가능. **단점.** '메시지마다 LLM 추출'은 단일 로컬 모델에 비용·지연·factual drift 위험 → 턴마다가 아니라 **세션 종료 시 배치 추출** 권장. ADD/UPDATE/DELETE/NOOP 판정은 코사인 임계치(룰) 1차 필터 후 모호한 케이스만 LLM에 위임해 호출·오류 절감.

### 상세 2 — Generative Agents (검색 스코어 공식)

**메커니즘.** 모든 지각/행동을 자연어 관찰로 시간순 memory stream에 append(episodic). 검색 시 세 점수 가중합으로 상위 기록 선택: **relevance**(질의 임베딩 코사인) + **recency**(지수 감쇠) + **importance**(LLM이 1~10 사전 부여). reflection은 consolidation 단계 — 최근 이벤트 importance 합이 임계치(구현상 150)를 넘으면 트리거되어 LLM이 핵심 질문을 생성하고 그 답(상위 추론)을 고차 노드로 다시 스트림에 기록.

**장점.** relevance+recency+importance 3요소는 **SQLite 한 테이블만으로 즉시 구현**되는 가장 단순·검증된 공식. importance를 저장 시 사전 부여하면 질의 시 추가 LLM 호출 없이 검색. reflection(주기 고차 요약 노드)은 1인 에이전트의 '사용자 프로필 형성'에 직결. **단점.** reflection은 주기적 LLM 호출을 요구 → 유휴/배치로 돌려야 함.

### 상세 3 — Letta(MemGPT) / Claude Memory (경량 self-edit + 툴 검색)

**Letta 메커니즘.** core(항상 컨텍스트 상주, 글자수 제한 블록 = RAM) / recall(검색 가능 대화 캐시) / archival(외부 장기 저장). 핵심 프리미티브는 `{label, value, size limit, description}` 메모리 블록(DB에 block_id로 개별 영속, Jinja 템플릿으로 컨텍스트 '컴파일'). 관습 블록은 human(사용자에 대해 아는 것)·persona(에이전트 자기설명). 에이전트가 `core_memory_append`/`core_memory_replace`/`memory_rethink` 도구를 추론 루프 중 호출해 갱신.

**Claude 메커니즘.** 매 대화를 빈 슬레이트로 시작, `conversation_search`/`recent_chats` 툴로 **원본 이력을 실시간 검색**(AI 요약·압축 프로필 없음). 별도 Memory tool은 memory 파일 디렉터리를 CRUD. 툴 호출이 가시화돼 **언제·왜 과거가 들어왔는지 감사 가능**.

**PocketLlama 차용.** "글자수 제한 core block을 시스템 프롬프트에 상주"는 RAG/벡터DB 없이 페르소나·핵심 선호를 영속화하는 최소 비용 해법 — UserDefaults에 human/persona 블록 JSON을 두고 매 요청 system 메시지로 주입하면 1인 MVP에 이상적. 긴 일화는 Claude식 `conversation_search` 툴로 온디맨드. **단, 35B-A3B의 tool-calling 신뢰도**가 self-edit/검색 호출 정확도를 좌우하므로 server-gate로 실측 후 의존.

### 상세 4 — 시간성: Zep/Graphiti bi-temporal & OpenMemory (경량 차용)

**메커니즘.** 모든 엣지에 `(t_valid, t_invalid)` 유효구간 + `(t_created, t_expired)` 시스템 시각 4 타임스탬프. 사실이 바뀌면 옛 사실을 **삭제하지 않고 `t_invalid`를 채워 무효화**(historical accuracy 보존). 검색은 LLM 호출 없이 임베딩+BM25+그래프 순회 하이브리드(P95 ~300ms). OpenMemory는 같은 아이디어를 SQLite `valid_from/valid_to` + decay/reinforce(적응형 망각)로 경량 구현.

**PocketLlama 차용.** Neo4j 풀그래프·다단계 LLM 추출은 1인 환경에 과하므로 **도입하지 않는다.** fact 테이블에 `valid_from`/`valid_to` 컬럼만 추가 → 모순 사실 등장 시 옛 행을 지우지 않고 `valid_to`를 찍어 이력 보존(작년→올해 바뀐 선호/직장/거주를 정확히 처리). "싱가포르 7월에 간다 → 갔다" 류 시간성 갱신을 ChatGPT처럼 처리하는 구체 스키마.

---

## PocketLlama 환경 적용성

우리 스택: **Swift(URLSession) 클라이언트 + Mac llama.cpp(`llama-server`) + Qwen3.6-35B-A3B(MoE, 활성 ~3B) + UserDefaults 수준 영속 + 단일 사용자 · 원격 추론 · 프라이버시 우선.**

### 쉬운 것 (낮은 위험·인프라)
- **슬라이딩 윈도우 + 요약 버퍼.** 최근 k턴은 Swift에서 결정적(무LLM) verbatim 유지, 토큰 임계 초과 시 llama-server 1회 호출로 과거 재귀 요약. 인프라 0, 즉시 적용.
- **소형 구조화 user profile.** Letta core block + LangMem profile 패턴 — 이름/직업/말투선호/금기 등 고정 스키마 JSON을 UserDefaults에 두고 매 요청 system 메시지로 주입(수백 토큰). 단일 사용자라 profile(in-place 갱신)이 정답.
- **relevance+recency+importance 검색.** SQLite 한 테이블 + 저장 시 LLM이 importance 사전부여 → 질의 시 무LLM top-N 주입.
- **로컬 임베딩.** llama.cpp `/v1/embeddings`로 완전 에어갭 시맨틱 검색. iOS는 SQLite 네이티브 + sqlite-vec/FTS5, 또는 Swift 네이티브 VecturaKit(NLContextualEmbedder 오프라인 폴백). 외부 클라우드 0.
- **heat 기반 프로필 승급.** MemoryOS — 자주 언급되는 사실(heat 카운터, 무LLM)을 long-term 프로필로 승격.
- **사용자 투명 메모리 페이지.** ChatGPT V3/Claude editable summary 패턴 — 저장된 메모리를 항상 조회·편집·삭제 가능하게 설정 화면에 노출.

### 어려운 것 (운영 부담·의존성)
- **풀 그래프 메모리(Zep/Graphiti·cognee·Mem0g).** Neo4j+Python 다단계 LLM 추출 스택은 Mac에서 무겁고 1인 운영 부담 大. 단일 사용자엔 그래프가 과설계 → dense 벡터 + 구조화 profile로 시작. 단, **bi-temporal '삭제 대신 무효화' 아이디어만** `valid_from`/`valid_to` SQLite 컬럼으로 경량 차용.
- **Python 메모리 프레임워크 본체(Letta/mem0/cognee/OpenMemory).** iOS 앱에서 직접 임베드 불가 → **Mac 사이드카(llama-server 옆)로 셀프호스트하고 앱이 URLSession으로 HTTP/REST 호출**하는 구조가 현실적(mem0 self-host / OpenMemory MCP). 대가: Mac이 켜져 있어야 하고 추출마다 추가 LLM 호출.
- **iOS에서 MCP 직접 말하기.** OpenMemory MCP는 Cursor/Claude Desktop용. iOS는 MCP가 아니라 OpenMemory의 HTTP/REST 메모리 API를 호출.

### 막히는 지점 (위험)
- **추출/갱신/진화/reflection = 모두 추가 LLM 호출.** Qwen3.6-35B-A3B(활성 ~3B MoE)의 처리량·지연·전력에 직접 비용. 완화: **턴마다 추출하지 말고 세션 종료/유휴 시 배치(LangMem Background)**로 채팅 응답 지연을 0 유지.
- **tool-calling 신뢰도.** 35B급 로컬 MoE는 큰 모델보다 메모리 편집용 함수호출 신뢰도가 낮음 → MemGPT식 '에이전트 자율 self-edit' 대신 **evict/요약/승급 트리거는 Swift에서 결정적으로, LLM은 추출·요약·중요도 판정만** 맡기는 하이브리드. server-gate로 함수콜 안정성 실측 후 의존.
- **ADD/UPDATE/DELETE/NOOP 정확도.** 코사인 임계치(룰) 1차 필터 후 모호한 케이스만 LLM에 위임해 호출·오류 절감.
- **메모리 무한 비대화.** 단일 기기에서 메모리가 끝없이 커짐 → OpenMemory decay/reinforce, cognee memify(프루닝), 또는 글자수 제한 core block, SwiftMem식 주기 클러스터 재조직으로 통제.
- **factual drift / 투명성.** 자동 추출 메모리는 사용자가 항상 조회·편집·삭제 가능해야(ChatGPT audit-trail 논란 그대로 적용). + 배치 추출로 드리프트 완화.
- **벤치마크 수치 신뢰성.** 벤더 LoCoMo 점수(Zep 84% ↔ mem0 58% 등)는 방법론 논쟁 → 절대 수치 아닌 아키텍처 특성으로 판단.

---

## 권장 채택안

PocketLlama 단계적 적용 경로(우선순위 = 권장 순서). 난이도 상=어려움/중=보통/하=쉬움.

| 우선순위 | 채택안 | 난이도 | 선행조건 |
|---|---|---|---|
| **1** | **슬라이딩 윈도우 + 요약 버퍼** (베이스라인, 인프라 0) — 최근 k턴 Swift 결정적 유지 + 토큰 임계 초과 시 llama-server 1회 재귀 요약 | 하 | 없음(현재 채팅 클라이언트 위 즉시). 토큰 카운팅·임계 설정만 |
| **2** | **소형 구조화 user profile** (Letta core block + LangMem profile) — 고정 스키마 JSON을 system 프롬프트 상주, 사용자 편집 가능한 메모리 페이지 노출 | 하 | UserDefaults 또는 작은 SQLite. 프로필 스키마 정의(이름/직업/말투/금기). 투명 UI |
| **3** | **장기 메모리: Mem0 패턴 + Generative Agents 검색공식 on SQLite** — 세션 종료 시 salient fact 배치 추출(JSON) → SQLite(sqlite-vec/FTS5) 저장, 검색 = relevance(코사인)+recency(지수감쇠)+importance(사전부여) top-N 주입 | 중 | llama.cpp `/v1/embeddings` 검증. SQLite+sqlite-vec/FTS5(또는 VecturaKit). 배치 추출 프롬프트. 하이브리드 파라미터(벡터 0.6/BM25 0.4, 512토큰 청크/100 overlap, content-hash dedup) |
| **4** | **시간성: bi-temporal '삭제 대신 무효화'** (Zep/OpenMemory 경량 차용) — fact 테이블에 `valid_from`/`valid_to` 추가, 모순 사실 시 옛 행 무효화로 이력 보존 | 중 | #3의 SQLite 스키마. ADD/UPDATE/DELETE/NOOP 판정(룰 1차 필터 + 모호 케이스만 LLM) |
| **5** | **Consolidation/프로필 형성** (MemoryOS heat 승급 + ChatGPT 'dreaming'을 로컬 배치로) — 앱 유휴/충전 중 배치 요약, heat 카운터(무LLM)로 자주 언급 사실을 long-term 프로필 승격, Generative Agents reflection으로 raw→추상 계층화 | 중 | #3·#4 가동. iOS 백그라운드 작업(충전/유휴 트리거). decay/reinforce로 비대화 통제 |
| (선택) | **Mac 사이드카 셀프호스트** (mem0 self-host / OpenMemory MCP) — 검증된 엔진에 추출·합병·하이브리드 검색 위임, Swift는 URLSession REST만 | 상 | Mac 상시 가동, Docker, llama.cpp를 LLM/임베딩으로 지정. tool-calling/임베딩 실측. 직접 구현(#3~5) 부담이 클 때만 |
| (게이트) | **메모리 회상 회귀 테스트** — LoCoMo류 미니 멀티세션 QA 셋으로 'fact 회상률' 정량 추적 | 중 | 기존 server-gate/QA 하네스 확장. temporal/multi-hop 정확도 측정 셋 작성 |

> **종합 권장.** #1·#2(난이도 하)를 먼저 깔아 컨텍스트 초과를 막고 항상-켜진 개인화의 최소 형태를 확보 → #3(ROI 최고)로 장기 메모리를 SQLite+로컬 임베딩으로 구축 → #4·#5로 시간성·consolidation을 얹는다. **그래프 메모리(Mac 사이드카 풀스택)는 직접 구현이 한계에 부딪힐 때만** 선택. 모든 추출/임베딩/검색이 Mac+iOS 로컬에서 완결 → 외부 클라우드 0, 프라이버시 목표 충족.

---

## 참고자료

**오픈소스 메모리 프레임워크**
- [Mem0: Building Production-Ready AI Agents with Scalable Long-Term Memory (arXiv 2504.19413)](https://arxiv.org/abs/2504.19413) · [arXiv HTML](https://arxiv.org/html/2504.19413v1)
- [State of AI Agent Memory 2026 — mem0 blog](https://mem0.ai/blog/state-of-ai-agent-memory-2026)
- [Mem0: An open-source memory layer for LLM applications — InfoWorld](https://www.infoworld.com/article/4026560/mem0-an-open-source-memory-layer-for-llm-applications-and-ai-agents.html)
- [AI Memory Research: 26% Accuracy Boost for LLMs | Mem0](https://mem0.ai/research-3)
- [mem0ai/mem0 GitHub](https://github.com/mem0ai/mem0)
- [Memory Blocks: The Key to Agentic Context Management — Letta](https://www.letta.com/blog/memory-blocks)
- [Agent Memory: How to Build Agents that Learn and Remember — Letta](https://www.letta.com/blog/agent-memory)
- [Core memory | Letta Docs](https://docs.letta.com/guides/ade/core-memory/)
- [Letta (MemGPT) Walkthrough: How Self-Managing Agent Memory Works — SurePrompts](https://sureprompts.com/blog/letta-memgpt-walkthrough)
- [MemGPT: Towards LLMs as Operating Systems](https://www.leoniemonigatti.com/papers/memgpt.html)
- [Adding memory to LLMs with Letta — Terse Systems](https://tersesystems.com/blog/2025/02/14/adding-memory-to-llms-with-letta/)
- [Zep: A Temporal Knowledge Graph Architecture for Agent Memory (arXiv 2501.13956)](https://arxiv.org/abs/2501.13956) · [arXiv HTML](https://arxiv.org/html/2501.13956v1)
- [Graphiti: Knowledge graph memory for an agentic world — Neo4j](https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/)
- [How Cognee Builds AI Memory for Agents — cognee](https://www.cognee.ai/blog/fundamentals/how-cognee-builds-ai-memory)
- [From RAG to Graphs: How Cognee is Building Self-Improving AI Memory — Memgraph](https://memgraph.com/blog/from-rag-to-graphs-cognee-ai-memory)
- [Long-term Memory in LLM Applications — LangMem Conceptual Guide](https://langchain-ai.github.io/langmem/concepts/conceptual_guide/)
- [A-MEM: Agentic Memory for LLM Agents (arXiv 2502.12110)](https://arxiv.org/abs/2502.12110)
- [GitHub — agiresearch/A-mem](https://github.com/agiresearch/a-mem)
- [Memory OS of AI Agent (arXiv 2506.06326)](https://arxiv.org/html/2506.06326v1)
- [BAI-LAB/MemoryOS GitHub](https://github.com/BAI-LAB/MemoryOS)
- [Memoria: A Scalable Agentic Memory Framework for Personalized Conversational AI (arXiv 2512.12686)](https://arxiv.org/abs/2512.12686)
- [SwiftMem: Fast Agentic Memory via Query-aware Indexing (arXiv 2601.08160)](https://arxiv.org/abs/2601.08160)
- [Enabling Personalized Long-term Interactions in LLM-based Agents through Persistent Memory and User Profiles (arXiv 2510.07925)](https://arxiv.org/pdf/2510.07925)
- [Generative Agents: Interactive Simulacra of Human Behavior (arXiv)](https://arxiv.org/pdf/2304.03442) · [ACM full text](https://dl.acm.org/doi/fullHtml/10.1145/3586183.3606763)

**Swift / 로컬-퍼스트 부품**
- [GitHub — rryam/VecturaKit](https://github.com/rryam/VecturaKit)
- [sqliteai/sqlite-memory GitHub](https://github.com/sqliteai/sqlite-memory)
- [SQLite-AI — On-device inference and embeddings inside SQLite](https://www.sqlite.ai/sqlite-ai)
- [Local-First RAG: Using SQLite for AI Agent Memory — PingCAP](https://www.pingcap.com/blog/local-first-rag-using-sqlite-ai-agent-memory-openclaw/)
- [GitHub — CaviraOSS/OpenMemory](https://github.com/CaviraOSS/OpenMemory)
- [Introducing OpenMemory MCP — mem0](https://mem0.ai/blog/introducing-openmemory-mcp)
- [Self-Hosting Mem0: A Complete Docker Deployment Guide — mem0](https://mem0.ai/blog/self-host-mem0-docker)

**프로덕션 메모리(ChatGPT / Claude) 분석**
- [Memory and new controls for ChatGPT — OpenAI](https://openai.com/index/memory-and-new-controls-for-chatgpt/)
- [OpenAI is rolling out a major upgrade to ChatGPT memory — Neowin](https://www.neowin.net/news/openai-is-rolling-out-a-major-upgrade-to-chatgpt-memory/)
- [How ChatGPT Remembers You — Embrace The Red](https://embracethered.com/blog/posts/2025/chatgpt-how-does-chat-history-memory-preferences-work/)
- [I really don't like ChatGPT's new memory dossier — Simon Willison](https://simonwillison.net/2025/May/21/chatgpt-new-memory/)
- [Comparing the memory implementations of Claude and ChatGPT — Simon Willison](https://simonwillison.net/2025/Sep/12/claude-memory/)
- [Memory tool — Claude API Docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)
- [Use Claude's chat search and memory — Claude Help Center](https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context)

**비교·벤치마크·큐레이션**
- [Mem0 vs Letta (MemGPT): AI Agent Memory Compared — Vectorize](https://vectorize.io/articles/mem0-vs-letta)
- [Best AI Agent Memory Frameworks in 2026 — Atlan](https://atlan.com/know/best-ai-agent-memory-frameworks-2026/)
- [Best AI Agent Memory Systems in 2026: 8 Frameworks Compared — Vectorize](https://vectorize.io/articles/best-ai-agent-memory-systems)
- [ConversationSummaryBufferMemory — LangChain docs](https://reference.langchain.com/python/langchain-classic/memory/summary_buffer/ConversationSummaryBufferMemory)
- [Conversational Memory for LLMs with Langchain — Pinecone](https://www.pinecone.io/learn/series/langchain/langchain-conversational-memory/)
- [NirDiamant/Agent_Memory_Techniques GitHub](https://github.com/NirDiamant/Agent_Memory_Techniques)
- [Memory for Autonomous LLM Agents: Mechanisms, Evaluation, and Emerging Frontiers (arXiv 2603.07670)](https://arxiv.org/html/2603.07670v1)
- [TeleAI-UAGI/Awesome-Agent-Memory GitHub](https://github.com/TeleAI-UAGI/Awesome-Agent-Memory)
