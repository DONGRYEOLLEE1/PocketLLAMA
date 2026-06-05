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
    }

    /// base URL + apiKey 조합이 바뀌면 클라이언트를 다시 만들기 위한 식별자.
    private func chatIdentity(_ url: URL) -> String {
        url.absoluteString + "|" + settings.apiKey
    }
}

#Preview {
    RootView()
}
