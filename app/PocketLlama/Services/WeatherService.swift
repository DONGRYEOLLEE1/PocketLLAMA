//
//  WeatherService.swift
//  PocketLlama
//
//  [Phase W1 — 날씨] WeatherServiceProtocol + Open-Meteo 구현체.
//  계획서 §6: 1콜로 current+daily 를 받아 WeatherToday 로 변환한다.
//  - 프로토콜 추상화로 추후 기상청 등 소스 스위칭(§0 ⑤-B).
//  - 에러는 기존 ClientError 로 분류(§7.6 재사용 — 새 에러 타입 만들지 않음).
//

import Foundation

/// 날씨 소스 추상화. 구현체 교체로 소스(Open-Meteo↔기상청)를 바꾼다(§6).
protocol WeatherServiceProtocol: Sendable {
    func today(for city: KoreanCity) async throws -> WeatherToday
}

/// Open-Meteo 구현체(무키·https — ATS 통과). 계획서 §6 의 쿼리 그대로.
struct OpenMeteoWeatherService: WeatherServiceProtocol {
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 15      // §W1 — 날씨는 15s 타임아웃
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
    }

    func today(for city: KoreanCity) async throws -> WeatherToday {
        let request = try makeRequest(for: city)
        do {
            let (data, resp) = try await session.data(for: request)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)
                throw ClientError.http(http.statusCode, body)
            }
            do {
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                return WeatherToday(from: decoded, cityName: city.displayName)
            } catch {
                throw ClientError.decoding(String(describing: error))
            }
        } catch let e as ClientError {
            throw e
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - 요청 조립(§6 쿼리 고정)

    private func makeRequest(for city: KoreanCity) throws -> URLRequest {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "current",
                         value: "temperature_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "daily",
                         value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code"),
            URLQueryItem(name: "timezone", value: "Asia/Seoul"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = components?.url else { throw ClientError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return req
    }

    /// 저수준 에러를 ClientError 로 분류(AnthropicChatClient.map 과 동일 정책, §7.6).
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
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet:
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
