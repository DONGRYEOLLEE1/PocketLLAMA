//
//  ModelInfoView.swift
//  PocketLlama
//
//  Phase 5. GET /v1/models → data[0].id 를 헤더에 표시.
//  실패해도 /health 가 200이면 "(이름 미상)" fallback 으로 채팅을 막지 않는다(§7.5).
//

import SwiftUI

struct ModelInfoView: View {
    let client: LLMChatClient

    @State private var modelName: String?
    @State private var didLoad = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
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
