//
//  Palette.swift
//  PocketLlama — DesignSystem
//
//  색 토큰 (semantic + 브랜드). 전부 Assets.xcassets 컬러셋(Any/Dark 페어)을 참조한다.
//  화면 코드에는 raw Color(red:...)/시스템 기본색을 직접 두지 않는다 — 한 곳에서 톤을
//  바꾸고, 라이트/다크·대비를 토큰 레벨에서 책임지기 위해서다.
//
//  팔레트 정체성: "포켓 속 라마, 아침의 따뜻함".
//  - 보라/제비꽃 브랜드(차분한 로컬-LLM) + 아침 햇살의 따뜻한 앰버 액센트.
//  - 순백·순흑 배경 대신 보라 기운이 도는 bg(FBF8FF / 0F0B1A).
//  모든 텍스트 조합의 대비는 _workspace/design-proposal.md 표에서 측정·검증(AA 4.5:1↑).
//

import SwiftUI

// 컬러셋은 도메인 이름(BrandAccent 등)으로 Assets에 정의되어 있고, Xcode가 그 이름으로
// Color.brandAccent 등을 자동 생성한다. 여기서는 화면 코드가 부를 의미 토큰(plXxx)을
// 그 위에 한 겹 별칭으로 얹는다 — 자동 심볼과 이름이 겹치지 않게 의미 prefix(pl)를 유지.
extension Color {
    // MARK: 브랜드 / 액센트
    /// 브랜드 제비꽃 보라. 아이콘·선택 강조·링크성 텍스트에. (라이트 #6B4DE6 / 다크 #B6A0FF)
    static let plAccent      = Color("BrandAccent")
    /// 채움(fill)용 액센트 — borderedProminent 버튼 등 흰 텍스트를 얹는 배경. (다크는 살짝 어둡게 #6A4BE0)
    static let plAccentFill  = Color("BrandAccentFill")
    /// 텍스트로 쓰는 액센트(대비 안전판). plAccent와 동일하지만 의도를 분리해 둔다.
    static let plAccentText  = Color("BrandAccentText")

    /// 따뜻한 아침 앰버. 브리핑 시그니처·강조 글리프. (라이트 #9A5B12 / 다크 #F2B765)
    static let plWarmAccent  = Color("WarmAccent")

    // MARK: 배경 (semantic)
    /// 화면 기본 배경(보라 기운). (라이트 #FBF8FF / 다크 #0F0B1A)
    static let plBgPrimary   = Color("SurfacePrimary")
    /// 한 단계 떠 있는 배경 — 입력바·상태바·카드 하층. (라이트 #F4F0FC / 다크 #1B1530)
    static let plBgElevated  = Color("SurfaceElevated")

    // MARK: 말풍선
    /// 어시스턴트 말풍선 배경(은은한 보라 톤). (라이트 #F0ECFB / 다크 #211B36)
    static let plAssistantBubble = Color("AssistantBubble")
    /// 사용자 말풍선 그라데이션 시작색. (라이트 #6B4DE6 / 다크 #5E42D6)
    static let plUserBubbleStart = Color("UserBubbleStart")
    /// 사용자 말풍선 그라데이션 끝색 — 흰 텍스트가 본문 AA를 통과하는 가장 밝은 정지점. (#7B5AF0 / #6A4BE0)
    static let plUserBubbleEnd   = Color("UserBubbleEnd")

    // MARK: 텍스트 (semantic)
    /// 기본 텍스트. (라이트 #1A1430 / 다크 #ECE8F5)
    static let plTextPrimary   = Color("InkPrimary")
    /// 보조 텍스트(캡션·설명). (라이트 #6B6580 / 다크 #A39CC0)
    static let plTextSecondary = Color("InkSecondary")

    // MARK: 상태 색
    /// 위험/오류. (라이트 #C2362B / 다크 #CF4338)
    static let plDanger  = Color("StatusDanger")
    /// 성공/연결됨. (라이트 #1E7A3D / 다크 #5BD681)
    static let plSuccess = Color("StatusSuccess")

    // MARK: 날씨 칩 라벨(브리핑)
    /// 최고기온. (라이트 #B23A16 / 다크 #FF8A5C)
    static let plWeatherHigh = Color("WeatherHigh")
    /// 최저기온. (라이트 #1F5FB8 / 다크 #6FA8FF)
    static let plWeatherLow  = Color("WeatherLow")
    /// 강수확률. (라이트 #0E6E78 / 다크 #4FC3D4)
    static let plWeatherPop  = Color("WeatherPop")
}

// MARK: - ShapeStyle 노출 (leading-dot 추론용)
//
// `.foregroundStyle(.plAccent)` / `.fill(.plAccent)` / `.tint(.plAccent)` 처럼 leading-dot 으로
// 쓰려면 토큰이 ShapeStyle 컨텍스트에서도 보여야 한다(Color static 만으로는 추론 실패).
// 자동 생성 Asset 심볼과 이름이 겹치지 않게 plXxx 별칭을 ShapeStyle 쪽에도 한 겹 더 노출한다.
extension ShapeStyle where Self == Color {
    static var plAccent: Color          { Color.plAccent }
    static var plAccentFill: Color      { Color.plAccentFill }
    static var plAccentText: Color      { Color.plAccentText }
    static var plWarmAccent: Color      { Color.plWarmAccent }
    static var plBgPrimary: Color       { Color.plBgPrimary }
    static var plBgElevated: Color      { Color.plBgElevated }
    static var plAssistantBubble: Color { Color.plAssistantBubble }
    static var plUserBubbleStart: Color { Color.plUserBubbleStart }
    static var plUserBubbleEnd: Color   { Color.plUserBubbleEnd }
    static var plTextPrimary: Color     { Color.plTextPrimary }
    static var plTextSecondary: Color   { Color.plTextSecondary }
    static var plDanger: Color          { Color.plDanger }
    static var plSuccess: Color         { Color.plSuccess }
    static var plWeatherHigh: Color     { Color.plWeatherHigh }
    static var plWeatherLow: Color      { Color.plWeatherLow }
    static var plWeatherPop: Color      { Color.plWeatherPop }
}

// MARK: - 브랜드 그라데이션

extension LinearGradient {
    /// 사용자 말풍선 그라데이션(좌상→우하). 두 정지점 모두 흰 텍스트 AA 통과.
    static let plUserBubble = LinearGradient(
        colors: [.plUserBubbleStart, .plUserBubbleEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 브랜드 액센트 그라데이션 — 빈 상태 글리프·강조 배지 등 장식용(텍스트 비탑재).
    static let plAccentSweep = LinearGradient(
        colors: [.plUserBubbleStart, .plUserBubbleEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 아침 브리핑 시그니처 — 보라에서 따뜻한 앰버로 번지는 새벽빛(카드 헤더/글리프 장식용).
    static let plMorning = LinearGradient(
        colors: [.plAccent, .plWarmAccent],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
