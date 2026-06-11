//
//  EmbeddingClient.swift
//  PocketLlama
//
//  [v0.2 M3] 임베딩 클라이언트 — POST http://<채팅서버 host>:8081/v1/embeddings (M0 게이트 계약).
//  - 호스트: 채팅 baseURL 의 host 를 재사용 + 포트 8081 고정(scheme 유지). 같은 맥에서 이중 기동(EMBED=1).
//  - 계약(M0 실측): body {"input": "<text>"} → data[0].embedding: [Float](1024차원).
//  - 쿼리측: instruct 프리픽스(검색 의도 명시) / 저장(문서)측: 원문(M-D13).
//  - 타임아웃 10s. 실패는 throw — 호출측(ChatViewModel/MemoryExtractor)이 LIKE 폴백 또는 NULL 저장.
//

import Foundation

/// 임베딩 서비스 추상화(테스트·교체 여지).
protocol EmbeddingServiceProtocol: Sendable {
    /// 쿼리(검색 의도) 임베딩 — instruct 프리픽스 부착.
    func embedQuery(_ text: String) async throws -> [Float]
    /// 문서(저장 대상) 임베딩 — 원문 그대로.
    func embedDocument(_ text: String) async throws -> [Float]
}

struct EmbeddingClient: EmbeddingServiceProtocol {
    let endpoint: URL
    private let session: URLSession

    /// 쿼리측 instruct 프리픽스(M0/M-D13 — Qwen3-Embedding 권장 형식).
    private static let queryInstruction =
        "Instruct: Given a query, retrieve relevant personal memories\nQuery: "

    /// 채팅 baseURL 의 host 를 재사용해 포트만 8081 로 바꾼 임베딩 엔드포인트를 만든다.
    /// host 추출 불가(드묾)면 nil → 호출측이 임베딩 비활성(LIKE 폴백)으로 동작.
    init?(chatBaseURL: URL) {
        guard var comps = URLComponents(url: chatBaseURL, resolvingAgainstBaseURL: false),
              comps.host != nil else { return nil }
        comps.port = 8081
        comps.path = "/v1/embeddings"
        guard let url = comps.url else { return nil }
        self.endpoint = url

        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false        // 회상 지연 금지 — 연결 대기 없이 빠르게 실패
        cfg.timeoutIntervalForRequest = 10      // M-D: 짧게(send 0.5s 지연 방지 — 호출측이 더 짧게 race 가능)
        cfg.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: cfg)
    }

    func embedQuery(_ text: String) async throws -> [Float] {
        try await embed(Self.queryInstruction + text)
    }

    func embedDocument(_ text: String) async throws -> [Float] {
        try await embed(text)
    }

    // MARK: - 요청

    private func embed(_ input: String) async throws -> [Float] {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(EmbeddingRequest(input: input))

        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8))
            }
            let decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
            guard let vector = decoded.data.first?.embedding, !vector.isEmpty else {
                throw ClientError.decoding("임베딩 응답에 embedding 이 없습니다")
            }
            return vector
        } catch let e as ClientError {
            throw e
        } catch let e as DecodingError {
            throw ClientError.decoding(String(describing: e))
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - DTO (M0 계약: {"input": …} → {"data":[{"embedding":[…]}]})

    private struct EmbeddingRequest: Encodable {
        let input: String
    }

    private struct EmbeddingResponse: Decodable {
        let data: [Item]
        struct Item: Decodable { let embedding: [Float] }
    }

    /// 저수준 에러 → ClientError(채팅 클라이언트와 동일 정책).
    private static func map(_ error: Error) -> ClientError {
        if error is CancellationError { return .cancelled }
        let e = error as NSError
        if e.domain == NSURLErrorDomain {
            switch e.code {
            case NSURLErrorCancelled: return .cancelled
            case NSURLErrorTimedOut: return .timedOut
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet:
                return .notConnected
            case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
                return .badURL
            default: break
            }
        }
        return .http(-1, e.localizedDescription)
    }
}
