# 리서치: 에이전틱 능력 — 툴·RAG·함수호출(로컬/소형 모델)

> 작성일: 2026-06-08 · 대상: **PocketLlama** (iOS SwiftUI 클라이언트 + Mac `llama.cpp`(`llama-server`)로 서빙하는 Qwen3.6-35B-A3B(MoE, 활성 ~3B), Anthropic 호환 `/v1/messages` SSE)
> 목표: "순수 채팅 클라이언트(메모리/툴/RAG 전무, UserDefaults 수준 영속)"를 **개인화 에이전트**로 고도화. 제약: 단일 사용자 · 프라이버시 우선(외부 클라우드 의존 최소화) · 원격 추론(온디바이스 아님) · 1인 개발.

---

## 한눈에 요약

- **tool-use 역량의 병목은 모델 지능이 아니라 운영층(템플릿·thinking 보존·인자 직렬화)이다.** Qwen3-30B-A3B류 소형 MoE는 BFCL-v2 ~76%(`Qwen3-Coder-30B-A3B` 76.63%)로 Llama-3.3-70B(77.30%)·Claude Sonnet 4.5(74.30%)·GPT-4o(71.70%)와 동급이다. 즉 PocketLlama가 쓰는 35B-A3B의 함수호출 역량 자체는 충분하고, 실패는 거의 전부 GGUF 배포의 chat template·직렬화 결함에서 온다.
- **PocketLlama의 정확한 모델 계열(Qwen3.5/3.6-35B-A3B)에 직격하는 실재 버그가 3종 있다.** (a) tool-call chat template이 `tool_call.arguments | items`를 타입체크 없이 호출해 `--jinja` 시 500/크래시(issue #19872, #13516), (b) `preserve_thinking` 누락 시 멀티턴에서 빈 인자 `{}` tool-call 무한 루프(earendil-works/pi #3325), (c) llama.cpp 버전에 따라 `tool_calls[].arguments`가 string↔object로 흔들리는 OpenAI 호환 회귀(#20198). 전부 모델 교체 없이 서버 플래그+커뮤니티 패치 템플릿+클라이언트 방어로 완화 가능하다.
- **llama.cpp는 PocketLlama가 붙는 그 경로(/v1/messages)에서 tool_use/tool_result content block을 이미 지원한다(PR #17570).** 따라서 서버 재작성 없이 Swift 측 content block 디코딩만 추가하면 tool-use 에이전트로 승급된다. `count_tokens` 엔드포인트로 컨텍스트 예산 관리도 가능. 단 tool use에는 반드시 `--jinja`가 필요하다.
- **개인 RAG의 실전 스택은 SQLite(FTS5 + sqlite-vec/sqlite-vector) + llama.cpp 임베딩(`/embedding`)으로 수렴한다.** 저장·검색이 단일 `.sqlite` 파일에서 완결되고, 임베딩은 같은 스택을 재사용하므로 외부 클라우드 0. 검색 품질은 dense 단독으론 부족해 dense+BM25 하이브리드(RRF)+리랭킹, Anthropic Contextual Retrieval(청크당 50~100토큰 문맥 prepend)이 recall@20 실패율을 최대 67%까지 낮춘다.
- **소형/로컬 모델의 에이전트 루프 한계는 하네스로 막는다.** ReAct 3대 실패(계획 포기·툴 반복·구문 실패)와 20K 토큰 초과 시 형식 표류가 핵심이며, 완화책은 모델이 아니라 클라이언트 측 loop/dedup 감지·per-tool circuit breaker·제약 디코딩(GBNF/json_schema)에 있다. Qwen 계열은 특히 툴 반복에 취약.
- **MCP·Mem0/Letta 같은 Python 프레임워크는 Swift에 직접 못 붙으므로 '패턴만 차용해 직접 구현'이 현실적이다.** MCP 도구·메모리·임베딩 RAG는 모두 Mac 측 llama.cpp 스택에 격리 호스팅하고, iOS 앱엔 tool(`search_notes` 등)로만 노출하면 프라이버시 + Swift 변경 최소를 동시에 달성한다.

---

## 조사한 접근·사례

| 이름 | 종류 | 핵심 메커니즘 | 성숙도 | PocketLlama 관련성 |
|---|---|---|---|---|
| **llama.cpp 서버 tool-calling (`--jinja`)** | 프레임워크 | `--jinja`로 모델별 native 핸들러(Qwen2.5/Coder, Hermes, Llama3.x 등) 인식, 미인식 시 generic 폴백. `parallel_tool_calls` 기본 off | 프로덕션 | tool 쓰려면 반드시 `--jinja` 기동. native 핸들러 유무·KV 양자화가 곧 신뢰성. 순수 채팅→tool-use 첫 관문 |
| **llama.cpp Anthropic Messages API (`/v1/messages`)** | 프레임워크 | PR #17570로 추가. Anthropic→OpenAI 변환 후 기존 파이프라인 재사용. tool_use/tool_result content block, SSE, vision, thinking 지원 | 신흥 | PocketLlama 핵심 경로 그 자체. content block 디코딩만 추가하면 서버 재작성 없이 승급. `count_tokens`로 예산 관리 |
| **GBNF lazy 문법 + JSON healer** | 기법 | JSON Schema→GBNF 변환, tool-call 접두사 감지 시 제약 디코딩 트리거. PEG 파서가 스트림 상태 유지, 부분 JSON을 healer로 valid화 | 프로덕션 | 제약 디코딩 켜지면 소형 MoE라도 인자 스키마 위반 격감. 단 '부분 tool call 델타 후 에러'·미완 JSON을 Swift가 방어해야 |
| **Qwen3.5/3.6 GGUF tool-call 템플릿 버그** | 프로젝트 | 원본 템플릿이 `tool_call.arguments \| items`를 dict 가정으로 호출→실패. `is mapping` 체크 후 키 순회로 패치(froggeric/unsloth 드롭인 템플릿) | 신흥 | 기본 내장 템플릿 신뢰 금지. `--chat-template-file`로 패치본 명시 주입 필수. 게이트에 'tool_use 1턴' 추가 근거 |
| **Qwen3.6 멀티턴 빈-인자 `{}` 루프** | 프로젝트 | `preserve_thinking=true` 누락 시 이전 `<think>` 폐기→직전 추론 컨텍스트 상실→'무엇을'은 알아도 '어떤 인자로'를 잃음. `chat_template_kwargs`로 보존(픽스 #3325) | 신흥 | Qwen3.6 멀티턴 tool-use 시 거의 확실히 마주칠 함정. 요청에 `preserve_thinking:true` 전달 설계 필요 |
| **tool_calls arguments object↔string 직렬화 버그 (#20198)** | 프로젝트 | PR #18675 리팩터가 `json::parse(arguments)`로 문자열 대신 객체 반환→OpenAI SDK `TypeError`. 수정 PR #20213 진행 중 | 실험적 | Swift 자체 파서라 SDK 크래시는 무관하나, 버전 따라 형태가 흔들림 → string/object 이중 허용 디코더 필요. 버전 고정 근거 |
| **Qwen3-30B-A3B tool-use 실측 (BFCL-v2 ~76%)** | 논문 | `Qwen3-Coder-30B-A3B` BFCL-v2 76.63%로 70B급 경쟁. BFCL 채점도 2025-06 chat template 버그 수정 이력(템플릿 민감) | 프로덕션 | 35B-A3B의 tool-use 역량 자체는 충분 → 병목은 운영층. BFCL 채점조차 템플릿 민감 = 신뢰성도 템플릿 정합성에 달림 |
| **GBNF/json_schema 제약 디코딩 (구조 강제)** | 기법 | 샘플링 중 문법 위반 토큰 마스킹. tool-calling 시 스키마가 프롬프트에도 주입. JSON schema 부분집합만 지원(PCRE 금지, #22314), 토큰 잘림 시 보장 깨짐 | 널리 사용 | 서버가 llama.cpp라 즉시 활용. tool-call 형식 위반을 서버단 1차 차단. `grammar`/`json_schema`를 호출에 실음 |
| **ReAct 루프 실패 3종 (계획포기·툴반복·구문실패)** | 기법 | 단일 글로벌 retry 카운터가 hallucinated tool name에 retry 슬롯 낭비(90.8%). Qwen·Ollama 계열이 툴 반복에 특히 취약 | 프로덕션 | ReAct 그대로 쓰면 안 된다는 경고. 반복·계획포기 탐지를 Swift 루프 컨트롤러에 구현해야 |
| **구조화 ReAct (error taxonomy + per-tool circuit breaker)** | 패턴 | 에러를 재시도가능/불가능 분류, 영구 에러는 retry 0 소모. 툴별 circuit breaker(3실패→open, probe 2성공→close). retry 낭비 0% | 신흥 | ChatState 상태머신에 enum/카운터로 이식 가능한 설계도. TOOL_NOT_FOUND·INVALID_INPUT 즉시중단이 핵심 |
| **KodeAgent (SLM≤8B function-calling)** | 프레임워크 | consecutive-call 카운터+nudge('다른 쿼리 시도'), 동일 인자 dedup 캐시, 페이지 truncation, 네이티브 function-calling 활용 | 실험적 | 35B-A3B가 정확히 이 SLM 시나리오. dedup 캐시·truncation을 Swift에 바로 이식 |
| **Qwen-Agent (캐노니컬 Qwen3 함수호출)** | 프레임워크 | Hermes-style tool use 포맷이 chat template에 내장. 파서가 raw text에서 인자 추출하나 **디코딩 중 schema 제약 미적용**→malformed 가능 | 널리 사용 | llama-server 직타라 그대로 못 쓰나, '서버 파싱 불완전 가능 → 클라이언트가 스키마 재검증' 교훈 직결 |
| **로컬 LLM tool-calling 실측 (13/40 케이스)** | 논문 | Qwen3.5 4B(3.4GB) 97.5% 1위. 모델 크기↔품질 상관 약함. tool 특화 모델이 chat template 호환성으로 15~42% 저조. 병렬화 역설 | 프로덕션 | (1) 템플릿/파서 불일치 시 tool-call 통째 실패 가능, (2) 순차 의존 작업을 병렬 발사로 의존성 무시 위험 → 강제 직렬화 |
| **Qwen3 에이전트 실측 (30B-A3B/32B 형식 표류)** | 논문 | Qwen3-32B first-attempt 툴 식별 ~87%. 20K 토큰 초과 시 형식 표류가 주 실패. thinking은 계획 결정에만 선택 적용→토큰 ~40% 절감 | 신흥 | 정확히 A3B MoE 계열 실측. 컨텍스트 압축+system prompt 포맷 예시 고정 필수. thinking 선택 사용은 원격추론 지연/배터리 직결 |
| **Structured Reflection (2509.18847)** | 논문 | Reflect→Call→Final로 실패 진단 후 후속 호출 제안. '인자 복구보다 올바른 툴 선택이 더 어렵다' | 실험적 | fine-tuning은 어려우나 프롬프트 레벨 Reflect→Call→Final만 차용 가능. 툴 5~8개 이하·설명 명확화 근거 |
| **τ-bench / τ²-bench / BFCL-v4** | 논문 | 멀티턴 정책준수·dual-control. '중간 출력 하나가 탈선', '자율→유저안내 전환 시 pass rate ~20% 급락'. trust scoring+fallback로 실패율 최대 50%↓ | 널리 사용 | 신뢰도 낮거나 비가역적 tool-call은 유저 승인 게이팅 근거. human-in-the-loop 폴백 필수 |
| **sqlite-vec / sqlite-vector** | 프레임워크 | `vec0` 가상 테이블에 float32 BLOB(768d=3KB) 저장, `vec_distance_cosine` KNN. document/chunk/vec_items 3테이블 + SHA2 증분. sqlite-vector는 iOS/Swift 공식 지원·HNSW | 프로덕션 | UserDefaults 대신 온디바이스 코퍼스 인덱스. float32가 플랫폼 호환이라 Mac DB를 iPhone에서 그대로 읽음 |
| **llama.cpp `/embedding` + Arctic-embed-M** | 기법 | `--embeddings`로 별도 인스턴스 기동, POST `/embedding`(또는 `/v1/embeddings`)이 768d 벡터 반환. 채팅/임베딩 모델 분리 서빙 권장 | 프로덕션 | '클라우드 의존 최소화' 완전 충족. Swift는 URLSession으로 `/embedding`만 추가 호출 |
| **EmbeddingGemma 308M** | 제품 | Gemma 3 기반 온디바이스 임베딩, 100+ 언어(한국어). MRL로 768/256/128d truncate, QAT로 <200MB RAM. GGUF 변환 존재 | 프로덕션 | 진짜 온디바이스 임베딩 1순위. 256d truncate로 iPhone 인덱스 1/3. 한국어 노트/메시지 유리 |
| **Anthropic Contextual Retrieval** | 기법 | 청크마다 소형 LLM으로 50~100토큰 문맥 생성·prepend. recall@20 실패율: Contextual Embeddings 35%↓, +BM25 49%↓, +리랭킹 67%↓ | 널리 사용 | 짧은 개인 노트·메시지에 특효(짧을수록 문맥 소실 큼). 문맥 생성을 로컬 Qwen3로 대체해 프라이버시 유지 |
| **Dense+BM25 하이브리드 (RRF)** | 패턴 | dense cosine top-k + BM25 top-k를 Reciprocal Rank Fusion으로 융합, 리랭커로 top-20. 고유명사·ID·기술용어 보완 | 널리 사용 | 코퍼스에 사람이름·날짜·앱이름 많아 dense 단독 취약. SQLite FTS5(BM25 내장)+sqlite-vec를 한 DB에서 결합 |
| **Obsidian Smart Connections** | 프로젝트 | 양자화 all-MiniLM(~25MB)을 TransformersJS(WASM/ONNX)로 로컬 실행. 임베딩은 worker thread로 분리(UI 멈춤 방지) | 널리 사용 | 노트 RAG 레퍼런스. 교훈: 25MB급이면 모바일 충분, 임베딩은 반드시 백그라운드(SwiftUI Task/actor) |
| **Mem0 / Letta(MemGPT) 메모리 계층** | 프레임워크 | episodic/semantic/procedural 3분류. Mem0는 추출+벡터/그래프 인출(p95 지연 91%↓·토큰 90%↓ 주장). Letta는 core/archival/recall | 프로덕션 | RAG '검색'과 구분되는 '기억'. Python이라 직접 못 붙음 → core(시스템 프롬프트)+archival(sqlite-vec) 패턴만 차용 |
| **에이전틱 RAG + FunctionGemma** | 패턴 | LLM이 '언제·어떻게 검색할지' 결정. 날짜·발신자 필터+벡터검색 결합. CRM/연락처는 '1 레코드=1 문서' | 신흥 | '지난주 메일' 같은 시간·필드 질의는 순수 임베딩 불가→Qwen3 tool-calling으로 검색 함수 정의. FunctionGemma 불요 |
| **로컬 LLM + MCP 스택 (OpenMemory MCP, mcp-agent)** | 프레임워크 | MCP='AI용 USB-C'. OpenMemory MCP는 Mem0+Docker+Postgres+Qdrant 로컬, 외부전송 0. mcp-agent는 연결·HITL·durable execution 추상화 | 신흥 | 개인화 청사진. MCP는 Mac에 격리, iOS는 `/v1/messages`만 알면 됨(복잡도 서버 격리) |
| **MeMemo (온디바이스 검색 증강)** | 논문 | ANN/HNSW 인덱스를 클라이언트 런타임(웹/WASM)으로 이식, 데이터가 기기를 안 떠남 | 실험적 | 프라이버시 우선 철학과 정확 일치. '검색까지 온디바이스, 추론은 내 Mac' 구도 정당화 |

### 상세 1 — llama.cpp Anthropic Messages API + tool-calling (PocketLlama 핵심 경로)

llama-server는 2025~2026년에 걸쳐 OpenAI 호환 tool-calling과 Anthropic 호환 `/v1/messages`(PR #17570)를 모두 갖췄다. 핵심 메커니즘은 `--jinja` 플래그로 모델 고유 chat template을 켜고, 응답에서 `tool_calls`를 파싱하는 것이다. Anthropic 경로는 내부적으로 Anthropic 포맷을 OpenAI 포맷으로 변환해 기존 추론 파이프라인을 재사용하며, tool use는 content block 방식(클라이언트가 `tools` 스키마 정의 → 모델이 `tool_use` 블록 응답 → 클라이언트가 `tool_result` 블록으로 결과 회수 → 멀티턴 연결)으로 동작한다. SSE는 `message_start`·`content_block_delta` 등 Anthropic 이벤트 타입을 따르고, `count_tokens` 엔드포인트로 컨텍스트 예산도 관리할 수 있다.

- **장점:** PocketLlama가 이미 이 경로에 붙어 있으므로 **서버 재작성 없이** Swift 측 content block 디코딩만 추가하면 tool-use 에이전트로 승급된다. native 핸들러(Qwen2.5/Coder, Hermes 등)가 인식되면 generic 폴백 대비 토큰 효율·정확도가 높다.
- **단점/함정:** tool use에는 **반드시 `--jinja`** 가 필요하다. 'full Anthropic spec 호환'을 강하게 주장하진 않으며(많은 앱에 충분한 수준), `parallel_tool_calls`는 기본 off라 payload에서 명시해야 한다. **극단적 KV 양자화(`-ctk q4_0` 등)는 tool-calling 성능을 크게 떨어뜨린다는 공식 경고**가 있다.

### 상세 2 — Qwen3.5/3.6 GGUF chat template 버그 3종 (PocketLlama 직격 리스크)

PocketLlama가 서빙하는 모델이 정확히 Qwen3.6-35B-A3B라, 다음 3종이 즉각적·실재적이다.

1. **tool-call 템플릿 크래시(#19872, #13516):** `tools` 파라미터를 보내면 `--jinja` 없이는 거부되고, `--jinja`를 켜면 `tool_call.arguments | items`를 타입체크 없이 호출해 `Unknown (built-in) filter items for type String` 같은 minja 엔진 불일치로 500을 반환한다. 수정은 `{%- if tool_call.arguments is mapping %}` 체크 후 `| items` 대신 키 순회. 커뮤니티 드롭인 템플릿(froggeric/Qwen-Fixed-Chat-Templates, unsloth)이 주 버그 외 다수 추가 버그까지 패치한다. **운영법:** `--chat-template-file`로 패치본을 명시 주입.
2. **멀티턴 빈-인자 `{}` 루프(earendil-works/pi #3325, 2026-04):** `chat_template_kwargs`에 `preserve_thinking=true`가 없으면 이전 턴 `<think>` 블록을 폐기한다. 2~3턴 후 모델은 '무엇을 호출할지'는 올바로 추론하나 직전 추론 컨텍스트를 잃어 '어떤 인자로'를 상실, 빈 인자 호출을 양산한다. **픽스:** 요청 params에 `chat_template_kwargs = { enable_thinking: !!reasoningEffort, preserve_thinking: true }` 주입.
3. **arguments object↔string 직렬화 회귀(#20198):** PR #18675의 파서 리팩터가 `arguments`를 문자열 유지 대신 파싱해 객체로 반환, 공식 OpenAI SDK가 `TypeError`로 크래시. 수정 PR #20213 진행 중. Swift 자체 파서라 SDK 크래시는 무관하나, **버전에 따라 형태가 흔들리므로 string/object 이중 허용 디코더가 필요**하다.

- **교훈:** 세 버그 모두 모델 교체 없이 **서버 플래그(`--jinja`)+패치 템플릿(`--chat-template-file`)+버전 고정+클라이언트 방어 디코딩**으로 완화된다. server-gate 스모크에 'tools 포함 1턴 왕복'과 'arguments 직렬화 형태' 검증을 추가할 강한 근거.

### 상세 3 — 소형/로컬 모델의 에이전트 루프 하네스 (Swift 클라이언트가 담당)

소형 모델의 에이전트 한계는 (1) 구조화 출력 형식 위반, (2) ReAct 루프 불안정(계획 포기·툴 반복·무한 루프), (3) 컨텍스트 성장에 따른 형식 표류로 군집화된다. Qwen·Ollama 계열은 특히 **툴 반복**(같은 호출 반복 중임을 인지 못함)에 취약하고, Qwen3-32B/30B-A3B는 **히스토리 20K 토큰 초과 시 형식 표류**로 tool-call이 깨진다. 핵심은 완화책이 모델이 아니라 클라이언트 하네스에 있다는 점이다.

- **이식할 패턴:** KodeAgent의 consecutive-call 카운터+nudge·동일 인자 dedup 캐시·페이지 truncation, 구조화 ReAct의 per-tool circuit breaker(3실패→open, probe 2성공→close)와 에러 분류(`TOOL_NOT_FOUND`·`INVALID_INPUT` 즉시중단), hard cap(`MAX_STEPS`)+repetition detector. 이들은 기존 `ChatState` 상태머신에 enum/카운터로 자연 확장된다.
- **형식 표류 완화:** system prompt에 tool-call 포맷 예시 고정 + 긴 멀티턴 컨텍스트 압축/요약 + thinking은 계획 결정에만 선택 적용(토큰 ~40% 절감, 원격추론 지연/배터리 직결). 툴 개수 5~8개 이하 유지(`인자 복구보다 툴 선택이 더 어렵다` — 2509.18847).
- **장점/단점:** 서버 무변경으로 신뢰성을 크게 올리나, fine-tuning이 불가능한 1인 개발이라 Structured Reflection은 **학습이 아닌 프롬프트 레벨 Reflect→Call→Final 패턴으로만** 차용해야 한다.

### 상세 4 — 개인 RAG 스택 (SQLite + llama.cpp 임베딩 + 하이브리드 검색)

소규모 개인 코퍼스 RAG의 2024~2026 합의 스택은 명확하다.

- **저장·검색:** SQLite + sqlite-vec(또는 iOS/Swift 공식 지원하는 sqliteai의 sqlite-vector). `document`(경로+SHA2 해시로 변경 감지)/`document_chunk`/`vec_items` 3테이블 분리. float32 인코딩이 플랫폼 간 바이너리 호환이라 Mac에서 만든 DB를 iPhone에서 그대로 읽는다. SQLite **FTS5(BM25 내장)** 를 같은 DB에 두면 추가 의존성 없이 dense+BM25 하이브리드를 RRF로 구현한다.
- **임베딩:** 단기적으론 Mac llama-server에 임베딩 전용 인스턴스(`--embeddings`, 다른 포트)를 띄워 Arctic-embed-M(768d)/EmbeddingGemma로 생성, Swift는 `/v1/embeddings`만 추가 호출. 진짜 온디바이스가 목표면 EmbeddingGemma를 256d로 truncate(MRL)해 Core ML/ONNX로 iPhone에서 직접 임베딩(저장 1/3·한국어 지원).
- **품질:** Contextual Retrieval(청크당 50~100토큰 문맥 prepend, 문맥 생성을 로컬 Qwen3로)이 짧은 개인 노트에 특효이며, dense+BM25+리랭킹과 결합 시 recall@20 실패율을 최대 67% 낮춘다. 캘린더/연락처는 '1 레코드=1 문서', 10~20% 오버랩.
- **주의:** 임베딩 모델을 바꾸면 차원·벡터공간 불일치로 **전체 재인덱싱**이 필요(모델 버전을 DB에 기록). 온디바이스 임베딩은 반드시 백그라운드 actor/Task로(Smart Connections 교훈). Contextual Retrieval은 인제스트 시 청크당 LLM 1회 호출이라 1인 코퍼스(수천 청크)에서만 현실적.

---

## PocketLlama 환경 적용성

우리 스택: **Swift(URLSession) 클라이언트 + Mac llama.cpp(llama-server) + Qwen3.6-35B-A3B + UserDefaults 영속 + 단일 사용자 · 원격추론 · 1인 개발**.

### 쉬운 것 (스택과 정합, 즉시/소규모 작업)

- **tool-use 경로 자체.** `/v1/messages`가 tool_use/tool_result content block을 이미 지원하므로(PR #17570), Swift는 content block 디코딩만 추가하면 된다. 서버 재작성 불요. native 핸들러(Qwen) 인식으로 generic 폴백 비효율도 회피.
- **서버단 형식 강제.** 서버가 llama.cpp라 `grammar`/`json_schema` 제약 디코딩을 `/v1/messages` 호출에 실어 tool-call 인자 형식을 디코딩 레벨에서 1차 차단할 수 있다.
- **로컬 임베딩 RAG 배선.** llama-server에 `--embeddings` 인스턴스를 다른 포트로 추가하고 Swift가 `/v1/embeddings`만 호출하면 끝. 동일 스택 재사용 → '클라우드 의존 최소화' 제약을 완벽 충족.
- **루프 컨트롤러 이식.** consecutive-call 카운터·dedup 캐시·circuit breaker·hard cap은 전부 결정적 Swift 코드라 기존 `ChatState` 상태머신에 enum/카운터로 자연 확장된다(외부 라이브러리 불요).
- **단일 사용자 단순성.** `RATE_LIMITED`·멀티테넌시·동시성 경쟁이 사실상 없어 에러 분류·메모리 스코프가 단순해진다.

### 어려운 것 (가능하나 설계·작업량 큼)

- **Swift 방어적 파서.** SSE 스트리밍에서 (a) `arguments` string↔object 이중 허용(string이면 재파싱, object면 그대로), (b) '부분 tool call 델타 후 에러'·미완 JSON 안전 처리(llama.cpp JSON healer/PEG 부분 파싱의 알려진 불일치)를 모두 견뎌야 한다.
- **멀티턴 thinking 보존.** Qwen3.6 빈-인자 루프를 막으려면 요청에 `chat_template_kwargs`로 `preserve_thinking:true`를 전달해야 하는데, thinking 보존은 컨텍스트·지연·배터리 비용을 키운다 → UserDefaults 수준을 넘는 대화 히스토리 관리·압축 전략과 동반돼야 한다.
- **영속 이행.** UserDefaults는 벡터 저장에 부적합 → SQLite(sqlite-vec/FTS5) 파일로 이행이 선행 필수. 온디바이스 임베딩은 백그라운드 actor/Task 분리가 필수(UI 멈춤 방지).
- **에이전틱 RAG의 시간·필드 질의.** '지난주 메일'류는 순수 임베딩으론 불가, Qwen3 tool-calling으로 날짜·발신자 필터+벡터검색 함수를 정의해야 한다 → tool-use 인프라가 선행돼야 성립.

### 막히는 지점 (사전 차단·검증 필요)

- **chat template × tool-call 호환성(최대 단일 실패점).** Qwen3.5/3.6은 `tools` 파라미터를 실으면 llama.cpp Jinja 버그(`Unknown filter items`, `--jinja` 미설정 거부)로 **500을 뱉을 수 있다**(#19872, #13516). 기본 내장 템플릿을 그대로 쓰면 tool 호출이 깨질 가능성이 크다 → `--jinja` + 검증된 `--chat-template-file`(froggeric/unsloth 패치본)이 필수.
- **긴 멀티턴 형식 표류.** 20K 토큰 초과 시 tool-call 형식이 깨진다 → system prompt 포맷 예시 고정 + 컨텍스트 압축이 전제.
- **순차 의존의 병렬 발사.** 로컬 모델이 시간 의존 작업(캘린더 조회→이벤트 생성)을 병렬로 발사해 의존성을 무시할 수 있다(병렬화 역설) → 클라이언트가 의존 단계를 강제 직렬화해야 한다.
- **비가역 작업 안전.** τ-bench의 '자율→유저안내 전환 시 ~20% 급락'을 근거로, 신뢰도 낮거나 비가역적(파일 삭제·메일 전송) tool-call은 유저 승인으로 게이팅(human-in-the-loop)해야 한다.
- **버전 회귀.** `arguments` 직렬화(#20198)처럼 llama.cpp 버전에 따라 계약이 흔들리므로 **버전 고정 + 게이트 검증**이 필요하다.
- **프레임워크 직접 도입 불가.** Mem0/Letta/LangChain/Qwen-Agent/mcp-agent는 전부 Python이라 Swift에 직접 못 붙는다 → '패턴만 차용해 직접 구현'이 유일한 현실적 경로(라이브러리 도입 기대 금지).

---

## 권장 채택안

> 난이도: 상(설계·작업량 큼) / 중 / 하(즉시·소규모). 우선순위는 PocketLlama의 '순수 채팅 → 개인화 에이전트' 경로에서 막힘을 먼저 제거하는 순.

| 우선 | 채택안 | 난이도 | 선행조건 |
|---|---|---|---|
| 1 | **server-gate를 tool-calling까지 확장** — `--jinja`+검증된 `--chat-template-file`(froggeric/unsloth 패치본) 기동, DoR에 'tools 포함 1턴 왕복'·'arguments 직렬화 형태(string/object)' 검증 추가, llama.cpp 버전 고정 | 하 | 별도 repo `~/workspace/dev/llm-serving`의 `serve.sh`에 `--jinja`·패치 템플릿 인자 추가 |
| 2 | **`/v1/messages` content block(tool_use/tool_result) 디코딩 추가** — Swift에 tool_use 블록 파싱 + tool_result 응답 작성, SSE 델타 누적 | 중 | 1번 게이트 통과(서버가 tool 호출을 정상 렌더) |
| 3 | **Swift 방어적 tool-call 파서** — arguments string/object 이중 허용, '부분 tool call 후 에러'·미완 JSON 안전 처리 | 중 | 2번 디코딩 골격 |
| 4 | **루프 컨트롤러 하네스** — `ChatState`에 consecutive-call 카운터·동일 인자 dedup 캐시·per-tool circuit breaker·hard cap(`MAX_STEPS`)·repetition detector를 enum/카운터로 이식 | 중 | 2·3번(tool-call 왕복이 동작) |
| 5 | **서버단 제약 디코딩** — `grammar`/`json_schema`를 `/v1/messages`에 실어 tool-call 인자 형식 강제(PCRE 금지·토큰 잘림 방어는 클라이언트 2차) | 하 | 1번(llama.cpp tool 경로 정상) |
| 6 | **멀티턴 thinking 보존** — 요청에 `chat_template_kwargs={enable_thinking, preserve_thinking:true}` 전달(빈-인자 루프 예방), thinking은 계획 결정에만 선택 적용 | 중 | 1번(서버가 kwargs 수용), 대화 히스토리 압축 전략 |
| 7 | **human-in-the-loop 폴백 + 순차 직렬화** — 비가역/저신뢰 tool-call은 유저 승인 게이팅, 의존 단계는 클라이언트가 강제 직렬화 | 중 | 4번 루프 컨트롤러 |
| 8 | **영속 이행: UserDefaults → SQLite(sqlite-vec + FTS5)** — `document`/`document_chunk`/`vec_items` 3테이블 + SHA2 증분, 모델 버전 기록 | 상 | sqlite-vec/sqlite-vector Swift 패키지 번들 |
| 9 | **로컬 임베딩 RAG** — llama-server `--embeddings` 별 인스턴스(다른 포트) + Arctic-embed-M/EmbeddingGemma, Swift `/v1/embeddings` 호출, 백그라운드 actor 임베딩 | 상 | 8번(저장소), 2~4번(검색을 tool로 노출 시) |
| 10 | **하이브리드 검색 + Contextual Retrieval** — dense+BM25(RRF)+리랭킹, 짧은 노트에 청크당 50~100토큰 문맥 prepend(로컬 Qwen3 생성) | 상 | 9번(임베딩·인덱스), 인제스트 배치 파이프라인 |
| 11 | **개인화 메모리 계층(패턴 차용)** — core(시스템 프롬프트 주입)+archival(sqlite-vec 검색), episodic/semantic 분리. Mem0/Letta는 '패턴만' | 상 | 8·9번. RAG '검색'과 메모리 '기억' 분리 설계 |

---

## 참고자료

**llama.cpp tool-calling / Anthropic API**
- [llama.cpp/docs/function-calling.md](https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md)
- [llama.cpp tools/server/README.md](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [New in llama.cpp: Anthropic Messages API (HF blog)](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp)
- [PR #17570 server: add Anthropic Messages API support](https://github.com/ggml-org/llama.cpp/pull/17570)
- [Chat Templates and Tool Calling (DeepWiki llama.cpp)](https://deepwiki.com/qualcomm/llama.cpp/8.2-chat-templates-and-tool-calling)
- [Issue #20867 MAX_REPETITION_THRESHOLD breaks tool grammars](https://github.com/ggml-org/llama.cpp/issues/20867)
- [How to use lazy grammars? (Discussion #12110)](https://github.com/ggml-org/llama.cpp/discussions/12110)

**Qwen3.5/3.6 GGUF 템플릿·직렬화 버그**
- [Qwen3.5-35B-A3B · tool calling chat template is broken (HF discussion)](https://huggingface.co/Qwen/Qwen3.5-35B-A3B/discussions/4)
- [unsloth Qwen3-Coder-30B-A3B GGUF · Chat Template + Tool Calling Fixes](https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/discussions/10)
- [Issue #3325 Qwen3.6 tool calls loop with empty arguments — preserve_thinking](https://github.com/earendil-works/pi/issues/3325)
- [unsloth Qwen3-30B-A3B-Thinking-2507-GGUF · <think> missing](https://huggingface.co/unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF/discussions/1)
- [Issue #20198 llama-server tool_calls arguments as object breaks OpenAI compat](https://github.com/ggml-org/llama.cpp/issues/20198)
- [Eval bug: Qwen 3.5 'Template supports tool calls but does not natively describe tools' — llama.cpp issue #19872](https://github.com/ggml-org/llama.cpp/issues/19872)
- [Eval bug: bizarre Jinja bug when trying to fix Qwen3 tool calling — llama.cpp issue #13516](https://github.com/ggml-org/llama.cpp/issues/13516)
- [froggeric/Qwen-Fixed-Chat-Templates — Hugging Face](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates)

**Qwen3 / 로컬 모델 tool-use 벤치·실측**
- [BFCL: From Tool Use to Agentic Evaluation (ICML 2025)](https://proceedings.mlr.press/v267/patil25a.html)
- [Qwen3-Coder BFCL eval README](https://github.com/QwenLM/Qwen3-Coder/blob/main/qwencoder-eval/tool_calling_eval/berkeley-function-call-leaderboard/README.md)
- [gorilla BFCL CHANGELOG (Qwen3 template fix 2025-06)](https://github.com/ShishirPatil/gorilla/blob/main/berkeley-function-call-leaderboard/CHANGELOG.md)
- [The Berkeley Function Calling Leaderboard (BFCL): From Tool Use to Agentic — OpenReview](https://openreview.net/pdf?id=2GmDdhBdDk)
- [Qwen3 Agent Capabilities: 8 Models Tested [2026 Review] — Kunal Ganglani](https://www.kunalganglani.com/blog/qwen3-agent-capabilities-review)
- [Qwen/Qwen3-30B-A3B-Instruct-2507 — Hugging Face](https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507)
- [I Tested 13 Local LLMs on Tool Calling | 2026 Eval Results — JD Hodges](https://www.jdhodges.com/blog/local-llms-on-tool-calling-2026-pt1-local-lm/)
- [Best Local Models for Tool Calling in 2026 — PromptQuorum](https://www.promptquorum.com/power-local-llm/best-local-models-tool-calling-2026)

**Qwen-Agent / 제약 디코딩**
- [QwenLM/Qwen-Agent — GitHub](https://github.com/QwenLM/Qwen-Agent)
- [Function Calling — Qwen 공식 문서](https://qwen.readthedocs.io/en/latest/framework/function_call.html)
- [llama.cpp grammars README — GitHub](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md)
- [Grammar and Structured Output — DeepWiki (llama.cpp)](https://deepwiki.com/ggml-org/llama.cpp/8.1-grammar-and-structured-output)
- [A Guide to Structured Generation Using Constrained Decoding — Aidan Cooper](https://www.aidancooper.co.uk/constrained-decoding/)

**에이전트 루프·실패 모드·리플렉션**
- [Common Agent Failure Modes — Agent Wiki](https://agentwiki.org/common_agent_failure_modes)
- [Your ReAct Agent Is Wasting 90% of Its Retries — Towards Data Science](https://towardsdatascience.com/your-react-agent-is-wasting-90-of-its-retries-heres-how-to-stop-it/)
- [What Happens When Your AI Agent Gets Stuck? Building Reliable Agents for SLMs — Barun Saha](https://medium.com/@barunsaha/what-happens-when-your-ai-agent-gets-stuck-building-reliable-agents-for-small-language-models-a5e7a32cd03d)
- [Failure Makes the Agent Stronger: Structured Reflection — arXiv 2509.18847](https://arxiv.org/abs/2509.18847)
- [τ²-Bench: Evaluating Conversational Agents in a Dual-Control Environment — arXiv 2506.07982](https://arxiv.org/pdf/2506.07982)
- [Automated Hallucination Correction for AI Agents: τ²-Bench case study — Cleanlab](https://cleanlab.ai/blog/tau-bench/)

**개인 RAG — 저장·임베딩·검색**
- [Local Vector Search with llama.cpp Embeddings and sqlite_vec](https://www.timestretch.com/2025/05/26/local_vector_search_with_llama_cpp_embeddings_and_sqlite_vec.html)
- [sqliteai/sqlite-vector (GitHub)](https://github.com/sqliteai/sqlite-vector)
- [SQLite-Vector - Fast vector search for embedded SQLite](https://www.sqlite.ai/sqlite-vector)
- [RAG with llama.cpp and external API services - NeuML](https://neuml.hashnode.dev/rag-with-llamacpp-and-external-api-services)
- [Building a RAG Pipeline with llama.cpp (MachineLearningMastery)](https://machinelearningmastery.com/building-a-rag-pipeline-with-llama-cpp-in-python/)
- [Implementing RAG, some questions on llama.cpp (Discussion #12125)](https://github.com/ggml-org/llama.cpp/discussions/12125)
- [Introducing EmbeddingGemma - Google Developers Blog](https://developers.googleblog.com/en/introducing-embeddinggemma/)
- [Welcome EmbeddingGemma (Hugging Face)](https://huggingface.co/blog/embeddinggemma)
- [Google AI Releases EmbeddingGemma - MarkTechPost](https://www.marktechpost.com/2025/09/04/google-ai-releases-embeddinggemma-a-308m-parameter-on-device-embedding-model-with-state-of-the-art-mteb-results/)

**RAG 품질 — Contextual Retrieval·하이브리드·온디바이스**
- [Introducing Contextual Retrieval - Anthropic](https://www.anthropic.com/news/contextual-retrieval)
- [Building Contextual RAG Systems with Hybrid Search and Reranking - Analytics Vidhya](https://www.analyticsvidhya.com/blog/2024/12/contextual-rag-systems-with-hybrid-search-and-reranking/)
- [The most effective RAG approach: Anthropic's Contextual Retrieval and Hybrid Search - Medium](https://medium.com/@odhitom09/the-most-effective-rag-approach-to-date-anthropics-contextual-retrieval-and-hybrid-search-8dc2af5cb970)
- [Smart Connections: How Obsidian Gets Semantic Search Without Breaking Mobile - Starlog](https://starlog.is/articles/data-knowledge/brianpetro-obsidian-smart-connections)
- [brianpetro/obsidian-smart-connections (GitHub)](https://github.com/brianpetro/obsidian-smart-connections)
- [On-Device RAG for App Developers: Embeddings, Vector Search, and Beyond - Medium (Google Developer Experts)](https://medium.com/google-developer-experts/on-device-rag-for-app-developers-embeddings-vector-search-and-beyond-47127e954c24)
- [MeMemo: On-device Retrieval Augmentation for Private and Personalized Text Generation (arXiv)](https://arxiv.org/pdf/2407.01972)

**MCP·메모리 계층**
- [OpenMemory MCP (mem0)](https://mem0.ai/blog/how-to-make-your-clients-more-context-aware-with-openmemory-mcp)
- [lastmile-ai/mcp-agent](https://github.com/lastmile-ai/mcp-agent)
- [I added these MCP servers to my local LLM stack (XDA)](https://www.xda-developers.com/added-these-mcp-servers-local-llm-stack-one-replaces-paid-tool/)
- [Long-Term Memory for AI Agents - Mem0](https://mem0.ai/blog/long-term-memory-ai-agents)
- [Best AI Agent Memory Frameworks in 2026 - Atlan](https://atlan.com/know/best-ai-agent-memory-frameworks-2026/)
- [NirDiamant/Agent_Memory_Techniques (GitHub)](https://github.com/NirDiamant/Agent_Memory_Techniques)
