//
//  ModelInfoView.swift
//  PocketLlama
//
//  Phase 5. GET /v1/models → data[0].id 를 헤더에 표시.
//  실패해도 /health 가 200이면 "(이름 미상)" fallback 으로 채팅을 막지 않는다(§7.5).
//

import SwiftUI

struct ModelInfoView: View {
    @Environment(\.theme) private var theme
    let client: LLMChatClient

    @State private var modelName: String?
    @State private var didLoad = false

    var body: some View {
        HStack(spacing: theme.spacing.xs + 2) {
            // [DesignSystem] 모델 칩 — 연결됨을 보라 점으로 은은히 알리고, 라벨은 토큰 색.
            Circle()
                .fill(modelName != nil ? Color.plSuccess : Color.plTextSecondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Image(systemName: "cpu")
                .font(.plCaption)
                .foregroundStyle(.plAccent)
            Text(displayName)
                .font(.plCaption)
                .foregroundStyle(.plTextSecondary)
                .lineLimit(1)
        }
        .task {
            // /v1/models 실패는 무시(fallback). 채팅 진행을 막지 않는다.
            if let ids = try? await client.models(), let first = ids.first {
                modelName = first
            }
            didLoad = true
        }
    }

    private var displayName: String {
        if let modelName { return "모델: \(modelName)" }
        return didLoad ? "모델: (이름 미상)" : "모델 확인 중…"
    }
}
