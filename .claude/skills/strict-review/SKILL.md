---
name: strict-review
description: 코드·계획서·문서를 엄중(strictly)하게 리뷰하는 오케스트레이터. "엄중/strict 리뷰", "계획서/코드 리뷰해줘", "깐깐하게 검토", "agy·grok·gemini로 리뷰", "외부 리뷰 받아서 통합", "이 변경 리뷰" 요청 시 반드시 이 스킬을 사용. 내부 엄중 리뷰 + agy(Gemini)·grok 외부 리뷰를 교차검증·상충판정해 단일 통합 리뷰를 만든다(strict-reviewer 에이전트, model opus). 후속도 포함: "다시 리뷰", "재리뷰", "리뷰 업데이트", "XX만 다시 검토", "다른 모델로", "리뷰 반영"(반영은 사용자 승인 후 별도).
---

# Strict Review — 엄중 리뷰 오케스트레이터

내부(Claude)·외부(agy=Gemini, grok) 세 시각으로 대상을 엄중 리뷰하고, **교차검증·상충판정**해 **단일 통합 리뷰**를 만든다. 이 repo가 수동으로 하던 "grok·gemini 리뷰 → 계획서 통합" 패턴의 자동화다.

**실행 주체:** `strict-reviewer` 에이전트(`.claude/agents/strict-reviewer.md`, general-purpose). 이 스킬이 트리거되면 메인은 `Agent(subagent_type:"strict-reviewer", model:"opus")`로 위임한다.

**기본 종착점:** **통합 리뷰 문서까지.** 대상 문서/코드 자동 수정은 하지 않는다 — 사용자가 "리뷰 반영해줘"라고 명시할 때만 별도 단계로 반영(strict review의 본질은 비판이고, 반영은 결정이라 분리한다).

**기본 엄중도:** `strengthened`(grok `--effort high --check` 자기검증). 중요 계획서·핵심 코드는 `max`로 올린다.

---

## Phase 0: 컨텍스트 확인 (초기 / 후속 / 부분 재실행)

먼저 기존 리뷰 산출물 유무로 모드를 정한다:

- **초기**: 대상에 대한 리뷰 파일(`*-review-*.md`)이 없음 → 전체 실행.
- **후속(개선)**: 리뷰 파일이 있고 사용자가 "다시/업데이트/보완" → 기존 리뷰를 읽고 **무엇이 바뀌었는지(대상 변경분)** 중심으로 재리뷰. 이전 통합 리뷰의 미해결 지적을 추적.
- **부분**: "grok만 다시", "보안 부분만" → 해당 리뷰어/포커스만 재호출하고 통합본을 갱신.

대상이 불명확하면(무엇을 리뷰할지) 사용자에게 1줄로 확인한다. 명백하면(직전 대화의 계획서·현재 diff 등) 묻지 말고 진행.

---

## Phase 1: 대상 식별

| 대상 유형 | 식별 방법 |
|---|---|
| 계획서/문서 | 경로 명시 또는 직전 대화 맥락(예: `plans/swiftui-ollama-ios-mvp-plan.md`) |
| 코드(작업 중) | `git diff` / `git status`로 변경분, 또는 지정 디렉토리(`app/PocketLlama`) |
| 특정 모듈 | 사용자가 지정한 파일/디렉토리 |

리뷰어가 외부 참조를 봐야 하면(예: 서버 스크립트 `~/workspace/dev/llm-serving`) `--context-dir`로 넘긴다.

---

## Phase 2: 3-시각 리뷰 (병렬)

`strict-reviewer` 에이전트가 다음을 수행한다:

