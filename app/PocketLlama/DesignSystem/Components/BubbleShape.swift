//
//  BubbleShape.swift
//  PocketLlama — DesignSystem / Components
//
//  차별화 말풍선 외형. user/assistant를 색·그라데이션·코너 비대칭("꼬리")으로 구분한다.
//  - user: 브랜드 보라 그라데이션 + 흰 텍스트 + 우하단 코너를 작게 깎아 "보낸 쪽" 꼬리.
//  - assistant: 은은한 보라 표면 + textPrimary + 좌하단 코너를 작게 깎아 "받은 쪽" 꼬리.
//  대비는 design-proposal.md 측정표에서 검증(그라데이션 두 정지점 모두 흰 텍스트 AA↑).
//
//  로직(turn·isUser·레이아웃)은 호출부 그대로 — 이 파일은 외형(배경·코너·그림자)만 캡슐화.
//

import SwiftUI

/// 한 모서리만 작게(꼬리) 깎는 비대칭 둥근 사각형. 말풍선 개성의 핵심.
struct BubbleShape: Shape {
    var bigRadius: CGFloat
    var tailRadius: CGFloat
    /// 꼬리(작은 코너)를 둘 모서리.
    var tailCorner: UnitPoint   // .bottomTrailing(user) 또는 .bottomLeading(assistant)

    func path(in rect: CGRect) -> Path {
        let tl: CGFloat = tailCorner == .topLeading     ? tailRadius : bigRadius
        let tr: CGFloat = tailCorner == .topTrailing    ? tailRadius : bigRadius
        let br: CGFloat = tailCorner == .bottomTrailing ? tailRadius : bigRadius
        let bl: CGFloat = tailCorner == .bottomLeading  ? tailRadius : bigRadius

        var p = Path()
        let w = rect.width, h = rect.height
        let minX = rect.minX, minY = rect.minY
        p.move(to: CGPoint(x: minX + tl, y: minY))
        p.addLine(to: CGPoint(x: minX + w - tr, y: minY))
        p.addArc(center: CGPoint(x: minX + w - tr, y: minY + tr),
                 radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: minX + w, y: minY + h - br))
        p.addArc(center: CGPoint(x: minX + w - br, y: minY + h - br),
                 radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: minX + bl, y: minY + h))
        p.addArc(center: CGPoint(x: minX + bl, y: minY + h - bl),
                 radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: minX, y: minY + tl))
        p.addArc(center: CGPoint(x: minX + tl, y: minY + tl),
                 radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - 말풍선 배경 모디파이어

struct BubbleBackground: ViewModifier {
    @Environment(\.theme) private var theme
    let isUser: Bool

    func body(content: Content) -> some View {
        let shape = BubbleShape(
            bigRadius: theme.radius.bubble,
            tailRadius: theme.radius.tail,
            tailCorner: isUser ? .bottomTrailing : .bottomLeading
        )
        return content
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
            .foregroundStyle(isUser ? Color.white : Color.plTextPrimary)
            .background {
                if isUser {
                    shape.fill(LinearGradient.plUserBubble)
                } else {
                    shape.fill(Color.plAssistantBubble)
                }
            }
            // user는 브랜드 보라 글로우, assistant는 미묘한 깊이 그림자.
            .shadow(
                color: isUser ? Color.plAccent.opacity(0.28) : Color.black.opacity(0.06),
                radius: isUser ? 9 : 4,
                y: isUser ? 4 : 2
            )
    }
}

extension View {
    /// 차별화 말풍선 외형 한 줄 적용 — 로직은 호출부 그대로.
    func bubbleStyle(isUser: Bool) -> some View { modifier(BubbleBackground(isUser: isUser)) }
}
