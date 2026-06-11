# PocketLlama 개인화 에이전트 — 컨셉 확정안 (v1.2)

> 작성 2026-06-08 · v1.1 2026-06-11(날씨 시나리오 한정·웹검색·UI 고도화 범위) · **v1.2 2026-06-11(strict-review 반영: 게이트 실측 현재형·통합 수술 명시·Keychain 확정·세션 격리)**
> 리서치 5종(`research-personalized-agent-*.md`)과 사용자 결정을 종합한 **컨셉 SSOT**. 통합 리뷰: `personalized-agent-concept-review-strict.md`(조건부 Go).

---

## 1. 정체성 (북극성)

> **"아침에 먼저 말 거는, 나를 기억하는 사적(私的) 비서"**

- 유일한 차별점은 성능이 아니라 **기억 + 프라이버시**: 나를 깊이 알면서, 데이터가 내 기기(아이폰·맥) 밖으로 나가지 않는다. 속도·지능으로는 클라우드 LLM을 이길 수 없고, 이기려 하지 않는다.
- 북극성 경험:
  ```
  08:00  🔔 "🦙 아침 브리핑이 준비됐어요"
    탭 → "좋은 아침. 오늘 비 와요 — 우산 챙기세요.
          한낮엔 27도까지 올라가니 얇게 입는 게 좋겠어요."
    → 그대로 이어서 대화
  ```

## 2. 확정 결정 (의사결정 로그)

| # | 결정 | 선택 | 사유·조건 |
|---|------|------|-----------|
| D1 | 시작 정체성 | **아침 브리핑형 능동 비서** (사적 비서·지식 비서·행동 에이전트 중) | 가장 야심차지만 "벨/내용 분리"로 도달 가능. 다른 능력은 위에 단계적으로 얹는다 |
| D2 | 실시간성 | **필수** — 브리핑 내용은 그 시각 데이터로 생성 | 날씨 등은 전날 밤 생성 시 stale. **전날 밤 사전 생성 금지** |
| D3 | 전달 방식 | **무료 단독: 벨+열면 브리핑** | 로컬 알림(무료, 시스템 스케줄러가 발화 — 앱 백그라운드 실행 불요)은 "벨"만 담당. 내용은 열어보는 순간 실시간 생성. ※저전력 모드·알림 합치로 분 단위 지연 가능 → 실기기 검증 항목 |
| D4 | 양보 사항 | 잠금화면 알림 **문구**는 고정 텍스트 | 내용까지 잠금화면에 띄우려면 푸시 채널 필요 → 업그레이드 경로로 보류 |
| D5 | 업그레이드 경로 | ntfy(무료·자가호스팅, 별도 앱) → APNs($99/년, 정식) | APNs는 무료 계정의 7일 재서명 문제도 함께 해결. v2 이후 판단 |
| D6 | **v0.1 브리핑 범위** | **날씨 시나리오 한정** | 알림→브리핑은 날씨(현재+오늘 예보) 중심으로 좁혀 확실히 완성. 일정(EventKit)은 v0.2로 이연 — 권한·시뮬레이터 검증 부담을 줄이고 한 시나리오를 끝까지 |
| D7 | 백엔드 서버 | **이번엔 안 만든다** (FastAPI+LangGraph 보류) | v0.1~Phase 2(프로필·요약)는 앱 로컬+llama-server로 충분. 웹검색 tool도 실행 주체가 앱이라 백엔드 불필요. Phase 4(장기기억)에서 ① 온디바이스(SQLite+sqlite-vec+`/v1/embeddings`) 우선 검토 → 요구 커지면 ② Mac 사이드카(FastAPI, LangGraph는 그때 선택) |
| D8 | **웹검색 tool-calling** | **네이티브 Anthropic tools 확정** (간단한 1-tool 루프) | **게이트 실측 완료(2026-06-11, `_workspace/gate-tools-measurement.md`): llama-server b9430 + 본 GGUF에서 비스트림 tool_use·tool_result 왕복·스트리밍 SSE·과호출 없음 4종 PASS.** 리서치가 경고한 Qwen3 템플릿 버그는 이 빌드에서 미발생. 프롬프트 폴백은 1차 경로가 아니라 **버전 변경/회귀 시의 최후 수단**으로만 보존. **llama.cpp 빌드·GGUF·템플릿은 버전 고정 — 변경 시 재게이트 필수** |
| D9 | **UI 고도화** | **이번 범위에 추가** | `ios-design` 하네스(ui-designer+design-critic)로 디자인 시스템 수립 + 화면 스타일링. 외형은 자유, 접근성(AA·Dynamic Type·44pt)은 불가침 |
| D10 | **API 키 보관** | **Keychain 단일 경로** (리뷰 M3 채택) | Tavily 키: 설정 화면 입력 → **iOS Keychain(SecItem) 저장·런타임 조회**. `.env`→`Secrets.swift`(gitignored)는 **개발 편의용 시드**로만 — Keychain 값이 항상 우선. 서버 apiKey도 UserDefaults 평문 → Keychain 이관(Phase 0 보안) |

