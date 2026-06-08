# 리서치: 개인화 UX·프롬프트·평가/안전

> 작성일: 2026-06-08 · 대상: **PocketLlama** (iOS SwiftUI + Mac `llama-server` / Qwen3.6-35B-A3B, MoE 활성 ~3B)
> 스택 제약: Swift 클라이언트(URLSession) + Anthropic 호환 `/v1/messages`(SSE) + UserDefaults 수준 영속 + 단일 사용자·원격 추론·프라이버시 우선

본 문서는 세 갈래의 리서치 findings(개인화·persona 엔지니어링 / 선제적 능동성·맥락 인지 / 메모리 평가·안전)를 통합·중복제거하고, 출처 URL이 확인된 주장만 남겨 PocketLlama 적용성 관점에서 재정리한 것이다.

---

## 한눈에 요약

- **개인화의 공통 루프는 "컨텍스트 엔지니어링"으로 수렴한다.** 사용자별 영속 상태(선호·사실·페르소나)를 구조화 저장 → 매 턴 관련 슬라이스만 system 프롬프트에 주입 → 상호작용으로 갱신. PersonaAgent·Mem0·Letta(MemGPT)·OpenAI Cookbook이 같은 패턴을 공유한다.
- **PocketLlama에 현실적인 경로는 "프롬프트/RAG 계열"이다.** 단일 사용자라 데이터가 적어 RAG가 PEFT(파인튜닝)보다 비용·효과 모두 우월하다(LaMP/2409.09510). 활성치 steering(Persona Vectors·EasySteer)은 `llama.cpp` 추론 루프 개입·능력 저하 위험으로 단기 부적합.
- **선제적(proactive) 에이전트의 핵심은 "언제 끼어들지"의 게이팅이다.** ContextAgent(proactive score≥3), ProMemAssist(효용=가치−비용 >0.75) 모두 신호 추출 → 점수화 → 임계 초과만 행동의 구조. 최신 SOTA도 선제성 end-to-end 40% 천장(PROBE)이라, **트리거를 좁은 고신뢰 케이스(일정 충돌·명시 리마인더)로 제한**해야 한다.
- **iOS 백그라운드 제약 때문에 선제 아키텍처는 Mac 서버 쪽에 둔다.** `llama-server` 옆 cron 잡으로 일정/시간 이벤트 폴링 → 추론 → 로컬/푸시 알림. "원시 데이터 로컬, 요약만 모델로"(MCP Personal Assistant) 패턴이 로컬 서빙과 정확히 부합.
- **메모리가 아직 전무한 지금이 안전장치를 "도입 시점부터" 심을 절호의 기회다.** 잘못된 기억(hallucinated)·낡은 기억(stale)·오염(MINJA, 주입성공률 98%)을 막는 쓰기 검증 게이트(SSGM)·provenance(TierMem)·TTL/Weibull 감쇠·FAMA식 평가를 SQLite 한 스키마로 커버 가능.
- **HITL(human-in-the-loop) 3분기와 최소 데이터 주입이 운영 안전선이다.** LangChain notify/question/review를 '제안함' UI로, AirGapAgent식 "현재 질의에 필요한 최소 기억만 주입"으로 원격 전송 누출면을 줄인다.

---

## 조사한 접근·사례

