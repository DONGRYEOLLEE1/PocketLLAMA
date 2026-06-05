//
//  LLMChatClient.swift
//  PocketLlama
//
//  채팅 클라이언트 추상화(§4.6). Phase 10에서 OpenAIChatClient 를 같은 프로토콜로 추가하기 위함.
//  AnthropicChatClient 가 이 프로토콜을 구현한다.
//

import Foundation

protocol LLMChatClient: Sendable {
    /// GET /health → 200이면 true.
    func health() async throws -> Bool

    /// GET /v1/models → 모델 id 목록. 표시값은 첫 번째(data[0].id).
    func models() async throws -> [String]

    /// POST /v1/messages (비스트림). 멀티턴 history 를 user/assistant 교대로 전송, text 블록 합산 반환.
    func send(messages: [ChatTurn], system: String?, maxTokens: Int) async throws -> String

    /// POST /v1/messages (stream:true). text_delta 를 순차 yield 한다.
    func stream(messages: [ChatTurn], system: String?, maxTokens: Int) -> AsyncThrowingStream<String, Error>
}