## 3. 아키텍처

### v0.1 — 폰 주도 (최소 부품)

```
[ iPhone = 수집 + 실행 + 얼굴 ]
  매일 08:00 반복 로컬 알림(벨, 고정 문구) ← 무료, 시스템 스케줄러 발화
  탭/앱 열기 →
    ① 날씨 수집 (폰이 Open-Meteo 직접 호출, 실시간)
    ② + 사용자 프로필(앱 로컬: 이름·한 줄 소개)
    ③ POST /v1/messages → [ Mac llama-server ] 브리핑 생성(스트리밍)
    ④ 브리핑 카드 표시 → "이어서 대화" 시 새 채팅 세션에 시드(세션 격리)

  일반 채팅 중 (웹검색 tool-calling):
    사용자 질의 → /v1/messages(tools=[web_search])
      → 모델이 tool_use 반환 시: 앱이 Tavily API 호출(HTTPS)
      → tool_result 회신 → 최종 답변(출처 포함) 스트리밍
    ※ tool 실행 주체 = 앱(Swift). 백엔드 서버 불필요(D7).
    ※ 계약은 게이트 실측으로 확정(D8) — 네이티브 tools.
```

- **Mac에 새 부품 0** — 이미 떠 있는 llama-server만 사용(serve.sh는 이미 `--jinja` 기동). cron·브리핑 서버·캘린더 동기화 전부 불필요.
- 실시간성은 구조적으로 보장(열어보는 순간 수집·생성).

**기존 코드 통합 = 구조 변경(외과수술) — 리뷰 Blocker 2건 명시** (상세 설계는 구현 계획서 §3·§4):
- (a) `StreamChunk`/SSE 파서에 `content_block_start`·`input_json_delta`·`content_block_stop` 디코딩 추가 — 현재는 text_delta만 처리(B1)
- (b) `ChatViewModel`을 단일 request-response에서 **2라운드 hard-cap tool 루프**로 재설계(B2)
- (c) `ChatTurn`/wire 모델의 String-only content를 tool block 표현 가능 구조로 확장
- (d) 알림 탭 → SwiftUI 라우팅 배선(현재 전무): `UIApplicationDelegateAdaptor`+`UNUserNotificationCenterDelegate`
- (e) **브리핑-채팅 세션 격리**: 브리핑은 별도 진입점(BriefingViewModel)에서 weather+profile을 주입하고, "이어서 대화"는 **새 채팅 세션에 2턴 시드** — 기존 대화 히스토리(슬라이딩 윈도우)와 상호 오염 차단

### v0.2+ — Mac 두뇌 확장 (선택적)

- 폰 수집 확장: EventKit 오늘 일정(D6에서 이연).
- Mac 수집기 추가: 어제 대화 요약, git 활동, (장기) 메일·파일 등 폰이 못 보는 데이터 → 경량 엔드포인트로 폰에 제공.
- ntfy/APNs 도입 시: Mac cron이 08:00에 브리핑을 사전 생성해 잠금화면에 **내용까지** 푸시.
- 장기기억(Phase 4) 시 저장소 결정(D7): 온디바이스 우선, 필요 시 FastAPI 사이드카.

## 4. 브리핑 재료 (단계별 진화)

