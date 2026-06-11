//
//  AnthropicChatClient.swift
//  PocketLlama
//
//  Anthropic 호환 /v1/messages 클라이언트(URLSession raw HTTP — Swift 공식 SDK 없음).
//  계획서 §7(계약)·§8(iOS)를 따른다:
//  - base URL 만 보관하고 경로를 조립(§7.1)
//  - max_tokens 필수, model "local"
//  - 비스트림 data(for:), 스트림 bytes(for:) + SSEDecoder(§7.4)
//  - 에러는 ClientError 로 분류(§7.6)
//

import Foundation

struct AnthropicChatClient: LLMChatClient {
    let baseURL: URL
    var apiKey: String?          // 비어 있으면 무인증(권장 A, §4.5)
    let model: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String? = nil, model: String = "local") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true            // §8.1
        cfg.timeoutIntervalForRequest = 180        // 35B TTFT 대비 넉넉히(단 취소 가능)
        cfg.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - 요청 조립

    /// base URL 위에 경로를 안전하게 조립(§7.1). path 는 선행 슬래시 없이.
    private func makeRequest(_ path: String, body: Data?) -> URLRequest {
        let url: URL
        if #available(iOS 16.0, macOS 13.0, *) {
            url = baseURL.appending(path: path)
        } else {
            url = baseURL.appendingPathComponent(path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let key = apiKey, !key.isEmpty {
            // §4.5: 헤더 형식은 게이트 실측 후 고정. Anthropic 경로 기준 x-api-key 사용.
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        req.httpBody = body
        return req
    }

    /// [Phase T1] 블록 포함 wire 메시지 + tools 를 받는 통합 인코더.
    /// ChatTurn 경로는 .text(String) wire 로 변환해 이 함수로 합류한다(회귀 0).
    private func encodeBody(wire: [MessagesRequest.Wire], system: String?, maxTokens: Int, stream: Bool?, tools: [ToolDefinition]?) throws -> Data {
        let request = MessagesRequest(
            model: model,
            max_tokens: maxTokens,           // ⚠️ 필수
            system: (system?.isEmpty == false) ? system : nil,
            messages: wire,
            stream: stream,
            tools: tools                     // nil 이면 인코딩 생략(일반 채팅 wire 불변)
        )
        return try JSONEncoder().encode(request)
    }

    /// ChatTurn(String content) → 텍스트 wire 변환(기존 텍스트 턴, 회귀 0).
    private func toWire(_ messages: [ChatTurn]) -> [MessagesRequest.Wire] {
        messages.map { .init(role: $0.role, content: $0.content) }
    }

    // MARK: - LLMChatClient

    func health() async throws -> Bool {
        do {
            let (_, resp) = try await session.data(for: makeRequest("health", body: nil))
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            throw Self.map(error)
        }
    }

    func models() async throws -> [String] {
        do {
            let (data, resp) = try await session.data(for: makeRequest("v1/models", body: nil))
            try Self.ensureOK(resp, data)
            do {
                return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id)
            } catch {
                throw ClientError.decoding(String(describing: error))
            }
        } catch let e as ClientError {
            throw e
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: 비스트림 send (ChatTurn 경로 + wire 경로)

    func send(messages: [ChatTurn], system: String?, maxTokens: Int, tools: [ToolDefinition]?) async throws -> ChatCompletion {
        try await send(wire: toWire(messages), system: system, maxTokens: maxTokens, tools: tools)
    }

    /// [Phase T1] 블록 포함 wire 경로 — tool 왕복 회신 전송(§3). 비스트림.
    func send(wire: [MessagesRequest.Wire], system: String?, maxTokens: Int, tools: [ToolDefinition]?) async throws -> ChatCompletion {
        do {
            let body = try encodeBody(wire: wire, system: system, maxTokens: maxTokens, stream: nil, tools: tools)
            let (data, resp) = try await session.data(for: makeRequest("v1/messages", body: body))
            try Self.ensureOK(resp, data)
            do {
                let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
                // [Phase T1] tool_use 블록·stop_reason 을 함께 노출(§3 — T2 tool 루프용).
                let toolUse = decoded.toolUse.map {
                    ChatCompletion.ToolUse(id: $0.id, name: $0.name, inputJSON: $0.inputJSON)
                }
                return ChatCompletion(
                    text: decoded.text,
                    truncated: decoded.wasTruncated,
                    stopReason: decoded.stop_reason,
                    toolUse: toolUse
                )
            } catch {
                throw ClientError.decoding(String(describing: error))
            }
        } catch let e as ClientError {
            throw e
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: 스트림 (ChatTurn 경로 + wire 경로)

    func stream(messages: [ChatTurn], system: String?, maxTokens: Int, tools: [ToolDefinition]?) -> AsyncThrowingStream<StreamEvent, Error> {
        stream(wire: toWire(messages), system: system, maxTokens: maxTokens, tools: tools)
    }

    /// [Phase T1] 블록 포함 wire 경로 — tool 왕복 회신 스트림(§3).
    func stream(wire: [MessagesRequest.Wire], system: String?, maxTokens: Int, tools: [ToolDefinition]?) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try encodeBody(wire: wire, system: system, maxTokens: maxTokens, stream: true, tools: tools)
                    let (bytes, resp) = try await session.bytes(for: makeRequest("v1/messages", body: body))
                    try Self.ensureOK(resp, nil)

                    let decoder = SSEDecoder()
                    var truncated = false
                    var done = false

                    // [Phase T1] tool_use 블록 캡처 상태. content_block_start(tool_use)에서 시작,
                    // input_json_delta 로 partial_json 누적, content_block_stop 에서 .toolUse 방출(§3).
                    var pendingToolID: String?
                    var pendingToolName: String?
                    var pendingToolJSON = ""

                    // ⚠️ bytes.lines(AsyncLineSequence)는 SSE 의 "빈 줄"(이벤트 경계)을 삼킨다 →
                    // 빈-줄 기반 SSEDecoder 가 이벤트를 방출하지 못해 무응답이 된다(실측 확인).
                    // 그래서 원시 바이트를 직접 '\n' 으로 분리해 빈 줄을 보존한다. (기존 파서 절대 변경 금지)
                    func process(_ rawLine: String) {
                        guard let event = decoder.push(rawLine) else { return }
                        if event.data == "[DONE]" { done = true; return }
                        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(event.data.utf8)) else { return }

                        if chunk.type == "content_block_start" {
                            // [Phase T1] tool_use 블록 시작 → id/name 캡처 + JSON 누적 버퍼 초기화(§3).
                            if chunk.content_block?.type == "tool_use" {
                                pendingToolID = chunk.content_block?.id
                                pendingToolName = chunk.content_block?.name
                                pendingToolJSON = ""
                            }
                        } else if chunk.type == "content_block_delta",
                           chunk.delta?.type == "text_delta",
                           let text = chunk.delta?.text {
                            continuation.yield(.delta(text))          // ← 기존 text_delta 경로(불변)
                        } else if chunk.type == "content_block_delta",
                                  chunk.delta?.type == "input_json_delta",
                                  let fragment = chunk.delta?.partial_json {
                            // [Phase T1] tool 인자 JSON 단편 누적(§3).
                            pendingToolJSON += fragment
                        } else if chunk.type == "content_block_stop" {
                            // [Phase T1] tool_use 블록 종료 → .toolUse 방출(§3).
                            if let id = pendingToolID, let name = pendingToolName {
                                continuation.yield(.toolUse(id: id, name: name, inputJSON: pendingToolJSON))
                                pendingToolID = nil
                                pendingToolName = nil
                                pendingToolJSON = ""
                            }
                        } else if chunk.type == "message_delta", let reason = chunk.delta?.stop_reason {
                            // stop_reason 은 message_delta 안에 온다(§7.4). 잘림 여부만 기록.
                            // [Phase T1] tool_use 도 정상 종료 사유 → done 처리(message_stop 누락 방어).
                            truncated = (reason == "max_tokens")
                            if reason == "tool_use" { done = true }
                        } else if chunk.type == "message_stop" {
                            done = true
                        }
                        // thinking_delta / 기타 이벤트는 무시(§7.4).
                    }

                    var buffer = [UInt8]()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if byte == 0x0A {                      // '\n' → 한 줄 완성(빈 줄도 그대로 전달)
                            process(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                            if done { break }
                        } else {
                            buffer.append(byte)
                        }
                    }
                    // 스트림이 개행 없이 끝났을 때 남은 한 줄 처리.
                    if !done, !buffer.isEmpty { process(String(decoding: buffer, as: UTF8.self)) }

                    continuation.yield(.done(truncated: truncated))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: (error as? ClientError) ?? Self.map(error))
                }
            }
            // 취소(§8.5): 스트림 소비자가 끊으면 URLSession 작업도 취소.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 공통 헬퍼

    private static func ensureOK(_ resp: URLResponse, _ data: Data?) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, data.flatMap(Self.errorMessage))
        }
    }

    /// 비2xx 본문에서 사람용 메시지만 추출(§7.6).
    /// `{"error":{"message":...}}`(Anthropic) 또는 `{"error":"..."}`(llama-server) JSON 을 시도하고,
    /// 디코드 실패 시 raw 문자열로 fallback. 빈 본문은 nil.
    private nonisolated static func errorMessage(from data: Data) -> String? {
        if data.isEmpty { return nil }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = envelope.message, !message.isEmpty {
            return message
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// 4xx/5xx 본문의 error 필드(객체형/문자열형 모두 대응).
    private nonisolated struct ErrorEnvelope: Decodable {
        let message: String?

        private enum CodingKeys: String, CodingKey { case error }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Anthropic: {"error":{"message":"...","type":"..."}}
            if let nested = try? container.decode(ErrorBody.self, forKey: .error) {
                message = nested.message
            // llama-server 일부 경로: {"error":"..."}
            } else if let plain = try? container.decode(String.self, forKey: .error) {
                message = plain
            } else {
                message = nil
            }
        }

        private struct ErrorBody: Decodable { let message: String? }
    }

    /// 저수준 에러를 ClientError 로 분류(§7.6).
    private static func map(_ error: Error) -> ClientError {
        if error is CancellationError { return .cancelled }
        let e = error as NSError
        if e.domain == NSURLErrorDomain {
            switch e.code {
            case NSURLErrorCancelled:
                return .cancelled
            case NSURLErrorTimedOut:
                return .timedOut
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed:
                // 로컬 네트워크 권한 거부도 iOS 에선 명확한 NSURLError 코드가 없어 보통 이 부류로 들어온다.
                // 그래서 .localNetworkDenied 를 별도로 반환하지 않고 .notConnected 로 통합한다(설명에 권한 안내 병기).
                return .notConnected
            case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
                return .badURL
            default:
                break
            }
        }
        return .http(-1, e.localizedDescription)
    }
}