| 이름 | 종류 | 핵심 메커니즘 | 성숙도 | PocketLlama 관련성 |
|---|---|---|---|---|
| PersonaAgent (Amazon, ACL 2026) | paper | persona = 사용자별 system prompt + episodic/semantic 2계층 메모리; 테스트타임 textual-loss로 프롬프트만 갱신 | experimental | 높음 — '순수 채팅 → 개인화 에이전트' 청사진. 단 textual-loss는 ground-truth 필요해 단순화 요 |
| Mem0 | framework | `add`(추출→통합)/`search`(멀티신호) 메모리 레이어; 벡터+KV+그래프 하이브리드 | production-ready | 중간 — 본체는 Python 서버라 Swift 직결 불가. 패턴(추출→저장→검색→주입)만 이식 |
| Letta (MemGPT) | framework | 3계층(Core/Recall/Archival) + memory block를 tool call로 self-edit(`core_memory_replace` 등) | production-ready | 높음 — tool-calling 켜면 가장 자연스러운 경로. 활성 3B가 편집 tool call 안정성 검증 필요 |
| PROSE | technique | 글쓰기 샘플에서 자연어 선호문 추론(반복 정제+일관성 prune), ICL 대비 ~1/10 토큰 | experimental | 매우 높음 — 순수 프롬프트, 벡터DB 불필요, 현 아키텍처 변경 최소 |
| LaMP / RAG vs PEFT | paper | 프로필 항목 랭킹(BM25/Contriever/Recency)→상위 병합→추론; RAG +14.92% vs PEFT +1.07% | widely-used | 높음 — 단일사용자 cold-start에 RAG 우월. `llama.cpp` embeddings + 코사인/BM25로 구현 |
| Persona Vectors (Anthropic) | paper | 활성 차이로 성격 벡터 추출, 추론 시 가감으로 톤 steer(MMLU 등 능력 저하 부작용) | experimental | 낮음 — control vector로 서버 실험만 가능, 클라이언트 추상화 밖. 장기 옵션 |
| EasySteer | framework | vLLM 기반 steering 벡터 주입(재학습 없는 톤 제어) | emerging | 낮음 — vLLM 의존, `llama.cpp` 스택과 불일치. 개념 참고만 |
| Context Engineering (OpenAI Cookbook 등) | pattern | 구조화 JSON 상태 분리 저장 + 런타임 관련 슬라이스만 주입 + 압축 요약 | production-ready | 매우 높음 — 운영 골격. 다른 항목을 담는 공통 컨테이너 |
| Survey: Personalized & Pluralistic Alignment | paper | 명시 선호 정렬 vs 잠재 선호 추론(latent user rep)의 지형도 | emerging | 중간 — 개인화 축 의사결정용. 프롬프트+잠재선호+RAG 권장 교차확인 |
| ContextAgent | paper | 센서 맥락 C + 페르소나 P → 1~5 proactive score; ≥3만 자동 툴 호출. 페르소나 제거 시 F1 −12.3%p | experimental | 높음 — 점수 게이팅 이식 가능. 영상 대신 일정/시간으로 대체 |
| Proactive Agent (ProactiveBench) | paper | 인간 accepted/rejected 라벨로 reward model 학습; F1 66.47% | experimental | 중간 — 풀 학습은 과투자. accepted/rejected를 few-shot으로 경량 대체 |
| ProMemAssist | paper | 2층 working memory + 효용=가치−비용; >0.75 즉시/0~0.75 유보/≤0 폐기 | experimental | 높음 — '잘못된 타이밍' 비용을 수식화하는 청사진 |
| LangChain Ambient Agents (+ Agent Inbox) | framework | 이벤트 스트림 청취 + notify/question/review HITL + interrupt 영속 | emerging | 높음 — 선제 알림 UX 표준안. '제안함' SwiftUI 화면으로 이식 |
| PROBE | paper | 선제성 3분해(anticipation/identification/targeting); SOTA도 end-to-end 40% 천장, 소형 모델 search 붕괴 | experimental | 높음 — 출시 게이트 설계 근거. 선제 트리거 범위 제한 경고 |
| MCP Personal Assistant | project | MCP 툴 분리 + 병렬 페치 + '원시 로컬, 요약만 모델로' 아침 브리핑 | experimental | 높음 — cron→맥락→선제 브리핑 파이프라인 실제 사례 |
| Apple App Intents / Proactive Suggestions | framework | AppIntent/AppEntity 정의 → OS가 시간/위치/사용패턴 학습해 Spotlight·Siri 선제 제안 | production-ready | 중간 — OS 선제 채널 탑승. iOS 26.5 실기기 확보 후 단계 |
| Memory-driven proactivity | technique | 단기 working + 장기 선호/루틴 분리; 새 이벤트를 baseline 대비 delta로 평가 | emerging | 중간 — 2층 메모리가 선제성의 전제라는 설계 방향 |
| SSGM | framework | 3게이트(Read 신선도·ACL / Write NLI 모순검사 / Reconciliation); 이중기억 | experimental | 높음 — 메모리 도입 시 쓰기 검증 청사진. NLI는 Qwen3 단발 호출로 근사 |
| Memora + FAMA | paper | '낡은 기억 폐기/갱신'을 평가; 무효 기억 재사용에 감점 | experimental | 높음 — ios-qa 회귀 루브릭으로 직접 채택 |
| MINJA | technique | 쿼리-온리 메모리 인젝션(bridging/indication/progressive shortening); ISR 98.2% ASR 76.8% | emerging | 중간 — 단일사용자라 외부 공격↓이나 '자기오염' 동일 메커니즘 |
| AirGapAgent + ConfAIde | framework | contextual integrity; 작업에 필요한 최소 데이터만 접근(air-gapping) | emerging | 높음 — 원격 추론의 컨텍스트=누출면. 최소 기억 주입 원칙 |
| TierMem | paper | lossy→verified 계층 + provenance 체인(source/verification/confidence/lineage) | experimental | 중간 — 추출 기억에 출처·confidence 부착. SQLite 컬럼으로 경량 구현 |
| TTL 밴드 + Weibull 인지감쇠 | pattern | 정보 유형별 TTL(불변=∞/컨텍스트=수시간/선호=중간) + 감쇠로 자연 망각 | emerging | 높음 — type/created_at 컬럼만으로 즉시 적용되는 최저비용 안전장치 |
| 로컬-퍼스트 SQLite 메모리 스택 | project | SQLite + 로컬 임베딩(ONNX INT8 ~20ms) 영속, 데이터가 기기 밖으로 안 나감 | emerging | 높음 — '클라우드 의존 최소화' 제약과 정확히 일치 |