| 버전 | 재료 | 의존 |
|------|------|------|
| **v0.1** | **날짜·요일, 날씨(현재+오늘 예보), 사용자 프로필** | 없음(즉시 가능) |
| v0.2 | + 오늘 일정(EventKit), 어제 대화 요약, 진행 중 작업 | EventKit 권한, 요약 메모리(Phase 2) |
| v0.3 | + 장기 기억 기반 맥락("지난 출장 때 ~했죠") | 장기 메모리(Phase 4) |
| v0.4 | + 능동 제안(일정 충돌 경고, 리마인더) | 능동성(Phase 5) |

## 5. 기존 리서치 로드맵과의 정렬

`research-personalized-agent-overview.md`의 Phase 0~5는 유지하되, 전부 **"브리핑"을 목적지로 재정렬**된다:

- **Phase 0 보안·영속** — 프로필·메모리(개인 데이터)를 쌓기 전 선결. `.env` gitignore 보호(완료) + **API 키 Keychain 이관(D10)** 포함.
- **Phase 1 프로필 개인화** — 브리핑의 1차 연료("나를 안다"). v0.1 최소판(이름·한 줄 소개) 선반영.
- **Phase 2 요약 메모리** — "어제 이야기" 재료.
- **Phase 3 tool-calling** — **이번에 "간단판"을 선착수(D8, 게이트 PASS)**: 단일 tool(web_search)·최대 2라운드. 풀 신뢰성 하네스(circuit breaker·dedup 확장 등)는 tool이 늘어날 때.
- **Phase 4 장기기억·RAG** — 브리핑 개인화 심화. 저장소 결정은 D7.
- **Phase 5 능동성** — 브리핑 안에서 좁은 범위로(일정 충돌·명시 리마인더만).

> **리서치와의 의도적 분기(리뷰 ⑤-3 양립 판정)**: 리서치는 "선제 알림 = Mac cron 백엔드"를 정석으로 제시하나, 그것은 **잠금화면에 내용까지 사전 푸시**하는 경우다(백그라운드 추론 필요). v0.1은 그 경우를 D4로 의도적으로 양보했고, 발화만 하는 로컬 알림은 시스템 스케줄러가 처리하므로 백엔드가 필요 없다 — 리서치 위반이 아니라 **합법적 다운스코프**이며, 내용 푸시가 필요해지는 시점(D5)에 리서치 권고로 복귀한다.

## 6. v0.1 범위 (이번 구현)

**포함**
- **A. 날씨 브리핑 + 알림**: 알림 권한 요청 + 매일 반복 로컬 알림(기본 08:00, 설정에서 시각 변경) → 탭/앱 열기 시 날씨 수집 → llama-server 스트리밍 브리핑 카드 → 새 채팅 세션으로 이어가기(세션 격리). 서버/네트워크 실패 시 우아한 실패(마지막 브리핑 캐시 + 날씨 원자료만이라도 표시).
- **B. 웹검색 tool-calling**: 일반 채팅에서 모델 판단으로 `web_search`(Tavily) 호출 → 검색 결과 기반 답변 + 출처 표기. 검색 중 상태 UI. 키는 Keychain(D10).
- **C. UI 고도화**: `ios-design` 하네스로 디자인 시스템(토큰) + 채팅/설정/브리핑 화면 스타일 + HIG·접근성 검증.
- 최소 프로필: 설정에 이름·한 줄 소개 → 브리핑·채팅 system 프롬프트에 주입.

**확정된 구현 선택** (열린 결정 해소 — 근거는 실측·리뷰)
- 날씨 소스: **Open-Meteo**(무키·https·한국 고해상도) + **`WeatherServiceProtocol` 추상화**(추후 기상청 스위칭 가능). WeatherKit은 유료 멤버십 필요라 제외(사실 확인됨).
- 위치: **도시 프리셋**(주요 도시 고정 좌표, 기본 서울) — 지오코딩 한국어 불안정 실측, CoreLocation 권한 피로 회피.
- 키 주입: **Keychain 단일 경로(D10)**, `.env`→Secrets.swift는 시드만.
- tool 방식: **네이티브 tools(D8, 게이트 PASS)**.
- 브리핑 시점: **하루 첫 진입 시 생성 + 당일 캐시 + 수동 새로고침**(알림을 놓쳐도 브리핑 표시, 35B 재생성 비용 회피, D2와 균형).

