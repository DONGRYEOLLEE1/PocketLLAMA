# Swift 골격 코드 — PocketLlama

> `swift-builder`의 복붙 시작점. 계획서 §7~9 normative를 코드로 옮긴 골격이다.
> 그대로 컴파일되는 것을 목표로 하되, 파일 분리·이름·세부는 프로젝트에 맞게 조정한다.
> iOS 17+ 가정(`@Observable`, `URL.appending(path:)`). 더 낮은 타깃이면 대체 표기 주석 참조.

## 목차
1. ClientError (에러 분류)
2. ServerURL (base URL 정규화)
3. Wire 모델 (Codable 요청/응답/스트림)
4. SSEDecoder (버퍼 기반 SSE 파서)
5. LLMChatClient 프로토콜 + AnthropicChatClient
6. ChatState / ChatViewModel 스케치
7. AppSettingsStore

---

## 1. ClientError
```swift
import Foundation

enum ClientError: Error, LocalizedError, Equatable {
    case badURL
    case notConnected          // 연결 거부(서버 꺼짐/포트 불일치)
    case timedOut              // 타임아웃(35B 지연 포함)
    case localNetworkDenied    // iOS 로컬 네트워크 권한 거부
    case http(Int, String?)    // 4xx/5xx + 본문 메시지
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badURL:            return "서버 주소 형식이 올바르지 않습니다."
        case .notConnected:      return "서버에 연결할 수 없습니다. 맥북에서 서버가 0.0.0.0으로 떠 있는지, 같은 Wi-Fi인지 확인하세요."
        case .timedOut:          return "응답이 지연되고 있습니다. 모델이 큰 경우 첫 응답이 느릴 수 있습니다."
        case .localNetworkDenied:return "로컬 네트워크 접근 권한이 필요합니다. 설정에서 허용해 주세요."
        case .http(let c, let m):return "서버 오류(HTTP \(c))\(m.map { ": \($0)" } ?? "")"
        case .decoding(let d):   return "응답 해석 실패: \(d)"
        case .cancelled:         return "요청이 취소되었습니다."
        }
    }
}
```

## 2. ServerURL 정규화
```swift
enum ServerURL {
    /// 사용자가 입력한 base 문자열 → 정규화된 base URL.
    /// 끝 슬래시·실수로 들어온 경로(/v1/messages 등)를 제거하고 스킴을 보정한다.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        let strip = ["/v1/messages", "/v1/models", "/health", "/v1"]
        func trimTrailingSlash() { while s.hasSuffix("/") { s.removeLast() } }
        trimTrailingSlash()
        for suffix in strip where s.hasSuffix(suffix) { s.removeLast(suffix.count); break }
        trimTrailingSlash()
        return URL(string: s)
    }
}
```

## 3. Wire 모델
```swift
struct ChatTurn: Identifiable, Equatable {
    let id = UUID()
    let role: String   // "user" | "assistant"
    var content: String
}

struct MessagesRequest: Encodable {
    let model: String
    let max_tokens: Int          // ⚠️ Anthropic 필수
    var system: String?
    let messages: [Wire]
    var stream: Bool?
    struct Wire: Encodable { let role: String; let content: String }
}

struct MessagesResponse: Decodable {
    let content: [Block]
    let stop_reason: String?
    struct Block: Decodable { let type: String; let text: String? }
    /// type=="text" 블록만 합친다(thinking 블록 혼입 대비).
    var text: String { content.filter { $0.type == "text" }.compactMap(\.text).joined() }
}

struct ModelsResponse: Decodable {
    let data: [Model]
    struct Model: Decodable { let id: String }
}

/// SSE data: 한 줄의 JSON
struct StreamChunk: Decodable {
    let type: String
    let delta: Delta?
    struct Delta: Decodable { let type: String?; let text: String? }
}
```

## 4. SSEDecoder (계획서 §7.4)
```swift
struct SSEEvent { let event: String?; let data: String }

/// bytes.lines 로 들어온 '한 줄'을 push. 빈 줄에서 이벤트 1개 방출.
/// - 다중 data: 줄은 \n 으로 join (SSE 스펙)
/// - 끝의 \r 제거 (\r\n 대응)
/// - 주석(:) 무시
final class SSEDecoder {
    private var dataLines: [String] = []
    private var eventType: String?
    func push(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            defer { dataLines.removeAll(); eventType = nil }
            guard !dataLines.isEmpty else { return nil }
            return SSEEvent(event: eventType, data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
```