> 성숙도 표기는 findings 원문을 그대로 옮긴 것이며, experimental은 단일 논문/사전 검증 단계임을 뜻한다. SSGM·Memora·FAMA·TierMem 등 2026년 arXiv id(2603/2604/2602 계열)는 매우 최신이라 재현·동료평가가 충분치 않을 수 있으므로 "참조 설계"로만 채택하고 PocketLlama 자체 회귀 테스트로 검증할 것.

### 상세 1 — PROSE: 가장 싼 개인화(프롬프트 only)

소수의 사용자 글쓰기 샘플에서 자연어 선호 기술문을 추론해 프롬프트로 주입하는 기법(파인튜닝 불필요).

- **메커니즘**: (1) 반복 정제 — LLM 초기 생성과 사용자 demonstration을 비교, 차이를 식별해 선호 기술문을 최대 S회(보통 5) 갱신. (2) 일관성 검증 — 기술문을 컴포넌트로 분해해 과거 demonstration에 대조, 임계 미만은 prune해 과적합 방지. 산출물은 자연어 한 단락(예: '옛날 라디오 방송 톤으로 작성').
- **장점**: ICL 대비 약 1/10 토큰. CIPHER 대비 +33%, ICL 결합 시 +47%, 인간평가 69.4% 승률. 벡터DB·툴 불필요 → 현 PocketLlama 아키텍처 변경 최소.
- **단점/주의**: demonstration 품질에 민감하고, 사용자가 "좋아한 응답/직접 쓴 메시지"를 모으는 수집 UX가 선행. 선호문은 1회 생성 후 영속 저장하되 주기적 재생성 트리거 필요.
- **PocketLlama 적용**: 사용자가 별표/북마크한 응답 몇 개를 demonstration으로 모아 `llama-server`로 선호문 1회 생성 → UserDefaults/파일 저장 → 매 `/v1/messages`의 system 필드에 짧게 주입.

### 상세 2 — Letta(MemGPT) self-editing memory: tool-calling 경로

