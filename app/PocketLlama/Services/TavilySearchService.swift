//
//  TavilySearchService.swift
//  PocketLlama
//
//  [Phase T2 — 웹검색(수술 B2)] Tavily Search API 클라이언트 + tool_result 포맷터(§4).
//  - POST https://api.tavily.com/search · body {api_key, query, max_results:5, search_depth:"basic"}.
//  - 결과 results[{title,url,content}] → "[n] 제목 — 발췌(≤400자) (URL)" 번호 목록(총 ≤3,000자).
//  - 키는 호출 시 주입(AppSettingsStore.tavilyAPIKey). 타임아웃 15s. 에러는 ClientError 분류(§7.6 재사용).
//

import Foundation

/// Tavily 검색 결과 1건(앱 내부용).
struct SearchResult: Equatable {
    let title: String
    let url: String
    let snippet: String
}

/// 웹검색 서비스 추상화(추후 다른 검색 소스 스위칭 여지).
protocol SearchServiceProtocol: Sendable {
    /// query 로 웹 검색. apiKey 는 호출 시 주입. 실패 시 ClientError throw.
    func search(query: String, apiKey: String) async throws -> [SearchResult]
}

struct TavilySearchService: SearchServiceProtocol {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.tavily.com/search")!

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15      // §T2 — 검색 15s
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
    }

    func search(query: String, apiKey: String) async throws -> [SearchResult] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.http(-1, "Tavily API 키가 없습니다")
        }
        let request = try makeRequest(query: query, apiKey: apiKey)
        do {
            let (data, resp) = try await session.data(for: request)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8))
            }
            do {
                let decoded = try JSONDecoder().decode(TavilyResponse.self, from: data)
                return decoded.results.map {
                    SearchResult(title: $0.title, url: $0.url, snippet: $0.content)
                }
            } catch {
                throw ClientError.decoding(String(describing: error))
            }
        } catch let e as ClientError {
            throw e
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - tool_result 포맷터(§4 — 번호 목록·발췌 ≤400자·총 ≤3,000자)

    /// 검색 결과를 모델 회신용 텍스트로 포맷. 빈 결과는 안내 문구.
    static func formatResults(_ results: [SearchResult]) -> String {
        guard !results.isEmpty else { return "검색 결과가 없습니다." }
        var out = ""
        for (i, r) in results.prefix(5).enumerated() {
            let snippet = clip(r.snippet, max: 400)
            let title = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = "[\(i + 1)] \(title) — \(snippet) (\(r.url))\n"
            // 총 길이 3,000자 한도(다음 줄 추가 시 초과면 중단).
            if out.count + line.count > 3000 { break }
            out += line
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "검색 결과가 없습니다." : trimmed
    }

    /// 발췌를 max 자로 자르고 말줄임(공백 정규화).
    private static func clip(_ s: String, max: Int) -> String {
        let normalized = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > max else { return normalized }
        return String(normalized.prefix(max)) + "…"
    }

    // MARK: - 요청 조립

    private func makeRequest(query: String, apiKey: String) throws -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = TavilyRequest(
            api_key: apiKey,
            query: query,
            max_results: 5,
            search_depth: "basic"
        )
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    // MARK: - DTO

    private struct TavilyRequest: Encodable {
        let api_key: String
        let query: String
        let max_results: Int
        let search_depth: String
    }

    private struct TavilyResponse: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let title: String
            let url: String
            let content: String
        }
    }

    /// 저수준 에러를 ClientError 로 분류(WeatherService.map 과 동일 정책).
    private static func map(_ error: Error) -> ClientError {
        if error is CancellationError { return .cancelled }
        let e = error as NSError
        if e.domain == NSURLErrorDomain {
            switch e.code {
            case NSURLErrorCancelled:        return .cancelled
            case NSURLErrorTimedOut:         return .timedOut
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
