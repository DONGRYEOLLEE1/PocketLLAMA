---
name: ios-design
description: PocketLlama iOS 앱의 비주얼/UX 디자인을 에이전트 팀으로 수행하는 오케스트레이터. "앱 디자인/UI 디자인 해줘", "예쁘게/세련되게/개성 있게", "디자인 시스템 만들어", "색·테마·말풍선·타이포·간격 다듬어", "HIG·접근성 점검", "다크모드 손봐", "이 화면 디자인 개선" 요청 시 반드시 이 스킬을 사용. ui-designer(생성)+design-critic(검증) 팀이 ios-design-system·apple-hig를 써서 디자인을 만들고 HIG·접근성·토큰 일관성을 검증한다(생성-검증 루프, model opus). 후속도 포함: "다음 화면", "이어서 디자인", "디자인 다시", "XX 화면만 다시", "비평 반영", "색만 바꿔서 재검증". (단순 한 줄 스타일 수정은 팀 없이 직접 처리)
---

# ios-design — 디자인 생성-검증 오케스트레이터

PocketLlama의 **비주얼/UX 디자인**을 에이전트 팀으로 수행한다. `ui-designer`(생성)가 디자인 시스템·스타일을 만들고, `design-critic`(검증)이 HIG·접근성·토큰 일관성을 즉시 교차검증하는 **생성-검증 루프**다. 방향성은 **차별화·개성 우선**(외형은 자유, 접근성·시스템 동작은 불가침).

기능 구현(네트워킹·스트리밍·상태머신)은 이 하네스의 일이 아니다 — 그건 `ios-build`다. 여기는 *외형*이다. 경계: ui-designer는 색·폰트·간격·모디파이어·시각 레이아웃만 만진다.

## Phase 0: 컨텍스트 확인 (실행 모드 판별)

먼저 기존 산출물·코드 상태로 실행 모드를 정한다:
- `app/PocketLlama/DesignSystem/` **미존재** → **초기 실행**(디자인 시스템부터 구축).
- `DesignSystem/` 존재 + 사용자가 **부분 수정** 요청("말풍선만", "색만") → **부분 재실행**(해당 토큰/화면만 ui-designer 재호출 → critic 재검증).
- `DesignSystem/` 존재 + **새 화면/방향** 요청 → **확장 실행**(기존 토큰 재사용하며 새 화면 디자인).
- 직전 `_workspace/`에 critic FAIL이 남아 있으면 → 그 지적부터 처리.

대상 화면이 모호하면 사용자에게 우선순위를 묻는다(채팅 vs 설정 vs 디자인 시스템 토대).

## Phase 1: 대상·범위 파악

1. 대상 화면/컴포넌트와 디자인 의도를 확정한다(예: "채팅 말풍선 + 빈 상태를 브랜드감 있게").
2. 현재 코드를 읽어 흩어진 하드코딩 스타일을 파악한다(`Color...opacity`, `cornerRadius:`, `.font(.system(size:))`).
3. 초기 실행이면 **디자인 시스템 토대(토큰)부터** — 화면 스타일링은 토큰 위에서.

## Phase 2: 팀 구성 및 작업 할당

**에이전트 팀 모드** (기본). `TeamCreate`로 팀, `TaskCreate`로 화면/컴포넌트 단위 작업.

```
TeamCreate(team: "design", members: [ui-designer, design-critic])   # 둘 다 model: opus
TaskCreate(작업들 — 화면/컴포넌트 단위, 의존관계 표시)
  예) 1. DesignSystem 토대(토큰·테마)   [ui-designer→design-critic]
      2. 채팅 말풍선·빈 상태 스타일      [의존: 1]
      3. 입력바·상태/에러 배너 스타일    [의존: 1]
      4. 설정·모델바 스타일             [의존: 1]
```

팀원은 `SendMessage`로 직접 조율한다. 리더(이 오케스트레이터)는 진행을 모니터링하고 결과를 종합한다.

