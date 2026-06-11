//
//  Weather.swift
//  PocketLlama
//
//  [Phase W1 — 날씨] Open-Meteo 응답 DTO + WMO weather_code 코드북 + 도시 프리셋.
//  계획서 §6: 1콜로 current+daily 를 받아 앱 내부용 WeatherToday 로 변환한다.
//  - DTO 는 실측 응답 shape 그대로(snake_case CodingKeys).
//  - 위치는 지오코딩 대신 도시 프리셋 고정 좌표(§0 — 한국어 지오코딩 신뢰 불가).
//

import Foundation

// MARK: - Open-Meteo 응답 DTO (실측 shape, snake_case 그대로)

/// `https://api.open-meteo.com/v1/forecast` 응답(현재 + 당일 daily, §6).
struct OpenMeteoResponse: Decodable {
    let current: Current
    let daily: Daily

    struct Current: Decodable {
        let time: String
        let temperature_2m: Double
        let apparent_temperature: Double
        let precipitation: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let relative_humidity_2m: Int
    }

    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int?]   // 일부 시점 null 가능 → 옵셔널 방어
        let weather_code: [Int]
    }
}

// MARK: - 앱 내부용 변환 모델

/// 화면/브리핑에서 쓰는 정규화된 오늘 날씨(코드북 변환 완료).
struct WeatherToday: Equatable {
    let cityName: String          // 도시 표시명(한국어)
    let observedAt: String        // 관측 시각(current.time, 원문)
    let temperature: Double       // 현재 기온(℃)
    let apparentTemperature: Double // 체감 온도(℃)
    let humidity: Int             // 상대 습도(%)
    let windSpeed: Double         // 풍속(m/s 또는 km/h — Open-Meteo 기본 단위)
    let precipitation: Double     // 현재 강수량(mm)
    let highTemperature: Double   // 오늘 최고(℃)
    let lowTemperature: Double    // 오늘 최저(℃)
    let precipitationProbability: Int? // 오늘 강수 확률(%) — 없을 수 있음
    let weatherCode: Int          // 원본 WMO 코드
    let description: String       // 한국어 날씨 설명(코드북)
    let sfSymbol: String          // SF Symbol 이름(코드북)

    /// Open-Meteo 응답 + 도시명 → WeatherToday.
    /// daily 배열의 0번(오늘, forecast_days=1)을 사용. 배열이 비면 current 값으로 폴백.
    init(from response: OpenMeteoResponse, cityName: String) {
        let c = response.current
        let d = response.daily
        let codebook = WeatherCodebook.entry(for: c.weather_code)

        self.cityName = cityName
        self.observedAt = c.time
        self.temperature = c.temperature_2m
        self.apparentTemperature = c.apparent_temperature
        self.humidity = c.relative_humidity_2m
        self.windSpeed = c.wind_speed_10m
        self.precipitation = c.precipitation
        self.highTemperature = d.temperature_2m_max.first ?? c.temperature_2m
        self.lowTemperature = d.temperature_2m_min.first ?? c.temperature_2m
        self.precipitationProbability = d.precipitation_probability_max.first ?? nil
        self.weatherCode = c.weather_code
        self.description = codebook.description
        self.sfSymbol = codebook.sfSymbol
    }
}

// MARK: - WMO weather_code 코드북 (§6)

/// WMO weather_code → (한국어 설명, SF Symbol). 구간 매핑(§6).
enum WeatherCodebook {
    struct Entry: Equatable {
        let description: String
        let sfSymbol: String
    }

    /// 코드 구간 매핑. 미지정 코드는 보수적으로 "흐림"으로 폴백.
    static func entry(for code: Int) -> Entry {
        switch code {
        case 0:
            return Entry(description: "맑음", sfSymbol: "sun.max")
        case 1, 2, 3:
            // 1 대체로 맑음 / 2 부분적 흐림 / 3 흐림 — 구름 강도 차이를 심볼로 표현.
            return Entry(description: code == 3 ? "흐림" : "구름조금", sfSymbol: code == 3 ? "cloud" : "cloud.sun")
        case 45, 48:
            return Entry(description: "안개", sfSymbol: "cloud.fog")
        case 51, 53, 55, 56, 57:
            return Entry(description: "이슬비", sfSymbol: "cloud.drizzle")
        case 61, 63, 65, 66, 67:
            return Entry(description: "비", sfSymbol: "cloud.rain")
        case 71, 73, 75, 77:
            return Entry(description: "눈", sfSymbol: "cloud.snow")
        case 80, 81, 82:
            return Entry(description: "소나기", sfSymbol: "cloud.heavyrain")
        case 85, 86:
            return Entry(description: "소낙눈", sfSymbol: "cloud.snow")
        case 95, 96, 99:
            return Entry(description: "뇌우", sfSymbol: "cloud.bolt.rain")
        default:
            return Entry(description: "흐림", sfSymbol: "cloud")
        }
    }
}

// MARK: - 도시 프리셋 (§0 — 고정 좌표, 기본 서울)

/// 주요 한국 도시 프리셋. 지오코딩 대신 고정 좌표를 쓴다(§0).
enum KoreanCity: String, Codable, CaseIterable, Identifiable {
    case seoul
    case busan
    case incheon
    case daegu
    case daejeon
    case gwangju
    case ulsan
    case suwon
    case jeju

    var id: String { rawValue }

    /// 한국어 표시명.
    var displayName: String {
        switch self {
        case .seoul:   return "서울"
        case .busan:   return "부산"
        case .incheon: return "인천"
        case .daegu:   return "대구"
        case .daejeon: return "대전"
        case .gwangju: return "광주"
        case .ulsan:   return "울산"
        case .suwon:   return "수원"
        case .jeju:    return "제주"
        }
    }

    var latitude: Double {
        switch self {
        case .seoul:   return 37.5665
        case .busan:   return 35.1796
        case .incheon: return 37.4563
        case .daegu:   return 35.8714
        case .daejeon: return 36.3504
        case .gwangju: return 35.1595
        case .ulsan:   return 35.5384
        case .suwon:   return 37.2636
        case .jeju:    return 33.4996
        }
    }

    var longitude: Double {
        switch self {
        case .seoul:   return 126.9780
        case .busan:   return 129.0756
        case .incheon: return 126.7052
        case .daegu:   return 128.6014
        case .daejeon: return 127.3845
        case .gwangju: return 126.8526
        case .ulsan:   return 129.3114
        case .suwon:   return 127.0286
        case .jeju:    return 126.5312
        }
    }
}
