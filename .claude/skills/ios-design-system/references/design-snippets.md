# PocketLlama 디자인 시스템 — SwiftUI 스니펫

ui-designer가 `DesignSystem/`을 만들 때의 골격. 그대로 복붙하지 말고 시작점으로 — 토큰 값·이름은 SKILL.md 규칙을 따른다. iOS 17+ 가정.

## 목차
1. Theme + Environment 주입
2. Palette (색 토큰, 라이트/다크)
3. ViewModifier (재사용 스타일)
4. 차별화 말풍선 컴포넌트
5. 햅틱 헬퍼
6. 모션 + reduce motion 폴백

---

## 1. Theme + Environment 주입

```swift
// DesignSystem/Theme.swift
import SwiftUI

struct Theme {
    let spacing = Spacing()
    let radius  = Radius()
    let motion  = Motion()

    struct Spacing { let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12,
                         l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32 }
    struct Radius  { let small: CGFloat = 10, medium: CGFloat = 16,
                         large: CGFloat = 22, bubble: CGFloat = 20 }
    struct Motion  {
        let quick  = Animation.easeOut(duration: 0.18)
        let spring  = Animation.spring(response: 0.4, dampingFraction: 0.8)
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme() }
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
```

루트(`PocketLlamaApp` 또는 `RootView`)에서 `.environment(\.theme, Theme())`. View에서 `@Environment(\.theme) private var theme`.

타이포 스케일은 `Font` extension으로 (Dynamic Type 연동 필수):

```swift
// DesignSystem/Theme.swift (계속)
extension Font {
    static let plTitle   = Font.system(size: 28, weight: .bold,     design: .rounded)
    static let plBody    = Font.system(.body,  design: .rounded)            // 시스템 스타일 = 자동 스케일
    static let plBubble  = Font.system(.body,  design: .rounded)
    static let plCaption = Font.system(.caption, design: .rounded)
}
// 고정 size가 꼭 필요하면 relativeTo로: .system(size: 28, weight: .bold, design: .rounded) 는
// title 토큰처럼 ScaledMetric으로 감싸거나 .dynamicTypeSize(...) 상한만 둔다.
```

## 2. Palette (색 토큰, 라이트/다크)

색은 **Assets.xcassets 컬러셋(Any/Dark 지정)**을 우선으로 하고, 토큰이 그 이름을 참조한다:

```swift
// DesignSystem/Palette.swift
import SwiftUI

extension Color {
    // 컬러셋이 있으면 이렇게 (Assets에 "AccentViolet", "BgPrimary" 등 Any/Dark 정의)
    static let plAccent          = Color("AccentViolet")
    static let plBgPrimary       = Color("BgPrimary")
    static let plAssistantBubble = Color("AssistantBubble")

    // semantic은 시스템 라벨을 우선 사용 (자동 다크모드 + 대비 보장)
    static let plTextPrimary   = Color.primary
    static let plTextSecondary = Color.secondary
}

extension LinearGradient {
    static let plAccent = LinearGradient(
        colors: [Color("AccentViolet"), Color("AccentMagenta")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
```

> 컬러셋을 추가할 수 없는 상황이면 `Color(red:green:blue:)` 리터럴을 Palette에 **한 번만** 정의하고, 다크 대응은 `UIColor { trait in ... }` 동적 컬러로 감싼다. 화면 코드에는 절대 리터럴을 두지 않는다.

## 3. ViewModifier (재사용 스타일)

```swift
// DesignSystem/Modifiers/CardStyle.swift
import SwiftUI

struct CardStyle: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .padding(theme.spacing.l)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: theme.radius.medium, style: .continuous))
    }
}
extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
```

## 4. 차별화 말풍선 컴포넌트

user = 브랜드 그라데이션 + 흰 텍스트, assistant = 은은한 톤/머티리얼. 대비는 critic이 `contrast.py`로 확인.

```swift
// DesignSystem/Components/BubbleBackground.swift
import SwiftUI

struct BubbleBackground: ViewModifier {
    @Environment(\.theme) private var theme
    let isUser: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
            .foregroundStyle(isUser ? Color.white : Color.plTextPrimary)
            .background {
                let shape = RoundedRectangle(cornerRadius: theme.radius.bubble, style: .continuous)
                if isUser {
                    shape.fill(LinearGradient.plAccent)
                } else {
                    shape.fill(Color.plAssistantBubble)
                }
            }
            .shadow(color: isUser ? Color.plAccent.opacity(0.25) : .clear, radius: 8, y: 3)
    }
}
extension View {
    func bubbleStyle(isUser: Bool) -> some View { modifier(BubbleBackground(isUser: isUser)) }
}
```

기존 `MessageBubble`(ChatView.swift)의 `.background(...).foregroundStyle(...).clipShape(...)` 블록을 `.bubbleStyle(isUser: turn.isUser)` 한 줄로 치환 — **로직(`turn`·`isUser`·레이아웃)은 그대로**, 외형만 토큰화.

## 5. 햅틱 헬퍼

```swift
// DesignSystem/Haptics.swift
import UIKit

enum Haptics {
    static func tap()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success()  { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()    { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
// 사용처는 외형 트리거(전송 버튼 탭 등)에만. ViewModel 로직에 끼워넣지 않는다.
```

## 6. 모션 + reduce motion 폴백

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@Environment(\.theme) private var theme

withAnimation(reduceMotion ? nil : theme.motion.spring) {
    // 스프링 등장. reduce motion이면 즉시 전환.
}
```

말풍선 등장은 `.transition(.move(edge: .bottom).combined(with: .opacity))` + 위 스프링. reduce motion이면 `.opacity`만.