**명시적 제외(v0.1에서 안 함)**
- EventKit 일정(D6, v0.2로) · 잠금화면에 브리핑 내용 표시(ntfy/APNs) · Mac cron/수집기 · 백엔드 서버(D7) · 벡터 RAG/장기기억 · 능동 제안 · 멀티 tool/풀 에이전트 하네스

## 7. 리스크 · 제약

| 리스크 | 내용 | 대응 |
|--------|------|------|
| 서버 버전 드리프트 | 게이트는 **b9430+본 GGUF 고정** 기준 PASS — llama.cpp/모델/템플릿 변경 시 tools 회귀 가능 | 버전 고정 기록 + **변경 시 재게이트 필수**. 회귀 시에만 프롬프트 폴백(최후 수단) |
| tool 루프 폭주 | 모델이 검색을 반복 호출 | 최대 2라운드 하드캡 + 동일 쿼리 중복 차단 |
| Tavily 키 유출 | 번들 평문 포함·레포 커밋 | **Keychain 저장(D10)** + `.env`/Generated gitignore(완료) + 외부 전송은 Tavily HTTPS뿐 |
| 통합 수술 리스크 | SSE 파서·ChatViewModel·ChatTurn 구조 변경(§3) 중 기존 채팅·스트리밍·취소 회귀 | Phase 분리 + 각 Phase 빌드 검증 + 기존 시나리오 회귀 테스트 의무화 |
| 잠금화면 문구 고정 | 내용은 탭해야 보임 (D4 양보) | 사용자 인지 완료. ntfy/APNs 업그레이드 경로 확보 |
| 무료 서명 7일 만료 | 실기기에서 주 1회 Xcode 재설치 필요 | 알림 예약은 재설치 후에도 앱 첫 실행 시 재등록 |
| Mac/서버 다운 | 브리핑 생성·채팅 실패 | 우아한 실패: 마지막 브리핑 캐시 + 재시도 + 날씨 원자료 표시(LLM 없이) |
| **로컬 네트워크 권한 거부** | iOS가 명확한 에러 코드를 안 줘 "서버 다운"으로 오인 | `notConnected` 안내문에 "설정 → 개인정보 보호 → 로컬 네트워크 확인" 병기 |
| 시뮬레이터 제약 | 정시·잠금화면 알림 동작 검증 한계 | 단축 트리거 발화 + pending 예약 검증으로 대체(보고서에 명시) + 실기기 체크리스트 |
| 프라이버시 | 프로필·대화가 system 프롬프트로 Mac에 전송, 검색어가 Tavily(외부)에 전송 | 동일 소유 기기 간 전송(LAN/Tailscale). **웹검색 사용 시에만** 검색어가 외부로 나감 — 검색 중 UI로 투명하게 표시 |

## 8. 진행 상태 · 다음 단계

1. ~~컨셉 strict-review 검증~~ ✅ 완료(조건부 Go) → 본 v1.2에 반영
2. ~~server-gate tools 계약 실측~~ ✅ PASS(`_workspace/gate-tools-measurement.md`)
3. ~~v0.1 구현~~ ✅ 완료(`v0.1-weather-briefing-websearch-plan.md` — 날씨 브리핑·웹검색 tool-calling·디자인, E2E 검증)
4. **v0.2 개인화 메모리 강화**: `v0.2-memory-enhancement-plan.md` — 3계층 메모리(core 프로필·장기 기억·세션 요약), 온디바이스 SQLite, 추출 배치·HITL, save/search_memory tool. 로드맵 Phase 1·2·4 의 구체화
5. 이후 로드맵 Phase 5(consolidation·능동성)로 확장

## 참조

- `personalized-agent-concept-review-{strict,gemini,grok}.md` — 본 문서 리뷰(조건부 Go)
- `_workspace/gate-tools-measurement.md` — tools 게이트 실측(PASS, 버전 고정 기준)
- `research-personalized-agent-overview.md` 외 리서치 4종 · `swiftui-ollama-ios-mvp-plan.md`(MVP, 완료)