컴퓨터 메모리 계층을 모사한 상태유지 에이전트. 에이전트가 스스로 메모리를 편집한다.

- **메커니즘**: 3계층 — Core Memory(컨텍스트 상주 작은 블록 = RAM, human/persona 블록), Recall Memory(검색 가능한 대화 이력 = 디스크), Archival Memory(도구 질의 장기저장 = 콜드). 핵심 primitive는 라벨링된 영속 문자열 'memory block'이며 system 프롬프트에 직접 삽입. 에이전트가 `core_memory_append`/`core_memory_replace`/`archival_memory_insert`/`archival_memory_search`를 tool call로 호출해 '무엇을 기억/갱신할지'를 자기 추론으로 결정.
- **장점**: '앱이 사용자를 학습'하는 효과를 외부 클라우드 없이. 단일사용자라 user_id 라우팅 불필요로 단순화.
- **단점/주의**: 활성 ~3B MoE가 메모리 편집 tool call을 **안정적으로** 낼지 불확실 → `server-gate`/실측 검증 필수. 모델이 환각한 사실을 자율 저장하면 자기오염(MINJA 메커니즘) 위험 → 쓰기 검증 게이트 동반 필요.
- **PocketLlama 적용**: `llama.cpp` tool-calling으로 `core_memory_replace`류 함수 노출, Swift가 human/persona 블록을 영속 저장 후 매 요청 system 필드에 주입.

### 상세 3 — 선제 게이팅: ContextAgent 점수 + ProMemAssist 효용

선제 알림의 최대 리스크는 '잘못된 타이밍 끼어들기'다. 두 연구를 합쳐 게이트를 설계한다.

- **ContextAgent**: 센서 맥락 C + 페르소나 맥락 P를 입력받아 thought trace + **1~5 proactive score** + tool chain 출력 → score ≥ 3일 때만 자동 툴 호출. 페르소나 제거 시 F1 −12.3%p(개인화가 게이팅 정확도에 직결). 7B 파인튜닝본이 70B 베이스라인과 동급 → Qwen3.6-35B-A3B로 충분.
- **ProMemAssist**: 효용 = (0.6·Importance + 0.4·Relevance) − (교체비용 + 간섭비용). **>0.75 즉시 전달 / 0~0.75 유보 후 재평가 / ≤0 폐기.** 사용자 연구(N=12)에서 긍정 반응 24.6% vs 베이스라인 9.34%, 좌절감 유의 감소.
- **PROBE 경고**: SOTA(GPT-5, Claude Opus 4.1)도 선제성 end-to-end 40% 천장, 소형 모델은 search F1 0.04로 붕괴. → 활성 3B급 PocketLlama는 **광범위 선제 판단 금지**, 좁은 고신뢰 케이스로 제한.
- **PocketLlama 적용**: 선제 후보마다 `llama-server`에 "지금 끼어들 가치가 있나"를 점수화시키고 임계 초과만 푸시. 센서 없이 시간/일정 충돌/최근 대화 맥락으로 recency·relevance·importance를 근사.

### 상세 4 — 메모리 안전 3종 세트: SSGM Write Gate + TierMem provenance + TTL/Weibull

메모리를 도입할 때 hallucinated/stale/poisoned를 동시에 막는 최소 구성.

- **SSGM Write Validation Gate**: 신규 업데이트 ΔM이 보호된 core fact와 논리적 모순인지 NLI로 검사해 모순이면 쓰기 거부(환각 캐스케이드 차단). Read Gate는 Weibull 신선도 필터 w(Δτ)=exp(−(Δτ/η)^κ)로 θ_fresh 미만 프루닝. PocketLlama에선 NLI 모순검사를 Qwen3 단발 호출('A와 B가 모순인가')로 근사.
- **TierMem provenance**: 각 기억에 source(어느 대화/턴)·verification status·confidence·lineage를 부착하고 검증된 것만 lossy→verified 승급. SQLite 컬럼(`source_turn_id`, `confidence`, `verified`)으로 경량 구현.
- **TTL 밴드 + Weibull 감쇠**: 불변 사실(이름)=무한 TTL, 일시 컨텍스트(현재 활동)=수 시간, 선호=중간. `type`/`created_at` 컬럼만 추가하면 즉시 적용. 단 '고-relevance인데 stale'은 감쇠로 안 잡혀 별도 무효화·재조정 필요(FAMA가 이를 평가).
- **MINJA 함의**: 단일사용자라 외부 공격자는 적으나, 모델이 환각한 추론을 자동 적재하는 '자기오염'이 동일 메커니즘 → 자동 사실추출 시 confidence 임계 미만은 저장 보류 또는 사용자 확인.

