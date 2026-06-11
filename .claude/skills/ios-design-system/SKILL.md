---
name: ios-design-system
description: PocketLlama 앱의 표준 디자인 시스템 — 디자인 토큰(색·그라데이션·타이포 스케일·간격·radius·머티리얼·모션)과 SwiftUI 테마/모디파이어/재사용 컴포넌트 패턴. 비주얼 스타일·색·타이포·말풍선·간격·다크모드·애니메이션·햅틱을 만들거나 수정할 때 반드시 따른다. ui-designer의 1차 참조. 방향성은 차별화·개성 우선(커스텀 팔레트·그라데이션·차별화 말풍선)이되 접근성은 토큰으로 보장. 후속도 포함: "색 바꿔", "테마 수정", "컴포넌트 추가", "말풍선 다듬어", "다크모드 손봐", "모션 추가".
---

# PocketLlama 디자인 시스템

PocketLlama의 비주얼 normative를 코드로 고정한다. 모든 색·타이포·간격·radius·모션은 **토큰을 거친다**. 화면 코드에 raw 값을 박지 않는다 — 한 곳에서 톤을 바꾸고, 일관성을 보장하고, 다크모드/Dynamic Type/접근성을 토큰 레벨에서 책임지기 위해서다.

방향성: **차별화·개성 우선**. 시스템 기본을 그대로 쓰지 않고 PocketLlama만의 정체성(따뜻하면서 로컬-LLM답게 차분한, 보라/제비꽃 계열 브랜드 + 그라데이션 + 부드러운 스프링 모션)을 만든다. 단 개성은 토큰 안에서 표현하고, 접근성(대비·Dynamic Type·44pt)은 토큰이 보장한다.

> 구체적 SwiftUI 코드(Theme 구조·Environment 주입·모디파이어·컴포넌트·햅틱 전문)는 `references/design-snippets.md` 참조 — 코드를 쓰기 직전에 읽는다.

## 1. 토큰 구조 (DesignSystem/)

```
app/PocketLlama/DesignSystem/
├── Theme.swift          토큰 집합(색·타이포·간격·radius·모션) + Environment 키
├── Palette.swift        색 토큰(semantic + 브랜드) — 라이트/다크 양쪽
├── Components/          재사용 스타일 컴포넌트(말풍선·버튼·카드 등)
└── Modifiers/           재사용 ViewModifier(.cardStyle() 등)
```

색은 가급적 **Assets.xcassets 컬러셋**(Any/Dark 양쪽 지정)으로 정의하고 토큰이 그 이름을 참조한다. 코드 리터럴 색이 필요하면 Palette에 한 번만 정의한다.

## 2. 토큰 카테고리 (각 토큰은 "역할"로 이름 짓는다)

| 카테고리 | 토큰 예시 | 원칙 |
|---|---|---|
| **색(semantic)** | `bgPrimary`, `bgElevated`, `textPrimary`, `textSecondary`, `userBubble`, `assistantBubble`, `accent`, `danger` | 역할 이름으로. `purple` 금지 → `accent`. 라이트/다크 양쪽 값 보유. |
| **브랜드 그라데이션** | `accentGradient`(2~3색 LinearGradient), `userBubbleGradient` | 개성의 핵심. 단 그 위 텍스트 대비는 가장 어두운 정지점 기준 AA 통과. |
| **타이포 스케일** | `.plTitle`, `.plBody`, `.plBubble`, `.plCaption` | **반드시 `relativeTo:`로 Dynamic Type에 연동**. 고정 `size:`만 쓰면 접근성 위반. |
| **간격(spacing)** | `.xs=4 .s=8 .m=12 .l=16 .xl=24 .xxl=32` | 8pt 그리드 기반 스케일. 매직 넘버 간격 금지. |
| **radius** | `.small=10 .medium=16 .large=22 .bubble=20` | `.continuous` 코너 스타일 권장(부드러운 개성). |
| **머티리얼** | `.bar`, `.thinMaterial`, `.regularMaterial` | 오버레이/상태바에. 단색 배경 남용 대신 깊이감. |
| **모션** | `.plQuick`(0.18 easeOut), `.plSpring`(response 0.4, damping 0.8) | 스프링을 기본 개성으로. reduce motion이면 즉시 전환 폴백. |

## 3. SwiftUI 적용 패턴

- **테마 주입**: `Theme`를 `Environment`로 주입하고 View에서 `@Environment(\.theme)`로 읽는다. 전역 단일 소스. (코드: 스니펫 §1)
- **모디파이어로 캡슐화**: 반복 스타일은 `ViewModifier` + `View` extension으로 — `.bubbleStyle(role:)`, `.cardStyle()`. 화면 코드를 선언적으로. (스니펫 §3)
- **재사용 컴포넌트**: 말풍선·1차 버튼처럼 여러 곳에 쓰이는 건 `Components/`의 별도 View로. ui-designer가 외형만, 데이터·콜백은 주입받는다.
- **차별화 말풍선**: user는 `userBubbleGradient` + 흰 텍스트, assistant는 `assistantBubble`(머티리얼/은은한 톤) + `textPrimary`. 꼬리·그림자·코너로 개성을. 단 대비 통과. (스니펫 §4)
- **햅틱**: 전송·완료·에러에 `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` 살짝. 과하지 않게. (스니펫 §5)

## 4. 불변 규칙 (어기면 critic FAIL)

- **토큰 우회 금지**: View에 raw `Color(red:...)`, `.font(.system(size: 17))`, 매직 간격/radius 직접 사용 금지. 전부 토큰 경유.
- **Dynamic Type 연동 필수**: 커스텀 폰트도 `.font(.system(size: 28, relativeTo: .title))` 또는 `ScaledMetric`으로. 고정 크기만 쓰지 않는다.
- **대비 보장**: 토큰 색 조합(특히 그라데이션 위 텍스트)은 AA 4.5:1(큰 글자 3:1) 이상. critic이 `contrast.py`로 검증한다.
- **양쪽 모드**: 모든 색 토큰은 라이트·다크 모두 정의. 하드코딩 `.white`/`.black` 배경 금지.
- **reduce motion 폴백**: 강한 모션은 `@Environment(\.accessibilityReduceMotion)` 분기로 약화/제거.
- **외형만**: 네트워킹·`ChatState`·`ViewModel` 로직은 건드리지 않는다(swift-builder 영역).

## 5. 시작 팔레트 (제안 — 고정 아님, 조정 가능)

차별화 방향의 출발점. 사용자/critic 피드백으로 조정한다. 오버피팅하지 말고 *시스템*을 따르되 이 값에서 시작:

- **accent**: 제비꽃 보라 `#7A5AF8` (다크에서 `#9B83FF`)
- **accentGradient**: `#7A5AF8 → #B66BFF` (135°)
- **bgPrimary**: 라이트 `#FAF9FF` / 다크 `#0E0B16` (순백·순흑 대신 보라 기운)
- **assistantBubble**: 라이트 `#F1EEFA` / 다크 `#1C1830`
- **textPrimary/Secondary**: semantic 시스템 라벨 우선 사용

이 값들은 대비를 미리 확인한 출발점이다. 바꿀 때는 반드시 `contrast.py`로 재확인한다.
