//
//  RootView.swift
//  PocketLlama
//
//  진입점(§9). 설정(base URL)이 미완료면 SettingsView, 완료면 ChatView.
//  설정은 시트로도 재진입 가능하게 한다.
//

import SwiftUI

struct RootView: View {
    @State private var settings = AppSettingsStore()

    var body: some View {
        Group {
            if settings.isConfigured, let baseURL = settings.baseURL {
                ChatView(settings: settings, baseURL: baseURL)
                    // baseURL/apiKey 가 바뀌면 ChatView(및 그 안의 ViewModel)를 새로 만든다.
                    .id(chatIdentity(baseURL))
            } else {
                NavigationStack {
                    SettingsView(settings: settings)
                }
            }
        }
        // [DesignSystem] 디자인 토큰을 전역 단일 소스로 주입. 모든 하위 View가 @Environment(\.theme)로 읽는다.
        .environment(\.theme, Theme())
        // 브랜드 액센트를 시스템 틴트로 — 토글·기본 컨트롤·네비게이션 강조까지 일관 보라.
        .tint(.plAccent)
        // ⚠️ 이 분기는 store 의 실시간 값에 반응한다. SettingsView 가 draft 로 편집하고
        //    "완료"에서만 store 에 커밋하므로, 입력 도중에는 isConfigured/baseURL 이
        //    바뀌지 않아 화면이 튕기지 않고 설정 시트도 닫히지 않는다.
    }

    /// base URL + apiKey 조합이 바뀌면 클라이언트를 다시 만들기 위한 식별자.
    /// 구분자는 URL·키에 나타날 수 있는 문자와 충돌하지 않도록 제어문자(US, 0x1F)를 쓴다.
    private func chatIdentity(_ url: URL) -> String {
        url.absoluteString + "\u{1F}" + settings.apiKey
    }
}

#Preview {
    RootView()
}