---

## PocketLlama 환경 적용성

### 쉬운 것 (현 스택에서 바로/저비용)

- **컨텍스트 엔지니어링 골격**: UserDefaults를 파일/SQLite로 격상하고 `UserProfile(JSON: 이름·선호·반복 사실)`을 두어 매 `/v1/messages` 직전 관련 슬라이스만 system 필드에 주입. 현 아키텍처 변경 최소, 클라우드 0.
- **PROSE식 선호문 주입**: 좋아요/북마크한 메시지 몇 개로 선호문 1회 생성 → 짧게 주입. 순수 프롬프트라 네트워킹 계층 변경 불필요.
- **TTL/type 컬럼 + Weibull 감쇠**: SQLite 스키마에 `type`/`created_at`만 추가하면 stale 자동 폐기 + 전송량·프라이버시면 동시 절감.
- **AirGapAgent식 최소 주입**: Swift 컨텍스트 빌더에서 '전체 메모리 덤프 금지, 현재 질의에 필요한 기억만' 강제. 원격 추론(Mac)이라 컨텍스트가 곧 누출면이므로 직접 효과.
- **LaMP식 경량 RAG**: 대화 이력/노트를 프로필 항목으로 두고 `llama.cpp` embeddings + 코사인/BM25 top-k 검색. 단일사용자 cold-start라 RAG가 PEFT보다 우월(논문 근거).

### 어려운 것 (가능하나 검증·추가 작업 필요)

- **Letta식 self-editing tool call**: `llama.cpp` tool-calling은 지원하나, 활성 ~3B MoE가 `core_memory_replace`류 호출을 안정적으로 내는지 `server-gate` 실측 필수.
- **선제 알림 백엔드**: iOS 백그라운드 실행이 엄격 제한 → 상시 센싱 불가. Mac `llama-server` 옆 cron 잡으로 일정/시간 이벤트 폴링 → 추론 → 로컬/푸시 알림하는 **백엔드 분리** 아키텍처가 정석. 캘린더는 EventKit으로 iOS 권한 받아 서버 동기화.
- **SSGM Write Gate (NLI 모순검사)**: Qwen3 단발 호출로 근사 가능하나, 모순 판정 정확도가 작은 모델에서 흔들릴 수 있어 보수적 임계·사용자 확인 병행 필요.
- **FAMA/Memora 회귀 평가**: ios-qa 하네스에 '낡은 선호로 추천하면 감점' 케이스를 이식해야 stale 재사용을 정량 추적 가능(소규모 수동 셋 구성 필요).

### 막히는 지점 (단기 부적합)

- **활성치 steering (Persona Vectors / EasySteer)**: control vector는 `llama.cpp`에 있으나 추론 루프 개입이 필요해 Anthropic 호환 `/v1/messages` 클라이언트 추상화 밖. 작은 MoE에서 MMLU 등 능력 저하 위험 + 운영 복잡성. EasySteer는 vLLM 의존이라 스택 불일치. → 장기 실험 옵션으로만.
- **reward model 풀 학습 (Proactive Agent)**: 1인 사용자 데이터로 풀 학습은 과투자. accepted/rejected 로그를 few-shot 예시로 프롬프트 주입하는 경량 변형으로 대체.
- **멀티모달 상시 센싱 (ContextAgent/ProMemAssist 원형)**: 웨어러블 영상/음향 전제라 그대로는 불가. 일정/시간 같은 저비용 맥락으로 게이팅 구조만 차용.
- **App Intents 기반 OS 선제 채널**: iOS 26.5 실기기 미확보(이 맥 미설치) → 향후 단계로 미룸.
- **Mem0/Letta 본체 직접 탑재**: Python 서버라 Swift 앱 직결 불가. Mac 서버 사이드카로 두거나 패턴만 Swift/서버에 이식.

