//
//  ChatTurn.swift
//  PocketLlama
//
//  UI/히스토리에서 다루는 한 차례의 대화(역할 + 텍스트).
//  멀티턴 계약(§7.2)에서 user/assistant 교대로 서버에 전송된다.
//  히스토리 content 는 문자열로 단순화(MVP). Codable 이라 최근 세션 저장(§8 Phase 8)에 그대로 쓴다.
//

import Foundation

struct ChatTurn: Identifiable, Equatable, Codable {
    let id: UUID
    let role: String   // "user" | "assistant"
    var content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    var isUser: Bool { role == "user" }
}
