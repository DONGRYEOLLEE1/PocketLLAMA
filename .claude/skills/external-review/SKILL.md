---
name: external-review
description: agy(Gemini)·grok 외부 CLI를 호출해 파일(코드·계획서·문서)을 엄중(strict) 리뷰받는 도구. "grok한테 물어봐", "gemini/agy로 리뷰", "외부 리뷰 받아", "외부 시각으로 비판/교차검증", "제3자 모델로 검토" 등 외부 LLM CLI 호출이 필요할 때 반드시 이 스킬을 사용. strict-review 오케스트레이터의 하위 도구로도 호출된다. 후속 표현도 포함: "다시 리뷰", "grok만 재호출", "다른 모델로 재검토", "리뷰 업데이트".
---

# External Review — agy/grok 엄중 리뷰 도구

맥에 설치된 외부 agentic CLI(`agy`=Gemini, `grok`)를 헤드리스로 호출해, 파일을 **읽기 전용**으로 엄중 리뷰받는다. 사람이 직접 CLI 플래그를 외우지 않아도 되도록 호출·프롬프트·저장을 표준화한다.

## 언제 쓰나
- 코드/계획서/문서를 **제3자 모델 시각**으로 비판받고 싶을 때
- `strict-review` 오케스트레이터가 외부 리뷰 단계를 실행할 때
- 특정 리뷰어/모델만 재호출(후속)할 때

## 핵심 규칙: 스크립트로 호출한다

`agy`/`grok`을 직접 타이핑하지 말고 **반드시 번들 스크립트**를 쓴다. 권한 플래그, 엄중 프롬프트 템플릿(심각도 분류·근거 요구·읽기 전용), 결과 헤더·저장이 한 곳에 고정되어 있어 매번 재현 가능하기 때문이다.

```bash
.claude/skills/external-review/scripts/external-review.sh <agy|grok> <target> [옵션]
```

옵션: `--out <file>` `--model <id>` `--rigor <standard|strengthened|max>` `--focus "<text>"` `--context-dir <dir>` `--cwd <dir>`

### 예시
```bash
# grok 으로 계획서 엄중 리뷰 → 파일 저장
.claude/skills/external-review/scripts/external-review.sh grok plans/swiftui-ollama-ios-mvp-plan.md \
  --rigor strengthened --focus "API 계약·SSE 파싱·보안·ATS" \
  --out plans/swiftui-ollama-ios-mvp-plan-review-grok.md

# agy(Gemini) 로 코드 디렉토리 리뷰(외부 참조 디렉토리 추가)
.claude/skills/external-review/scripts/external-review.sh agy app/PocketLlama \
  --rigor strengthened --context-dir ../dev/llm-serving \
  --out plans/pocketllama-review-gemini.md
```

## 엄중도(rigor) 매핑

| rigor | grok | agy(Gemini) | 용도 |
|---|---|---|---|
| `standard` | `--effort medium` | 기본 + 엄중 프롬프트 | 빠른 1패스 |
| `strengthened` (기본) | `--effort high --check`(자기검증 루프) | 엄중 프롬프트 + 자기검증 지시 | **일반 엄중 리뷰** |
| `max` | `--effort xhigh --best-of-n 3` | 다관점 + 자기검증 지시 | 중요 계획서·핵심 코드 |

> `agy`에는 effort/check/best-of-n 플래그가 없으므로, 엄중도는 **프롬프트 안의 자기검증 지시 강도**로 반영한다. `grok`은 네이티브 플래그로 강제한다.

## 출력 저장 컨벤션 (기존 패턴 유지)
- 외부 리뷰 결과는 `plans/<문서이름>-review-grok.md`, `...-review-gemini.md` 형태로 저장(이미 이 repo가 쓰던 패턴).
- `--out` 지정 시 스크립트가 헤더(리뷰어·대상·rigor·모델·일시)를 붙여 저장하고, 동시에 stdout으로도 출력한다.
- 미지정 시 stdout만 → 호출자(에이전트)가 받아서 처리.

## 읽기 전용 원칙 (why)
리뷰어가 파일을 고치기 시작하면 "검토"가 "수정"으로 번져 추적이 어려워진다. 그래서 프롬프트가 **수정/생성/삭제를 금지**하고, 명령 실행을 사실 확인용 읽기로 제한한다. 권한 자동승인 플래그(`--dangerously-skip-permissions`/`--permission-mode dontAsk`)는 "팝업 없이 진행"을 위한 것이지 쓰기 허가가 아니다 — 읽기 전용은 프롬프트가 보장한다.

## 에러 핸들링
- **미인증(401/`not logged in`)**: 해당 CLI 로그인 필요. 사용자에게 `! agy`(또는 `agy` 로그인 흐름) / `! grok login`을 안내하고, 그 리뷰어는 건너뛴 채 진행(스크립트는 비0 종료). 다른 리뷰어 결과는 살린다.
- **미설치(종료코드 3)**: PATH 확인. `which agy grok`.
- **타임아웃**: 대상이 크면 분할하거나 `--focus`로 범위를 좁힌다. `agy`는 내부 `--print-timeout 15m` 적용.
- 한 리뷰어가 실패해도 **다른 리뷰어와 내부 리뷰는 계속**한다(누락은 통합 리뷰에 명시).

## 더 보기
- CLI 전체 플래그·세션·모델 옵션: `references/cli-reference.md` (직접 플래그를 더 손봐야 할 때만 로드)
