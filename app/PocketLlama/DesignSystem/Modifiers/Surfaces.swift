//
//  Surfaces.swift
//  PocketLlama — DesignSystem / Modifiers
//
//  재사용 표면(surface) 스타일 — 카드·시그니처 카드·화면 배경. 전부 토큰 경유.
//  화면 코드에서 `.cardStyle()` / `.plScreenBackground()` 한 줄로 선언적으로 쓴다.
//

import SwiftUI

// MARK: - 일반 카드(은은한 보라 표면 + continuous 코너)

struct CardStyle: ViewModifier {
    @Environment(\.theme) private var theme
    var tint: Color = .plBgElevated

    func body(content: Content) -> some View {
        content
            .padding(theme.spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tint,
                in: RoundedRectangle(cornerRadius: theme.radius.medium, style: .continuous)
            )
    }
}

extension View {
    /// 표준 카드: 토큰 패딩 + elevated 표면 + medium continuous 코너.
    func cardStyle(tint: Color = .plBgElevated) -> some View {
        modifier(CardStyle(tint: tint))
    }
}

// MARK: - 시그니처 카드(브리핑 — 새벽빛 보더로 차별화)

struct SignatureCardStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(theme.spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: theme.radius.large, style: .continuous)
            )
            .overlay(
                // 새벽빛(보라→앰버) 얇은 보더 — 아침 브리핑의 시그니처 디테일.
                RoundedRectangle(cornerRadius: theme.radius.large, style: .continuous)
                    .strokeBorder(LinearGradient.plMorning.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: Color.plAccent.opacity(0.12), radius: 14, y: 6)
    }
}

extension View {
    /// 브리핑 시그니처 카드: 머티리얼 + 새벽빛 그라데이션 보더 + 부드러운 보라 그림자.
    func signatureCardStyle() -> some View { modifier(SignatureCardStyle()) }
}

// MARK: - 화면 배경(보라 기운 그라데이션 — 순백/순흑 탈피)

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            LinearGradient(
                colors: [.plBgPrimary, .plBgElevated],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

extension View {
    /// 화면 전체 배경 — bgPrimary→bgElevated 미묘한 세로 그라데이션(보라 기운, 깊이감).
    func plScreenBackground() -> some View { modifier(ScreenBackground()) }
}
