# PocketLlama iOS Lab

맥북에서 `llama.cpp`(`llama-server`)로 서빙하는 `Qwen3.6-35B-A3B` 모델에 아이폰 SwiftUI 앱(**PocketLlama**)이 Anthropic 호환 `/v1/messages`로 붙어 채팅하는 MVP 프로젝트.

- **현재 단계**: v0.2 개인화 메모리 구현 완료 — ✅ v0.1(브리핑·웹검색·디자인) + 3계층 메모리(프로필·세션 요약·SQLite 장기기억)·추출 파이프라인·save_memory tool·임베딩 서빙(Qwen3-Embedding-0.6B, 8081). 5대 시나리오 E2E 검증(`_workspace/qa-memory-e2e.md`). 알림 정시 발화·MemoryView 탭 조작은 실기기 체크리스트.
- **SSOT 문서**: 컨셉 `plans/personalized-agent-concept.md`(v1.2) · v0.2 메모리 계획 `plans/v0.2-memory-enhancement-plan.md`(v1.0, 완료) · v0.1 구현 계획 `plans/v0.1-weather-briefing-websearch-plan.md`(완료) · MVP 계획 `plans/swiftui-ollama-ios-mvp-plan.md`(v3, 완료) · 리서치 `plans/research-personalized-agent-*.md`
- **서버**: 별도 repo `~/workspace/dev/llm-serving`(`serve.sh`=`llama-server`). 아이폰 접속엔 `0.0.0.0` 바인딩 필요.

---

# 하네스 (3개)

이 프로젝트는 세 하네스로 운영한다. 자연스러운 연결: **`server-gate`(계약 실측) → `ios-build`(구현+QA) → `ios-design`(비주얼 디자인) → `strict-review`(엄중 리뷰)**. `ios-build`가 *기능*(네트워킹·상태머신)을, `ios-design`이 *외형*(색·타이포·말풍선·모션)을 맡는다 — 둘은 View를 공유하되 책임이 갈린다.

| 하네스 | 목적 | 실행 모드 | 트리거(요약) |
|---|---|---|---|
| `strict-review` | 코드·계획서 엄중 리뷰(내부+agy/grok 통합) | 서브 에이전트 | "엄중/strict 리뷰", "agy·grok 리뷰" |
| `ios-build` | 계획서 Phase를 SwiftUI 코드로 구현+검증 | 에이전트 팀 | "PocketLlama 구현", "Phase N 만들어" |
| `ios-design` | 비주얼/UX 디자인을 코드로(디자인 시스템+HIG 검증) | 에이전트 팀 | "디자인/예쁘게/개성 있게", "색·말풍선·테마", "접근성·HIG 점검" |

**공통 규칙:** 모든 에이전트 `model: "opus"`. 단순 질문/한 줄 수정은 하네스 없이 직접. 중간 산출물 `_workspace/`.

## 하네스 1: strict-review (엄중 리뷰)

**에이전트:** `strict-reviewer` — 내부 리뷰 + agy(Gemini)·grok 외부 리뷰 호출 + 교차검증·상충판정·통합.
**스킬:** `strict-review`(오케스트레이터, 통합까지) · `external-review`(agy/grok 호출 도구, 독립 재사용).

**실행 규칙:**
- "엄중/strict 리뷰", "계획서/코드 리뷰", "agy·grok·gemini로 리뷰", "외부 리뷰 통합" → `strict-review` → `strict-reviewer`.
- "grok한테 물어봐" 류 외부 1회 호출 → `external-review` 직접.
- **종착점은 통합 리뷰까지**(대상 자동수정 ✗, "반영해줘"만 별도). 기본 엄중도 `strengthened`(중요 대상 `max`).
- 산출물: `plans/<문서>-review-{grok,gemini,strict}.md`.
- agy/grok 사전 로그인 필요. 미인증 시 그 리뷰어 건너뛰고 진행(`! agy` / `! grok login`).

## 하네스 2: ios-build (구현+게이트)

**에이전트:** `swift-builder`(SwiftUI 구현) · `ios-qa`(경계면 교차검증·컴파일·완료기준 대조).
**스킬:** `ios-build`(오케스트레이터, 팀) · `swiftui-patterns`(구현 표준+골격) · `server-gate`(llama-server 게이트 스모크) · `xcode-build-check`(xcodebuild 컴파일 검증).

**실행 규칙:**
- "PocketLlama 구현", "Phase N 구현/만들어", "SwiftUI 채팅/스트리밍/설정 구현" → `ios-build` → `swift-builder`+`ios-qa` 팀(생성-검증 루프).
- 네트워크 관련 구현 전 `server-gate`로 `/v1/messages` 계약을 실측(DoR). "서버 게이트", "Phase 0 게이트" → `server-gate` 직접.
- Swift 작성 후 `xcode-build-check`로 컴파일 확인. "빌드 확인" → `xcode-build-check` 직접.
- **경계**: Xcode 빈 프로젝트 생성(.xcodeproj)은 사용자가 GUI로. 이후 Swift 구현·검증을 하네스가.
- 산출물: 코드 `app/PocketLlama/`, QA 리포트 `_workspace/qa-<phase>.md`.

## 하네스 3: ios-design (비주얼/UX 디자인)

**에이전트:** `ui-designer`(디자인 시스템·스타일 구현) · `design-critic`(HIG·접근성·토큰 일관성·대비·컴파일 검증, 읽기 전용).
**스킬:** `ios-design`(오케스트레이터, 팀) · `ios-design-system`(디자인 토큰+SwiftUI 스타일 표준, 생성 1차 참조) · `apple-hig`(HIG+접근성 체크리스트+`contrast.py` 대비 측정, 검증 1차 참조). 컴파일은 `xcode-build-check` 공용.

