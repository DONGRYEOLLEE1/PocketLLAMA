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

    private func encodeBody(messages: [ChatTurn], system: String?, maxTokens: Int, stream: Bool?) throws -> Data {
        let request = MessagesRequest(
            model: model,
            max_tokens: maxTokens,           // ⚠️ 필수
            system: (system?.isEmpty == false) ? system : nil,
            messages: messages.map { .init(role: $0.role, content: $0.content) },
            stream: stream
        )
        return try JSONEncoder().encode(request)
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

    func send(messages: [ChatTurn], system: String?, maxTokens: Int) async throws -> ChatCompletion {
        do {
            let body = try encodeBody(messages: messages, system: system, maxTokens: maxTokens, stream: nil)
            let (data, resp) = try await session.data(for: makeRequest("v1/messages", body: body))
            try Self.ensureOK(resp, data)
            do {
                let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
                return ChatCompletion(text: decoded.text, truncated: decoded.wasTruncated)
            } catch {
                throw ClientError.decoding(String(describing: error))
            }
        } catch let e as ClientError {
            throw e
        } catch {
            throw Self.map(error)
        }
    }

    func stream(messages: [ChatTurn], system: String?, maxTokens: Int) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try encodeBody(messages: messages, system: system, maxTokens: maxTokens, stream: true)
                    let (bytes, resp) = try await session.bytes(for: makeRequest("v1/messages", body: body))
                    try Self.ensureOK(resp, nil)

                    let decoder = SSEDecoder()
                    var truncated = false
                    for try await rawLine in bytes.lines {
                        try Task.checkCancellation()
                        guard let event = decoder.push(rawLine) else { continue }
                        if event.data == "[DONE]" { break }
                        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(event.data.utf8)) else { continue }

                        if chunk.type == "content_block_delta",
                           chunk.delta?.type == "text_delta",
                           let text = chunk.delta?.text {
                            continuation.yield(.delta(text))
                        } else if chunk.type == "message_delta", let reason = chunk.delta?.stop_reason {
                            // stop_reason 은 message_delta 안에 온다(§7.4). 잘림 여부만 기록하고 종료는 message_stop 에서.
                            truncated = (reason == "max_tokens")
                        } else if chunk.type == "message_stop" {
                            break
                        }
                        // thinking_delta / 기타 이벤트는 무시(§7.4).
                    }
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
