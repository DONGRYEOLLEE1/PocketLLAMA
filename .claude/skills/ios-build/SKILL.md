---
name: ios-build
description: PocketLlama iOS 앱을 계획서 Phase에 따라 구현하는 오케스트레이터(에이전트 팀). "PocketLlama 구현", "Phase N 구현/만들어", "SwiftUI 채팅/스트리밍/설정 구현", "iOS 앱 개발 진행", "연결 테스트/모델 화면 만들어" 요청 시 반드시 이 스킬을 사용. swift-builder(구현)+ios-qa(검증) 팀이 swiftui-patterns·server-gate·xcode-build-check를 써서 코드를 만들고 경계면·빌드를 검증한다. 후속: "다음 Phase", "이어서 구현", "Phase N만 다시", "QA 다시", "빌드 고쳐". (단순 한 줄 수정은 직접 처리)
---

# iOS Build — PocketLlama 구현 오케스트레이터

계획서(`plans/swiftui-ollama-ios-mvp-plan.md`)의 Phase를 **생성-검증 팀**으로 구현한다. `swift-builder`가 코드를 만들고 `ios-qa`가 경계면·컴파일을 검증하는 루프를 돌려, "짰다"가 아니라 "빌드되고 계약이 맞는다"까지 끌고 간다.

**실행 모드:** 에이전트 팀(`swift-builder`, `ios-qa`). 두 에이전트가 `SendMessage`로 구현↔검증 피드백을 주고받고, 리더(메인)는 `TaskCreate`로 Phase를 할당·추적한다. 모든 에이전트 `model: "opus"`.

**경계:** Xcode **빈 프로젝트 생성(.xcodeproj)**은 GUI라 사용자가 한다(계획서 Phase 1, 신규 `PocketLlama`). 이 하네스는 그 이후 **Swift 파일 구현·검증**을 담당한다.

---

## Phase 0: 컨텍스트 확인
- **초기**: `app/PocketLlama/`에 코드 없음 → 사용자가 Xcode로 빈 프로젝트를 만들었는지 확인(없으면 안내). 있으면 Phase 2(권한)부터.
- **후속/이어서**: 기존 구현이 있음 → 다음 미완 Phase를 이어서, 또는 지정 Phase만.
- **부분**: "Phase 6만 다시", "QA만" → 해당 작업만 재실행.
대상 Phase가 불명확하면 1줄로 확인(계획서의 어느 Phase인지).

## Phase 1: 선행 게이트 (네트워크 관련일 때)
연결/채팅/스트리밍(계획서 Phase 4·6·7)을 구현하려면 **서버 계약이 실측돼야** 한다. `server-gate` 미통과 상태면 먼저 권고:
- "구현 전에 `server-gate`로 `/v1/messages` 게이트를 통과시키는 걸 권장합니다(계약·`/v1/models` shape 확정)."
- 게이트 산출물(`/v1/models` 샘플, 인증 헤더 형식)을 `ios-qa`의 경계면 비교 기준으로 넘긴다.

## Phase 2: 팀 구성 & 작업 할당
1. `TeamCreate`로 `swift-builder` + `ios-qa` 팀 구성(2명, 소규모).
2. `TaskCreate`로 대상 Phase를 작업으로 등록(계획서 완료기준을 Task 설명에 복사).
3. 한 번에 한 Phase/모듈(incremental). 큰 Phase는 모듈로 분할(예: Phase 6 = 모델 → 클라이언트 send → ChatView).

## Phase 3: 구현 ↔ 검증 루프
```
swift-builder: swiftui-patterns 따라 모듈 구현 → app/PocketLlama/ 에 파일
      │ SendMessage("검증 요청 + 만든 파일·경계면")
      ▼
ios-qa: 경계면 교차 비교(API↔Decodable, SSE) + xcode-build-check 컴파일 + 완료기준 대조
      │ FAIL → SendMessage("어느 경계면이 어떻게 불일치, 수정 지시") → builder 수정
      │ PASS → 리더에 완료 보고
      ▼
다음 모듈/Phase
```
- `ios-qa`는 코드를 직접 고치지 않는다(검증만). 수정은 `swift-builder`. 책임 분리.
- 같은 항목 2회+ FAIL → 리더 에스컬레이션(설계 재검토).

## Phase 4: 완료 & 연결
- 대상 Phase 완료기준 충족 시 종료. 변경 요약 + 빌드 결과 보고.
- 제안: "이 변경을 `strict-review`로 엄중 리뷰할까요?"(구현→리뷰 연결).

---

## 데이터 흐름
- **파일 기반(산출물)**: 실제 코드 `app/PocketLlama/`. QA 리포트는 `_workspace/qa-<phase>.md`(보존).
- **태스크 기반(조율)**: `TaskCreate`/`TaskUpdate`로 Phase 진행·의존 추적.
- **메시지 기반(실시간)**: builder↔qa 구현/검증 피드백.

## 에러 핸들링
- 빌드 실패: builder가 에러 라인 기준 수정 후 재빌드. 통과 전 완료 보고 금지.
- 서버 미기동으로 런타임 경계면 확인 불가: 계획서 §7 계약 기준 정적 비교 + "런타임 검증은 게이트 후"로 명시.
- `.xcodeproj` 없음(빈 템플릿): 사용자에게 Phase 1(Xcode 신규 생성) 안내 후 대기.
- 계약 불확실: 추측 금지 → `server-gate` 실측 또는 계획서 §7.

## 테스트 시나리오
- **정상**: "Phase 4 연결 테스트 구현" → builder가 `AnthropicChatClient.health()`+`SettingsView` 버튼 구현 → ios-qa가 `/health` 계약·컴파일·완료기준("버튼으로 연결 여부+실패원인 구분") 검증 PASS → 보고.
- **에러**: builder가 `MessagesResponse`를 `content: String`으로 잘못 모델링 → ios-qa가 실제 응답(`content[]` 배열)과 경계면 불일치 검출 → builder에 수정 지시 → 재검증 PASS.

## 더 보기
- 구현 패턴·골격: `../swiftui-patterns/SKILL.md`
- 게이트: `../server-gate/SKILL.md` · 빌드: `../xcode-build-check/SKILL.md`
- 계획: `plans/swiftui-ollama-ios-mvp-plan.md` §6~9