## Phase 3: 생성-검증 루프 (작업 단위마다)

```
ui-designer:  토큰/스타일 구현 → "검증 요청"(파일·토큰·적용 화면) → design-critic
design-critic: 토큰 일관성 + 접근성(contrast.py) + HIG 핵심 + 다크모드 + 컴파일 → PASS/FAIL
  FAIL → ui-designer에게 파일·줄 단위 수정 지시 → 그 부분만 수정 → 재검증
  PASS → 리더에게 완료 보고 → 다음 작업
같은 항목 2회 FAIL → 리더에게 에스컬레이션(토큰 설계 재고)
```

생성 측 1차 참조 = `ios-design-system`. 검증 측 1차 참조 = `apple-hig`(+ `contrast.py`) + `xcode-build-check`.

## Phase 4: 종합

- 적용된 화면·추가된 토큰·해소된 FAIL을 한 화면으로 요약한다.
- 시뮬레이터 설치 후 실기기 시각 검증이 필요한 항목을 별도로 모은다.
- 사용자에게 피드백을 청한다("색/톤/모션에서 바꾸고 싶은 곳?") — 진화 입력.

## 데이터 전달

| 전략 | 용도 |
|---|---|
| **태스크 기반** (`TaskCreate`/`Update`) | 화면 단위 진행·의존·재검증 상태 |
| **메시지 기반** (`SendMessage`) | designer↔critic 실시간 검증 요청·FAIL 피드백 |
| **파일 기반** | 산출물 = `app/PocketLlama/DesignSystem/` + View edit. 디자인 결정 근거·critic 리포트 = `_workspace/` (`design-proposal.md`, `design-critique-<화면>.md`). 최종 코드만 앱에, 중간 산출물은 `_workspace/` 보존(감사 추적). |

## 에러 핸들링

- **critic FAIL 반복(2회+)**: 토큰 설계 자체 문제일 수 있음 → 리더가 토큰 구조를 재검토(예: 그라데이션을 대비 통과하는 정지점으로 재정의).
- **빌드 깨짐**: 스타일 edit가 컴파일을 깸 → ui-designer가 통과까지 수정, 그 전엔 PASS 금지.
- **로직 변경 필요**: 디자인이 새 상태/데이터를 요구 → 이 하네스 범위 밖. 리더가 사용자에게 알리고 `ios-build`로 위임(직접 로직 수정 금지).
- **시뮬레이터 미설치**: 렌더 스크린샷 불가 → 코드 정적 평가로 진행, 실기기 시각 검증은 "플랫폼 설치 후"로 명시.
- 실패한 결과는 삭제하지 않고 `_workspace/`에 사유와 함께 보존한다.

## 테스트 시나리오

**정상 흐름**: "채팅 화면을 PocketLlama답게 개성 있게 디자인해줘"
→ Phase 0: DesignSystem 미존재 → 초기 실행 → ui-designer가 토큰·테마 구축 → critic 검증(대비 4.52:1 PASS, 다크모드 PASS, 컴파일 PASS) → 말풍선·빈 상태 스타일 → critic 재검증 → 종합 + 실기기 검증 항목 분리.

**에러 흐름**: 사용자 말풍선 그라데이션 위 흰 텍스트가 밝은 정지점에서 2.9:1
→ critic FAIL("BubbleBackground.swift:18, 2.9:1 < 4.5, 밝은 끝을 어둡게") → ui-designer가 그라데이션 정지점만 조정 → critic이 contrast.py 재측정 4.6:1 PASS → 진행.

## 후속 작업

- "말풍선만 다시", "색만 바꿔" → 부분 재실행(해당 토큰/화면만, 전면 재작성 금지).
- "다음 화면", "이어서" → 기존 토큰 재사용하며 확장.
- "비평 반영" → `_workspace/`의 최신 critique FAIL을 ui-designer가 처리 후 재검증.
- 단순 한 줄 스타일 수정은 팀 없이 직접 처리(오버헤드 방지).
