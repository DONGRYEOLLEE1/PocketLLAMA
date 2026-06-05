# PocketLlama iOS Lab

맥북에서 `llama.cpp`(`llama-server`)로 서빙하는 `Qwen3.6-35B-A3B` 모델에 아이폰 SwiftUI 앱(**PocketLlama**)이 Anthropic 호환 `/v1/messages`로 붙어 채팅하는 MVP 프로젝트.

- **현재 단계**: 계획 확정(코드 미착수 — Xcode 빈 템플릿).
- **SSOT 문서**: 구현 계획 `plans/swiftui-ollama-ios-mvp-plan.md`(v3) · 사전 조사 `docs/ollama-iphone-research.md`
- **서버**: 별도 repo `~/workspace/dev/llm-serving`(`serve.sh`=`llama-server`). 아이폰 접속엔 `0.0.0.0` 바인딩 필요.

---

# 하네스 (2개)

이 프로젝트는 두 하네스로 운영한다. 자연스러운 연결: **`server-gate`(계약 실측) → `ios-build`(구현+QA) → `strict-review`(엄중 리뷰)**.

| 하네스 | 목적 | 실행 모드 | 트리거(요약) |
|---|---|---|---|
| `strict-review` | 코드·계획서 엄중 리뷰(내부+agy/grok 통합) | 서브 에이전트 | "엄중/strict 리뷰", "agy·grok 리뷰" |
| `ios-build` | 계획서 Phase를 SwiftUI 코드로 구현+검증 | 에이전트 팀 | "PocketLlama 구현", "Phase N 만들어" |

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

---

## 디렉토리 구조
```
.claude/
├── agents/
│   ├── strict-reviewer.md
│   ├── swift-builder.md
│   └── ios-qa.md
└── skills/
    ├── strict-review/      SKILL.md + references/synthesis-guide.md
    ├── external-review/    SKILL.md + scripts/external-review.sh + references/cli-reference.md
    ├── ios-build/          SKILL.md
    ├── swiftui-patterns/   SKILL.md + references/swift-snippets.md
    ├── server-gate/        SKILL.md + scripts/gate.sh
    └── xcode-build-check/  SKILL.md + scripts/build-check.sh
```

## 외부 도구 호출 요약
- **agy**(Gemini): `agy -p "<프롬프트>" --add-dir <dir> --print-timeout 15m --dangerously-skip-permissions [--model M]` (effort/check 없음 → 프롬프트로 엄중도)
- **grok**: `grok -p "<프롬프트>" --cwd <dir> --permission-mode dontAsk --effort high --check [-m M]` (`--best-of-n N` 최고강도)
- **gate.sh**: `server-gate/scripts/gate.sh [--serve] [--host IP] [--api-key K]` → 게이트 8줄 스모크
- **build-check.sh**: `xcode-build-check/scripts/build-check.sh` → 시뮬레이터 SDK 컴파일

## 변경 이력
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-06-05 | 초기 구성 (strict-review 하네스) | strict-reviewer / strict-review / external-review | 코드·계획서 엄중 리뷰 + agy/grok 외부 리뷰 통합 |
| 2026-06-05 | ios-build 하네스 추가 | swift-builder, ios-qa / ios-build, swiftui-patterns, server-gate, xcode-build-check | 구현 생산성 — 계획서 Phase를 코드로(생성-검증) + 서버 E2E 게이트 자동화 |