## 5. LLMChatClient + AnthropicChatClient
```swift
protocol LLMChatClient {
    func health() async throws -> Bool
    func models() async throws -> [String]
    func send(messages: [ChatTurn], system: String?, maxTokens: Int) async throws -> String
    func stream(messages: [ChatTurn], system: String?, maxTokens: Int) -> AsyncThrowingStream<String, Error>
}

struct AnthropicChatClient: LLMChatClient {
    let baseURL: URL
    var apiKey: String?          // 비어 있으면 무인증
    let model: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String? = nil, model: String = "local") {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true            // 계획서 §8.1
        cfg.timeoutIntervalForRequest = 180        // 35B TTFT 대비
        self.session = URLSession(configuration: cfg)
    }

    private func makeRequest(_ path: String, body: Data?) -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))   // iOS<16: appendingPathComponent
        req.httpMethod = body == nil ? "GET" : "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let k = apiKey, !k.isEmpty {            // §4.5: 헤더 형식은 게이트 실측 후 고정(x-api-key 가정)
            req.setValue(k, forHTTPHeaderField: "x-api-key")
        }
        req.httpBody = body
        return req
    }

    func health() async throws -> Bool {
        do {
            let (_, resp) = try await session.data(for: makeRequest("health", body: nil))
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { throw Self.map(error) }
    }

    func models() async throws -> [String] {
        do {
            let (data, resp) = try await session.data(for: makeRequest("v1/models", body: nil))
            try Self.ensureOK(resp, data)
            return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id)
        } catch let e as ClientError { throw e } catch { throw Self.map(error) }
    }

    func send(messages: [ChatTurn], system: String?, maxTokens: Int) async throws -> String {
        let reqBody = try JSONEncoder().encode(MessagesRequest(
            model: model, max_tokens: maxTokens, system: system,
            messages: messages.map { .init(role: $0.role, content: $0.content) }, stream: nil))
        do {
            let (data, resp) = try await session.data(for: makeRequest("v1/messages", body: reqBody))
            try Self.ensureOK(resp, data)
            return try JSONDecoder().decode(MessagesResponse.self, from: data).text
        } catch let e as ClientError { throw e } catch { throw Self.map(error) }
    }

    func stream(messages: [ChatTurn], system: String?, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let reqBody = try JSONEncoder().encode(MessagesRequest(
                        model: model, max_tokens: maxTokens, system: system,
                        messages: messages.map { .init(role: $0.role, content: $0.content) }, stream: true))
                    let (bytes, resp) = try await session.bytes(for: makeRequest("v1/messages", body: reqBody))
                    try Self.ensureOK(resp, nil)
                    let decoder = SSEDecoder()
                    for try await line in bytes.lines {
                        guard let ev = decoder.push(line) else { continue }
                        if ev.data == "[DONE]" { break }
                        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(ev.data.utf8)) else { continue }
                        if chunk.type == "content_block_delta", chunk.delta?.type == "text_delta", let t = chunk.delta?.text {
                            continuation.yield(t)
                        } else if chunk.type == "message_stop" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: (error as? ClientError) ?? Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }   // 취소(§8.5)
        }
    }

    private static func ensureOK(_ resp: URLResponse, _ data: Data?) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = data.flatMap { String(data: $0, encoding: .utf8) }
            throw ClientError.http(http.statusCode, msg)
        }
    }

    private static func map(_ error: Error) -> ClientError {
        if error is CancellationError { return .cancelled }
        let e = error as NSError
        if e.domain == NSURLErrorDomain {
            switch e.code {
            case NSURLErrorCancelled:            return .cancelled
            case NSURLErrorTimedOut:             return .timedOut
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost: return .notConnected
            default: break
            }
        }
        return .http(-1, e.localizedDescription)
    }
}
```

## 6. ChatState / ChatViewModel 스케치
```swift
enum ChatState: Equatable {
    case idle, connecting, ingesting, generating, cancelled
    case failed(String)
    var notice: String? {
        switch self {
        case .connecting: return "서버에 연결 중…"
        case .ingesting:  return "맥북이 프롬프트를 분석하고 있습니다 (대기 중)…"
        case .generating: return "답변 생성 중…"
        default:          return nil
        }
    }
}

@Observable @MainActor
final class ChatViewModel {
    var messages: [ChatTurn] = []
    var input: String = ""
    var state: ChatState = .idle
    private var task: Task<Void, Never>?
    private let client: LLMChatClient
    private let historyWindow = 12   // 멀티턴 슬라이딩 윈도우(§7.2)

    init(client: LLMChatClient) { self.client = client }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, task == nil else { return }   // 디바운스(§8.5)
        input = ""
        messages.append(ChatTurn(role: "user", content: text))
        var reply = ChatTurn(role: "assistant", content: "")
        messages.append(reply)
        state = .ingesting
        let window = Array(messages.dropLast().suffix(historyWindow))
        task = Task {
            defer { self.task = nil }
            do {
                for try await delta in client.stream(messages: window, system: nil, maxTokens: 1024) {
                    if state != .generating { state = .generating }
                    reply.content += delta
                    if let i = messages.lastIndex(where: { $0.id == reply.id }) { messages[i] = reply }
                }
                state = .idle
            } catch let e as ClientError {
                state = (e == .cancelled) ? .cancelled : .failed(e.errorDescription ?? "오류")
            } catch { state = .failed(error.localizedDescription) }
        }
    }

    func cancel() { task?.cancel() }   // URLSession 취소로 전파
}
```

## 7. AppSettingsStore
```swift
@Observable @MainActor
final class AppSettingsStore {
    private let d = UserDefaults.standard
    var baseURLString: String {
        didSet { d.set(baseURLString, forKey: "baseURL") }
    }
    var apiKey: String {
        didSet { d.set(apiKey, forKey: "apiKey") }
    }
    init() {
        baseURLString = d.string(forKey: "baseURL") ?? "http://192.168.0.10:8080"
        apiKey = d.string(forKey: "apiKey") ?? ""
    }
    var baseURL: URL? { ServerURL.normalize(baseURLString) }
}
```
