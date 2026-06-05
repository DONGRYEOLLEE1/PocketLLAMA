//
//  LLMChatClient.swift
//  PocketLlama
//
//  채팅 클라이언트 추상화(§4.6). Phase 10에서 OpenAIChatClient 를 같은 프로토콜로 추가하기 위함.
//  AnthropicChatClient 가 이 프로토콜을 구현한다.
//

import Foundation

/// 비스트림 응답 1건(Phase 6). 잘림 여부(stop_reason=="max_tokens")를 함께 전달해
/// ViewModel 이 "응답이 max_tokens 로 잘렸습니다" 안내를 덧붙일 수 있게 한다.
struct ChatCompletion: Equatable {
    let text: String
    let truncated: Bool
}

/// 스트림(Phase 7) 이벤트. delta 는 누적, done(truncated:) 은 종료 시점에 잘림 여부를 전달한다.
enum StreamEvent: Equatable {
    case delta(String)
    case done(truncated: Bool)
}

protocol LLMChatClient: Sendable {
    /// GET /health → 200이면 true.
    func health() async throws -> Bool

    /// GET /v1/models → 모델 id 목록. 표시값은 첫 번째(data[0].id).
    func models() async throws -> [String]

    /// POST /v1/messages (비스트림, Phase 6). 멀티턴 history 를 user/assistant 교대로 전송,
    /// text 블록 합산 + 잘림 여부를 반환.
    func send(messages: [ChatTurn], system: String?, maxTokens: Int) async throws -> ChatCompletion

    /// POST /v1/messages (stream:true, Phase 7). text_delta 를 .delta 로 순차 yield,
    /// 종료(message_delta 의 stop_reason / message_stop) 시 .done(truncated:) 를 1회 방출한다.
    func stream(messages: [ChatTurn], system: String?, maxTokens: Int) -> AsyncThrowingStream<StreamEvent, Error>
}
