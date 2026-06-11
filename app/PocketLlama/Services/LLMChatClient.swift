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
///
/// [Phase T1] tool 루프(§4 T2)를 위해 stopReason 과 toolUse 를 노출한다.
/// 기존 호출부는 text/truncated 만 읽으면 되므로 무수정 컴파일된다.
struct ChatCompletion: Equatable {
    let text: String
    let truncated: Bool
    /// 응답 stop_reason 원문(end_turn / max_tokens / tool_use / ...). 기본 nil.
    var stopReason: String?
    /// tool_use 블록이 있으면 (id, name, inputJSON). 없으면 nil.
    var toolUse: ToolUse?

    struct ToolUse: Equatable {
        let id: String
        let name: String
        let inputJSON: String
    }

    init(text: String, truncated: Bool, stopReason: String? = nil, toolUse: ToolUse? = nil) {
        self.text = text
        self.truncated = truncated
        self.stopReason = stopReason
        self.toolUse = toolUse
    }
}

/// 스트림(Phase 7) 이벤트. delta 는 누적, done(truncated:) 은 종료 시점에 잘림 여부를 전달한다.
enum StreamEvent: Equatable {
    case delta(String)
    /// [Phase T1] tool_use 블록 완성(content_block_stop 시점, §3). id/name + 누적 input JSON.
    case toolUse(id: String, name: String, inputJSON: String)
    case done(truncated: Bool)
}

protocol LLMChatClient: Sendable {
    /// GET /health → 200이면 true.
    func health() async throws -> Bool

    /// GET /v1/models → 모델 id 목록. 표시값은 첫 번째(data[0].id).
    func models() async throws -> [String]

    /// POST /v1/messages (비스트림, Phase 6). 멀티턴 history 를 user/assistant 교대로 전송,
    /// text 블록 합산 + 잘림 여부를 반환.
    /// [Phase T1] tools 기본값 nil — 기존 호출부는 무수정. nil 이면 일반 채팅 경로(회귀 0).
    func send(messages: [ChatTurn], system: String?, maxTokens: Int, tools: [ToolDefinition]?) async throws -> ChatCompletion

    /// POST /v1/messages (stream:true, Phase 7). text_delta 를 .delta 로 순차 yield,
    /// 종료(message_delta 의 stop_reason / message_stop) 시 .done(truncated:) 를 1회 방출한다.
    /// [Phase T1] tools 기본값 nil. tool_use 블록은 .toolUse 로 방출(§3).
    func stream(messages: [ChatTurn], system: String?, maxTokens: Int, tools: [ToolDefinition]?) -> AsyncThrowingStream<StreamEvent, Error>

    // MARK: - [Phase T1] tool 왕복용 wire 경로(블록 포함 메시지)
    // tool_result 회신(assistant tool_use + user tool_result)을 인코딩하려면 content 가
    // 블록 배열인 wire 메시지를 전송해야 한다(§3). ChatTurn(String content)로는 표현 불가하므로
    // MessagesRequest.Wire 를 직접 받는 경로를 별도로 둔다. T2 의 tool 루프가 사용한다.

    /// 비스트림 — 블록 포함 wire 메시지 전송(tool 왕복용, §4).
    func send(wire: [MessagesRequest.Wire], system: String?, maxTokens: Int, tools: [ToolDefinition]?) async throws -> ChatCompletion

    /// 스트림 — 블록 포함 wire 메시지 전송(tool 왕복용, §4).
    func stream(wire: [MessagesRequest.Wire], system: String?, maxTokens: Int, tools: [ToolDefinition]?) -> AsyncThrowingStream<StreamEvent, Error>
}

// MARK: - [Phase T1] 후방호환 기본 구현(기존 호출부 무수정 보장)
// 기존 ChatViewModel 은 `stream(messages:system:maxTokens:)` / `send(messages:system:maxTokens:)`
// 를 호출한다. tools 인자를 추가하면 호출부 수정이 필요하므로, tools 생략 오버로드를
// 프로토콜 extension 으로 제공해 호출부를 무수정으로 둔다.
extension LLMChatClient {
    func send(messages: [ChatTurn], system: String?, maxTokens: Int) async throws -> ChatCompletion {
        try await send(messages: messages, system: system, maxTokens: maxTokens, tools: nil)
    }

    func stream(messages: [ChatTurn], system: String?, maxTokens: Int) -> AsyncThrowingStream<StreamEvent, Error> {
        stream(messages: messages, system: system, maxTokens: maxTokens, tools: nil)
    }
}
