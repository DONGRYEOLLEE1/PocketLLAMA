---
name: apple-hig
description: Apple Human Interface Guidelines + iOS 접근성 지식베이스 — 네비게이션·머티리얼·타이포·색·다크모드·SF Symbols·터치 타깃(44pt)·Dynamic Type·VoiceOver·reduce motion. 디자인이 HIG 핵심과 접근성을 지키는지 검증하거나, 디자인의 HIG 제약을 확인할 때 반드시 참조한다. design-critic의 1차 체크리스트. 대비 비율은 scripts/contrast.py로 수치 측정한다. 차별화·개성 방향에서 "외형은 자유, 접근성·시스템 동작은 불가침"의 경계를 정의한다. 후속도 포함: "접근성 점검", "HIG 위반 확인", "대비 다시 재봐", "다크모드 검수".
---

# Apple HIG + 접근성 (PocketLlama 검증 기준)

design-critic이 디자인 품질을 판정하는 기준선. PocketLlama의 방향은 **차별화·개성 우선**이므로, 이 스킬의 역할은 "시스템 기본을 강요"하는 게 아니라 **개성이 넘지 말아야 할 선(접근성·시스템 동작)을 지키는지** 검증하는 것이다.

> 화면별·항목별 상세 감사 절차는 `references/accessibility-checklist.md` 참조 — 실제 감사를 수행하기 직전에 읽는다.

## 핵심 프레임: 자유 vs 불가침

| 자유 (디자이너 재량 — critic이 막지 않음) | 불가침 (위반 시 critic FAIL) |
|---|---|
| 색 팔레트·그라데이션·브랜드 톤 | **대비**: 텍스트 AA 4.5:1 (큰 글자 3:1) |
| 타이포 스케일·라운드 폰트·웨이트 | **Dynamic Type**: 텍스트가 글자 크기 설정에 반응 |
| 말풍선 모양·꼬리·그림자·코너 | **터치 타깃**: 인터랙티브 요소 ≥ 44×44pt |
| 모션 곡선·스프링·전환·햅틱 | **reduce motion** 폴백 존재 |
| 카드·일러스트·장식 | **VoiceOver**: 아이콘 버튼에 라벨, 의미 전달 |
| 커스텀 빈 상태·로딩 표현 | **세이프에어리어**·시스템 제스처 존중 |
|  | **다크/라이트** 양쪽에서 깨지지 않음 |

핵심: 개성은 "보기"의 문제, 불가침은 "쓸 수 있는가"의 문제다. 못 읽거나 못 누르는 화면은 아무리 차별화돼도 실패다.

## 대비 측정 (필수 — 인상평 금지)

색 토큰 조합은 추측하지 말고 측정한다:

```bash
python3 .claude/skills/apple-hig/scripts/contrast.py "#FFFFFF" "#7A5AF8"
# → 대비 비율 4.52:1, 일반 AA PASS / AAA FAIL ...
```

- **그라데이션 위 텍스트**는 가장 불리한(어두운 글자면 가장 밝은, 밝은 글자면 가장 어두운) 정지점으로 측정한다.
- semantic 시스템 색(`Color.primary`/`.secondary`)은 Apple이 대비를 보장하므로 측정 면제. 커스텀 색 위 텍스트만 측정 대상.
- 결과는 리포트에 "색1 vs 색2 = X:1, 파일·줄"로 기록.

## HIG 핵심 점검 (이 앱에 해당하는 것만)

PocketLlama는 화면이 둘이다 — **채팅(메시징)**, **설정(폼)** + 모델 정보 바. 과한 일반론 대신 이 둘에 집중:

- **네비게이션**: `NavigationStack` + inline 타이틀 일관. 툴바 아이콘(새 대화·설정)은 표준 위치(leading/trailing). 커스텀 색을 입혀도 위치·동작은 표준.
- **메시징 패턴**: 보낸 메시지=trailing 정렬, 받은 메시지=leading. 입력 바는 하단 고정, 키보드 회피(세이프에어리어). 차별화는 말풍선 *외형*에서.
- **폼(설정)**: `Form`/`List` 그룹·섹션·푸터 설명 활용. 입력 검증 피드백 명확히.
- **머티리얼·깊이**: 상태바·오버레이는 `.bar`/`.thinMaterial`로 깊이감(단색 떡칠 대신).
- **SF Symbols**: 아이콘은 SF Symbols 우선(자동 Dynamic Type·웨이트 일치). 임의 비트맵 아이콘 지양.
- **로딩·지연 정직성**: 35B 모델은 첫 응답이 느리다. 진행 상태를 시각적으로(스피너·상태 텍스트) — "멈춘 듯"을 디자인으로 가린다.

## 접근성 빠른 점검 (상세는 reference)

1. **대비** — contrast.py로 모든 커스텀 색 조합.
2. **Dynamic Type** — 고정 `.font(.system(size:))` 남용 탐지. 텍스트는 시맨틱 스타일 또는 `relativeTo:`.
3. **터치 타깃** — 버튼·탭 영역 ≥ 44pt. 작은 아이콘은 `.frame`/`.contentShape`로 확장.
4. **VoiceOver** — 아이콘 전용 버튼에 `.accessibilityLabel`. 장식 이미지는 숨김.
5. **reduce motion** — 강한 애니메이션에 `@Environment(\.accessibilityReduceMotion)` 분기.
6. **다크/라이트** — 두 모드 모두에서 대비·가독성 확인. 하드코딩 흰/검 금지.

## 출력 형식 (critic이 쓸 것)

각 항목 PASS/FAIL + 근거. 예:
- `[FAIL] 대비 — 사용자 말풍선 흰 텍스트 위 #C9B8FF = 1.6:1 < AA 4.5 (ChatView.swift:248). 그라데이션 어두운 정지점을 #6A4AE0로.`
- `[PASS] 터치 타깃 — 전송 버튼 44pt 이상 (ChatView.swift:184).`
- `[FAIL] Dynamic Type — 타이틀 .system(size: 28) 고정 (Theme.swift:12). ScaledMetric 또는 relativeTo: .title 로.`