---

## 권장 채택안

우선순위는 "비용↓ · 효과↑ · 현 아키텍처 변경↓" 순. 난이도는 1인 개발·현 스택 기준.

| 우선순위 | 채택안 | 난이도 | 선행조건 |
|---|---|---|---|
| 1 | **컨텍스트 엔지니어링 골격** — UserDefaults→SQLite, `UserProfile(JSON)` 구조화, 매 요청 관련 슬라이스만 system 주입 | 하 | SQLite/파일 영속 스키마 설계; 컨텍스트 빌더에 '최소 주입' 규칙(AirGapAgent) |
| 2 | **SQLite 메모리 스키마 + 안전 컬럼 선설계** — `type`/`created_at`/`source_turn_id`/`confidence`/`verified` (TierMem+TTL+FAMA 한 스키마) | 하 | 1번 위에 컬럼 추가; Weibull 신선도 필터 함수 |
| 3 | **PROSE식 자연어 선호문** — 북마크 demonstration → 선호문 1회 생성 → system 짧게 주입 | 하 | 응답 좋아요/북마크 수집 UX; 선호문 재생성 트리거 |
| 4 | **LaMP식 경량 RAG** — 이력/노트를 프로필 항목으로, `llama.cpp` embeddings + 코사인/BM25 top-k 주입 | 중 | embeddings 엔드포인트 확인; 로컬 벡터 저장(sqlite-vec) |
| 5 | **쓰기 검증 게이트 + update-on-write** — 유사 기억 검색 후 add/update/delete 판정(mem0) + 모순 시 거부(SSGM); 자동추출은 confidence 임계 미만 보류 | 중 | 4번의 검색 + Qwen3 단발 모순판정 호출; 사용자 확인 경로 |
| 6 | **선제 게이팅 게이트 (좁은 고신뢰 케이스)** — proactive score(≥3) + 효용(>0.75) 점수화, 일정 충돌·명시 리마인더로 제한 | 중 | EventKit 캘린더 권한; Mac cron 잡; 점수화 프롬프트 |
| 7 | **HITL 3분기 '제안함' UI** — notify/question/review를 SwiftUI 카드로, 발신·외부 행동은 review 강제 | 중 | 6번 산출을 받을 인박스 화면; 로컬 알림 우선(APNs 페이로드에 민감정보 금지) |
| 8 | **Letta식 self-editing 메모리 (tool-calling)** — `core_memory_replace`류 노출, 모델이 블록 갱신 | 상 | `llama.cpp` tool-calling을 활성 3B에서 `server-gate` 실측; 5번 쓰기 게이트 선결 |
| 9 | **FAMA/Memora 회귀 셋** — '낡은 선호 추천 감점' + LongMemEval knowledge-update/temporal 소규모 이식 | 중 | ios-qa 하네스 확장; 평가 케이스 수동 작성 |
| — | 활성치 steering / reward model 풀 학습 / 멀티모달 센싱 / App Intents | 보류 | 능력 저하·과투자·플랫폼(iOS 26.5) 미충족 — 장기 옵션 |

> **권고 순서 요약**: 먼저 1·2·3(전부 난이도 하)으로 '구조화 상태 + 안전 스키마 + 톤 개인화'를 깔고, 4·5로 RAG와 안전한 쓰기 경로를 더한 뒤, 6·7로 선제 UX를 좁게 켠다. 8(self-editing)은 모델의 tool-calling 안정성이 `server-gate`로 입증된 후에만. 모든 저장은 로컬(앱 + Mac 서버)에 머물러 프라이버시 제약과 충돌하지 않는다.

