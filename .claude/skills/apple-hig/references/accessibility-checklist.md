# 접근성 + HIG 상세 감사 체크리스트

design-critic이 화면별로 수행하는 상세 절차. 각 항목은 **코드 근거(파일·줄)** 와 함께 PASS/FAIL로 판정한다. 시뮬레이터 미설치 시 코드 정적 분석 기반으로 판정하고, 실기기 시각 확인이 필요한 항목은 "플랫폼 설치 후"로 표시한다.

## 목차
1. 대비 (Contrast)
2. Dynamic Type
3. 터치 타깃 (Hit Target)
4. VoiceOver / 레이블
5. 모션 / reduce motion
6. 다크/라이트 모드
7. 메시징 화면 HIG
8. 폼/설정 화면 HIG

---

## 1. 대비 (Contrast)

- [ ] 모든 **커스텀 색 위 텍스트** 조합을 `scripts/contrast.py`로 측정했는가.
- [ ] 일반 텍스트 ≥ 4.5:1, 큰 텍스트(≥24pt 또는 ≥19pt bold) ≥ 3:1.
- [ ] **그라데이션** 위 텍스트는 가장 불리한 정지점으로 측정했는가.
- [ ] 비활성(secondary/disabled) 텍스트도 최소 3:1 이상 — 너무 옅은 회색 주의.
- [ ] 아이콘·구분선 등 비텍스트 UI는 ≥ 3:1 (인지 가능).
- 측정 면제: `Color.primary`/`.secondary`/`.accentColor` 등 시스템 시맨틱 색.

**FAIL 표기 예**: `대비 — userBubble 그라데이션 밝은 끝 #B66BFF 위 흰 텍스트 = 2.9:1 < 4.5 (BubbleBackground.swift:18)`

## 2. Dynamic Type

- [ ] 본문 텍스트가 **시맨틱 폰트 스타일**(`.body`/`.headline`/`.caption`) 또는 `relativeTo:`를 쓰는가.
- [ ] 고정 `.font(.system(size: N))`이 본문/중요 텍스트에 쓰이지 않았는가 (장식적 1회성은 허용하되 표시).
- [ ] 큰 글자 크기에서 레이아웃이 깨지지 않게 `lineLimit`/`minimumScaleFactor`/줄바꿈을 고려했는가.
- [ ] 커스텀 크기가 필요하면 `@ScaledMetric`으로 스케일에 연동했는가.
- 도구: `grep -n "\.system(size:" app/PocketLlama` 로 고정 크기 탐지.

## 3. 터치 타깃 (Hit Target)

- [ ] 모든 탭 가능한 요소(버튼·토글·링크)가 ≥ 44×44pt인가.
- [ ] 작은 SF Symbol 버튼은 `.frame(minWidth:44,minHeight:44)` 또는 `.contentShape(Rectangle())`로 탭 영역을 확장했는가.
- [ ] 인접한 인터랙티브 요소 사이 간격이 충분한가(오탭 방지).

## 4. VoiceOver / 레이블

- [ ] **아이콘 전용 버튼**에 `.accessibilityLabel`이 있는가 (새 대화·설정·전송·취소 등).
- [ ] 순수 장식 이미지는 `.accessibilityHidden(true)` 또는 라벨 생략.
- [ ] 상태 변화(전송 중·에러)가 VoiceOver로 전달되는가 — 중요 상태는 `.accessibilityElement`/라벨 갱신 고려.
- [ ] 말풍선이 "사용자/어시스턴트" 화자를 구분해 읽히는가(레이블 또는 구조).

## 5. 모션 / reduce motion

- [ ] 등장/전환/스프링 애니메이션에 `@Environment(\.accessibilityReduceMotion)` 분기가 있는가.
- [ ] reduce motion일 때 큰 이동·스케일·시차 효과가 제거/약화되는가(페이드 정도만).
- [ ] 자동 스크롤·로딩 모션이 과하지 않은가.

## 6. 다크/라이트 모드

- [ ] 모든 색 토큰이 라이트·다크 양쪽 값을 갖는가(컬러셋 Any/Dark 또는 동적 색).
- [ ] 하드코딩 `.white`/`.black` 배경·텍스트가 없는가 — 한 모드에서 대비가 깨진다.
- [ ] 그림자·그라데이션이 다크에서 과하거나(번짐) 사라지지(안 보임) 않는가.
- [ ] 두 모드 각각에서 §1 대비를 만족하는가.

## 7. 메시징 화면 HIG (ChatView)

- [ ] 사용자 메시지 trailing, 어시스턴트 leading 정렬.
- [ ] 입력 바 하단 고정 + 키보드 회피(세이프에어리어 inset).
- [ ] 자동 스크롤이 새 메시지에 자연스럽게 따라가는가.
- [ ] 빈 상태가 친절하고 브랜드감 있게(차별화 기회) 표현됐는가.
- [ ] 전송/취소 상태 전환이 시각적으로 명확한가(35B 지연 정직성).
- [ ] 에러 배너가 눈에 띄되 닫을 수 있는가.

## 8. 폼/설정 화면 HIG (SettingsView)

- [ ] `Form`/`List` 섹션·푸터로 그룹화·설명.
- [ ] 입력 필드 라벨·플레이스홀더 명확.
- [ ] 서버 URL/키 검증 피드백 즉각적이고 이해 가능.
- [ ] 완료/취소 동작이 표준 위치·동작.