1. **내부 엄중 리뷰** — 에이전트가 직접 대상을 읽고 Blocker/Major/Minor로 정리(근거·위치 필수).
2. **외부 리뷰(병렬)** — `external-review` 스킬의 스크립트로 두 CLI를 동시 호출:
   ```bash
   .claude/skills/external-review/scripts/external-review.sh grok <target> \
     --rigor strengthened --focus "<영역>" --out plans/<name>-review-grok.md &
   .claude/skills/external-review/scripts/external-review.sh agy <target> \
     --rigor strengthened --focus "<영역>" --out plans/<name>-review-gemini.md &
   wait
   ```
   - 출력 파일명은 기존 패턴(`<문서이름>-review-grok.md`, `...-review-gemini.md`) 유지.
   - `--focus`는 대상 유형에 맞게(계획서: "API 계약·보안·ATS·실행순서" / iOS 코드: "동시성·에러처리·메모리·네트워킹").

> 외부 리뷰는 시간이 걸린다(특히 `--check`/`best-of-n`). 두 호출을 `&` + `wait`로 병렬화한다.

---

## Phase 3: 종합 · 상충판정 · 통합 리뷰

세 리뷰를 모아 단일 통합 리뷰를 만든다. 판정 기준은 `references/synthesis-guide.md` 참조. 요지:

- **합의(2개 이상 동일 지적)** → 신뢰도 높음. 우선 반영 후보.
- **상충(서로 다른 판정)** → **삭제하지 말고 출처 병기** + 에이전트가 파일을 직접 열어 **사실로 판정**(어느 쪽이 맞는지 근거 제시). 예: 한쪽이 "X 위험"이라는데 코드/문서를 보니 과장이면 "과장 — 근거"로 표기.
- **단독 지적** → 근거가 타당하면 채택, 약하면 "미검증/불확실"로 표기.
- **환각 필터** → 외부 리뷰가 존재하지 않는 파일·API를 단정하면 **검증 후 기각**하고 그 사실을 적는다.

산출물: 통합 리뷰 1개. 기본 저장 경로 `plans/<대상이름>-review-strict.md` (또는 사용자 지정). 구조:
1. 총평 + Definition of Ready 판단(있으면)
2. **Blocker**(합의/판정 결과)
3. **Major**
4. **Minor/정합성**
5. **상충·기각 항목**(출처 병기 + 판정 근거)
6. 외부 리뷰 원본 링크(`*-review-grok.md`, `*-review-gemini.md`)

종료 시 사용자에게 보고하고, **"통합 리뷰를 대상 문서/코드에 반영할까요?"**를 1줄로 제안한다(자동 반영 금지).

---

## 데이터 흐름
- **파일 기반(산출물)**: 외부 리뷰 → `plans/*-review-{grok,gemini}.md`. 통합 → `plans/*-review-strict.md`. 보존(감사 추적).
- **중간물**: 필요 시 `_workspace/`에 부분 결과. 최종만 `plans/`.
- 에이전트는 통합 리뷰 본문을 메인에 반환(요약 보고용).

## 에러 핸들링
- **외부 리뷰어 1개 실패(미인증/타임아웃)**: 1회 재시도 → 재실패 시 **그 리뷰어 없이 진행**, 통합 리뷰에 "Gemini 리뷰 누락(사유)" 명시. 다른 리뷰어+내부 리뷰로 통합.
- **둘 다 실패**: 내부 엄중 리뷰만으로 통합 리뷰를 내고, 외부 리뷰 미수행을 명시 + 로그인 안내(`! agy` / `! grok login`).
- **상충**: 삭제 금지, 출처 병기 + 사실 판정.
- **대상 과대**: `--focus`/파일 분할로 범위를 좁혀 재호출.

## 테스트 시나리오
- **정상**: `plans/swiftui-ollama-ios-mvp-plan.md` 엄중 리뷰 → grok·gemini 외부 리뷰 파일 2개 생성 + `*-review-strict.md` 통합본 생성, 상충 항목은 판정과 함께 기재.
- **에러**: grok 미인증 상태 → 1회 재시도 후 누락 처리, gemini+내부 리뷰로 통합본 생성하고 "grok 누락(미인증)" 명시 + 로그인 안내.

## 더 보기
- 상충판정·통합 기준 상세: `references/synthesis-guide.md`
- 외부 CLI 호출/플래그: `../external-review/SKILL.md`, `../external-review/references/cli-reference.md`
