//
//  Theme.swift
//  PocketLlama — DesignSystem
//
//  비-색 토큰: 간격(8pt 그리드)·radius·모션. Environment(\.theme)로 단일 소스 주입.
//  타이포 스케일은 Font extension(아래) — 전부 Dynamic Type에 연동(고정 size 금지/relativeTo).
//
//  화면 코드에 매직 넘버(간격 17, cornerRadius 16, duration 0.18)를 직접 박지 않는다.
//  한 곳에서 리듬을 바꾸고 일관성을 보장하기 위해서다.
//

import SwiftUI

struct Theme {
    let spacing = Spacing()
    let radius  = Radius()
    let motion  = Motion()

    /// 8pt 그리드 기반 간격 스케일.
    struct Spacing {
        let xxs: CGFloat = 2
        let xs:  CGFloat = 4
        let s:   CGFloat = 8
        let m:   CGFloat = 12
        let l:   CGFloat = 16
        let xl:  CGFloat = 24
        let xxl: CGFloat = 32
    }

    /// 코너 반경 스케일. 부드러운 개성을 위해 사용처에서 `.continuous` 스타일과 함께 쓴다.
    struct Radius {
        let small:  CGFloat = 10
        let medium: CGFloat = 16
        let large:  CGFloat = 22
        let bubble: CGFloat = 20   // 말풍선 — 꼬리 쪽은 작게 비대칭으로 깎아 개성.
        let tail:   CGFloat = 6    // 말풍선 "꼬리" 코너(보낸 쪽 모서리).
    }

    /// 모션 토큰. 스프링을 기본 개성으로. reduce motion이면 사용처에서 nil 폴백.
    struct Motion {
        /// 짧은 상태 전환(배너 등장/사라짐).
        let quick  = Animation.easeOut(duration: 0.18)
        /// 기본 스프링 — 말풍선 등장·시트 콘텐츠.
        let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
        /// 더 통통 튀는 강조 스프링 — 전송 직후·브리핑 카드 등장.
        let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.7)
    }
}

// MARK: - Environment 주입

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme() }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - 타이포 스케일 (Dynamic Type 연동 필수)

extension Font {
    /// 대형 타이틀 — 브랜드 모먼트(빈 상태 등). rounded + bold로 친근한 개성.
    /// 텍스트 스타일(.title) 기반이라 사용자 글자 크기 설정에 자동 스케일된다(고정 size 아님).
    static let plDisplay = Font.system(.title, design: .rounded).weight(.bold)

    /// 섹션/카드 타이틀.
    static let plTitle = Font.system(.title3, design: .rounded).weight(.semibold)

    /// 헤드라인(빈 상태 제목·강조 라벨).
    static let plHeadline = Font.system(.headline, design: .rounded)

    /// 본문(채팅 입력·일반 텍스트).
    static let plBody = Font.system(.body, design: .rounded)

    /// 말풍선 본문 — 본문과 같되 의도 분리(추후 독립 조정 여지).
    static let plBubble = Font.system(.body, design: .rounded)

    /// 캡션(상태/보조 텍스트).
    static let plCaption = Font.system(.caption, design: .rounded)

    /// 가장 작은 메타 라벨(저장됨·언어 태그).
    static let plCaption2 = Font.system(.caption2, design: .rounded)
}