---

## 참고자료

**개인화·persona 엔지니어링**
- [PersonaAgent: Bridging Memory and Action for Personalized LLM Agents (arXiv 2506.06254)](https://arxiv.org/abs/2506.06254)
- [PersonaAgent — Amazon Science publication](https://www.amazon.science/publications/personaagent-when-large-language-model-agents-meet-personalization-at-test-time)
- [PersonaAgent — OpenReview](https://openreview.net/forum?id=Id97yjKWMG)
- [mem0ai/mem0 — GitHub](https://github.com/mem0ai/mem0)
- [Mem0: Building Production-Ready AI Agents with Scalable Long-Term Memory (arXiv 2504.19413)](https://arxiv.org/abs/2504.19413)
- [Mem0 — Context Engineering guide](https://mem0.ai/blog/context-engineering-ai-agents-guide)
- [MemGPT Agents (Legacy) — Letta Docs](https://docs.letta.com/guides/legacy/memgpt_agents_legacy)
- [Mem0 vs Letta (MemGPT): AI Agent Memory Compared](https://vectorize.io/articles/mem0-vs-letta)
- [Stateful AI Agents: Deep Dive into Letta (MemGPT) Memory Models](https://medium.com/@piyush.jhamb4u/stateful-ai-agents-a-deep-dive-into-letta-memgpt-memory-models-a2ffc01a7ea1)
- [Aligning LLMs by Predicting Preferences from User Writing Samples (PROSE, arXiv 2505.23815)](https://arxiv.org/html/2505.23815v1)
- [LaMP-Benchmark/LaMP — GitHub](https://github.com/LaMP-Benchmark/LaMP)
- [LaMP: When Large Language Models Meet Personalization (arXiv 2304.11406)](https://arxiv.org/abs/2304.11406)
- [Comparing RAG and PEFT for Privacy-Preserving Personalization (arXiv 2409.09510)](https://arxiv.org/html/2409.09510v2)
- [Persona vectors: Monitoring and controlling character traits — Anthropic](https://www.anthropic.com/research/persona-vectors)
- [Persona Vectors (arXiv 2507.21509)](https://arxiv.org/pdf/2507.21509)
- [New persona vectors from Anthropic — VentureBeat](https://venturebeat.com/ai/new-persona-vectors-from-anthropic-let-you-decode-and-direct-an-llms-personality)
- [EasySteer: A Unified Framework for High-Performance and Extensible LLM Steering (arXiv 2509.25175)](https://arxiv.org/html/2509.25175v1)
- [Context Engineering for Personalization — OpenAI Cookbook](https://developers.openai.com/cookbook/examples/agents_sdk/context_personalization)
- [A Survey on Personalized and Pluralistic Preference Alignment in LLMs (arXiv 2504.07070)](https://arxiv.org/pdf/2504.07070)

**선제적 능동성·맥락 인지**
- [ContextAgent: Context-Aware Proactive LLM Agents with Open-World Sensory Perceptions (arXiv HTML)](https://arxiv.org/html/2505.14668v1)
- [ContextAgent — OpenReview](https://openreview.net/forum?id=tRXt10xKc5)
- [Proactive Agent: Shifting LLM Agents from Reactive Responses to Active Assistance (arXiv)](https://arxiv.org/abs/2410.12361)
- [ProMemAssist: Timely Proactive Assistance Through Working Memory Modeling (arXiv HTML)](https://arxiv.org/html/2507.21378v1)
- [ProMemAssist — ACM UIST 2025](https://dl.acm.org/doi/10.1145/3746059.3747770)
- [Introducing Ambient Agents — LangChain blog](https://www.langchain.com/blog/introducing-ambient-agents)
- [Ambient Agents — LangChain analysis (Colin McNamara)](https://colinmcnamara.com/blog/ambient-agents-langchain-analysis)
- [Beyond Reactivity: Measuring Proactive Problem Solving in LLM Agents (PROBE, arXiv HTML)](https://arxiv.org/html/2510.19771v1)
- [MCP-Personal-Assistant — GitHub](https://github.com/paddumelanahalli/MCP-Personal-Assistant)
- [App Intents — Apple Developer Documentation](https://developer.apple.com/documentation/appintents)
- [Integrating actions with Siri and Apple Intelligence](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence)
- [From Reactive to Proactive: How Memory Gives AI a Sense of Agency (MemU)](https://medium.com/@memU_ai/from-reactive-to-proactive-how-memory-gives-ai-a-sense-of-agency-5d5bcf5d8e76)
- [The Memory Problem Changes When Agents Stop Waiting To Be Prompted (Monte Carlo)](https://www.montecarlodata.com/blog-the-memory-problem-changes-when-agents-stop-waiting-to-be-prompted/)

**평가·안전 (메모리·프라이버시·인젝션)**
- [Governing Evolving Memory in LLM Agents: SSGM Framework (arXiv HTML)](https://arxiv.org/html/2603.11768v1)
- [SSGM Framework (PDF)](https://arxiv.org/pdf/2603.11768)
- [From Recall to Forgetting: Benchmarking Long-Term Memory for Personalized Agents (Memora, arXiv HTML)](https://arxiv.org/html/2604.20006v1)
- [From Recall to Forgetting — OpenReview](https://openreview.net/forum?id=YzFNBzlQbo)
- [LongMemEval: Benchmarking Chat Assistant Long-Term Memory (arXiv PDF)](https://arxiv.org/pdf/2410.10813)
- [A Practical Memory Injection Attack against LLM Agents (MINJA, arXiv HTML)](https://arxiv.org/html/2503.03704v2)
- [Memory Injection Attacks on LLM Agents via Query-Only Interaction (PDF)](https://arxiv.org/pdf/2503.03704)
- [What Is a Memory Injection Attack (MINJA)? — Future AGI](https://futureagi.com/glossary/memory-injection-attack-minja/)
- [AirGapAgent: Protecting Privacy-Conscious Conversational Agents (PDF)](https://arxiv.org/pdf/2405.05175)
- [Privacy in Action: Realistic Privacy Mitigation and Evaluation for LLM-Powered Agents (arXiv HTML)](https://arxiv.org/html/2509.17488v1)
- [1-2-3 Check: Enhancing Contextual Privacy in LLM via Multi-Agent Reasoning (ACL)](https://aclanthology.org/2025.llmsec-1.9/)
- [Mem0 — Overall Architecture and Principles (Medium)](https://medium.com/@zeng.m.c22381/mem0-overall-architecture-and-principles-8edab6bc6dc4)
- [State of AI Agent Memory 2026 — mem0 blog](https://mem0.ai/blog/state-of-ai-agent-memory-2026)
- [From Lossy to Verified: A Provenance-Aware Tiered Memory for Agents (TierMem, PDF)](https://arxiv.org/pdf/2602.17913)
- [When Agent Memory Learns to Forget (Medium)](https://medium.com/@Nexumo_/when-agent-memory-learns-to-forget-21fb08a88513)
- [The Forgetting Problem: When Unbounded Agent Memory Degrades Performance (TianPan.co)](https://tianpan.co/blog/2026-04-12-the-forgetting-problem-when-agent-memory-becomes-a-liability)
- [PersistBench: When Should Long-Term Memories Be Forgotten by LLMs? (arXiv HTML)](https://arxiv.org/html/2602.01146v1)
- [sqliteai/sqlite-ai: On-device inference & embeddings inside SQLite (GitHub)](https://github.com/sqliteai/sqlite-ai)
- [sqliteai/sqlite-memory: Markdown-based AI agent memory, offline-first (GitHub)](https://github.com/sqliteai/sqlite-memory)
- [MemX: A Local-First Long-Term Memory System for AI Assistants (PDF)](https://arxiv.org/pdf/2603.16171)