**실행 규칙:**
- "앱 디자인/UI 디자인", "예쁘게/세련되게/개성 있게", "색·테마·말풍선·타이포·간격 다듬어", "다크모드 손봐", "HIG·접근성 점검" → `ios-design` → `ui-designer`+`design-critic` 팀(생성-검증 루프).
- **방향성**: 차별화·개성 우선(커스텀 팔레트·그라데이션·모션) — **외형은 자유, 접근성(대비 AA·Dynamic Type·44pt)·시스템 동작은 불가침**.
- **경계(중요)**: `ui-designer`는 *외형*만(색·폰트·간격·모디파이어·시각 레이아웃). 네트워킹·`ChatState`·`ViewModel` 로직은 `ios-build`(swift-builder)의 것. 같은 View를 공유하므로 디자인=외형 / 빌드=로직으로 가른다.
- 산출물: 코드 `app/PocketLlama/DesignSystem/` + View 스타일 edit, 디자인 근거·critique `_workspace/design-*.md`.

---

## 디렉토리 구조
```
.claude/
├── agents/
│   ├── strict-reviewer.md
│   ├── swift-builder.md
│   ├── ios-qa.md
│   ├── ui-designer.md
│   └── design-critic.md
└── skills/
    ├── strict-review/      SKILL.md + references/synthesis-guide.md
    ├── external-review/    SKILL.md + scripts/external-review.sh + references/cli-reference.md
    ├── ios-build/          SKILL.md
    ├── swiftui-patterns/   SKILL.md + references/swift-snippets.md
    ├── server-gate/        SKILL.md + scripts/gate.sh
    ├── xcode-build-check/  SKILL.md + scripts/build-check.sh
    ├── ios-design/         SKILL.md
    ├── ios-design-system/  SKILL.md + references/design-snippets.md
    └── apple-hig/          SKILL.md + references/accessibility-checklist.md + scripts/contrast.py
```

## 외부 도구 호출 요약
- **agy**(Gemini): `agy -p "<프롬프트>" --add-dir <dir> --print-timeout 15m --dangerously-skip-permissions [--model M]` (effort/check 없음 → 프롬프트로 엄중도)
- **grok**: `grok -p "<프롬프트>" --cwd <dir> --permission-mode dontAsk --effort high --check [-m M]` (`--best-of-n N` 최고강도)
- **gate.sh**: `server-gate/scripts/gate.sh [--serve] [--host IP] [--api-key K]` → 게이트 8줄 스모크
- **build-check.sh**: `xcode-build-check/scripts/build-check.sh` → 시뮬레이터 SDK 컴파일
- **contrast.py**: `apple-hig/scripts/contrast.py "#fg" "#bg"` → WCAG 대비 비율 + AA/AAA 판정(디자인 대비 검증)

## 변경 이력
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-06-05 | 초기 구성 (strict-review 하네스) | strict-reviewer / strict-review / external-review | 코드·계획서 엄중 리뷰 + agy/grok 외부 리뷰 통합 |
| 2026-06-05 | ios-build 하네스 추가 | swift-builder, ios-qa / ios-build, swiftui-patterns, server-gate, xcode-build-check | 구현 생산성 — 계획서 Phase를 코드로(생성-검증) + 서버 E2E 게이트 자동화 |
| 2026-06-05 | 전체 구현 + 게이트 통과 + 마이그레이션 | app/PocketLlama(신규), server/, gate.sh·build-check 진화(macOS 폴백·bash3.2 버그) | 계획서 기반 Phase 1~8 구현 완료, 구 ollama-iphone 폐기·git init |
| 2026-06-11 | ios-design 하네스 추가 | ui-designer, design-critic / ios-design, ios-design-system, apple-hig(+contrast.py) | 비주얼/UX 디자인 생산성 — 디자인 시스템(토큰)을 코드로(생성-검증) + HIG·접근성·대비 자동 검증. 방향성 차별화·개성 우선, 외형은 자유·접근성은 불가침 |
| 2026-06-11 | v0.1 개인화 에이전트 구현(전 하네스 동원) | 컨셉 v1.2+구현계획(strict-review 조건부 Go 반영), tools 게이트 실측(네이티브 PASS·b9430 고정), P0 Keychain·W1 날씨·T1 tools 클라이언트·W2 알림/설정·W3 브리핑·T2 웹검색 루프(ios-build), DesignSystem(ios-design), E2E 드라이버+시뮬레이터 검증 | "아침에 먼저 말 거는 비서" 1단계 — 날씨 브리핑(벨/내용 분리)+간단 tool-calling. `.gitignore` `models/`→`/models/` 교정(Models/ 소스 미추적 잠복 이슈 해소) |
| 2026-06-12 | v0.2 개인화 메모리 구현 | 계획 v1.0(strict-review No-Go→조건부 Go: ScenePhase 폐기→pending 큐·FTS5→LIKE·tool 스키마 일반화 반영), M0 게이트(임베딩 마진 0.477·추출 8/8), M1 프로필·M2 세션 요약·M3 SQLite 장기기억(추출·NOOP·dedup·만료·HITL)·M4 save_memory(ios-build), serve.sh EMBED 이중 기동, 5대 시나리오 E2E(DB 직접 검사) | "나를 기억하는 비서" 2단계 — 3계층 메모리. 임베딩=Qwen3-Embedding-0.6B Q8(8081, --pooling last 필수) |
