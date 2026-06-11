//
//  BriefingViewModel.swift
//  PocketLlama
//
//  [Phase W3 — 브리핑] 날씨→브리핑 스트리밍→캐시→폴백 상태머신(§5).
//  - 상태: idle → fetchingWeather → generating(스트리밍) → done / failed(reason).
//  - WeatherServiceProtocol + LLMChatClient 주입(세션 격리 — ChatViewModel 과 독립 클라이언트).
//  - tools 미포함 단방향 생성(§5). 당일 캐시(UserDefaults briefing.cache).
//  - 취소 가능(ChatViewModel §8.5 와 동일 Task 패턴).
//

import Foundation
import Observation

@Observable @MainActor
final class BriefingViewModel {

    /// 브리핑 상태머신(§5). failed 는 사유를 구분해 폴백 UI 를 분기한다.
    enum Phase: Equatable {
        case idle
        case fetchingWeather
        case generating
        case done
        case failed(Reason)

        enum Reason: Equatable {
            case weather   // 날씨 수집 실패(캐시 있으면 함께 노출)
            case llm       // LLM 생성 실패(날씨 원자료는 보존)
        }
    }

    private(set) var phase: Phase = .idle
    /// 현재 날씨 원자료(LLM 무관 칩 표시용 — 실패해도 보존).
    private(set) var weather: WeatherToday?
    /// 생성된(또는 캐시된) 브리핑 텍스트(스트리밍 중 누적).
    private(set) var briefingText: String = ""
    /// 캐시에서 복원했는지(새로고침 버튼 활성 판단·표시용).
    private(set) var loadedFromCache = false

    private var task: Task<Void, Never>?
    private let weatherService: WeatherServiceProtocol
    private let client: LLMChatClient
    private let store: AppSettingsStore

    private let maxTokens = 700   // 2~4문장 브리핑 — 짧게.

    init(weatherService: WeatherServiceProtocol, client: LLMChatClient, store: AppSettingsStore) {
        self.weatherService = weatherService
        self.client = client
        self.store = store
    }

    var isBusy: Bool {
        switch phase {
        case .fetchingWeather, .generating: return true
        default: return false
        }
    }

    // MARK: - 생성

    /// 브리핑 생성. force=false 면 당일 캐시가 있을 때 캐시만 로드한다(§5).
    func generate(force: Bool) {
        guard task == nil else { return }   // in-flight 1개

        // 당일 캐시 우선(!force).
        if !force, let cache = store.loadBriefingCache(), cache.date == Self.todayKey() {
            briefingText = cache.text
            loadedFromCache = true
            phase = .done
            return
        }

        loadedFromCache = false
        briefingText = ""
        phase = .fetchingWeather

        let city = store.selectedCity
        let streaming = store.useStreaming

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                // 1) 날씨 수집.
                let today = try await self.weatherService.today(for: city)
                try Task.checkCancellation()
                self.weather = today

                // 2) LLM 브리핑 생성(tools 미포함, §5).
                self.phase = .generating
                let user = ChatTurn(role: "user", content: Self.userPrompt(weather: today, store: self.store))
                let system = Self.systemPrompt(store: self.store)

                if streaming {
                    var acc = ""
                    for try await event in self.client.stream(messages: [user], system: system, maxTokens: self.maxTokens) {
                        switch event {
                        case .delta(let t):
                            acc += t
                            self.briefingText = acc
                        case .toolUse:
                            break   // 브리핑은 tools 미주입 → 방출 안 됨(exhaustive 충족).
                        case .done:
                            break
                        }
                    }
                    if acc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw ClientError.http(-1, "빈 응답")
                    }
                } else {
                    let completion = try await self.client.send(messages: [user], system: system, maxTokens: self.maxTokens)
                    try Task.checkCancellation()
                    self.briefingText = completion.text
                    if completion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw ClientError.http(-1, "빈 응답")
                    }
                }

                // 3) 캐시 저장 + 완료.
                try Task.checkCancellation()
                self.store.saveBriefingCache(BriefingCache(
                    date: Self.todayKey(),
                    text: self.briefingText,
                    weatherSnapshot: Self.weatherSnapshot(today)
                ))
                self.phase = .done
            } catch is CancellationError {
                // 취소: 부분 상태 유지하되 idle 로(시트 닫기/재시도 자유).
                self.phase = .idle
            } catch let error as ClientError where error == .cancelled {
                self.phase = .idle
            } catch {
                // 실패 분기: 날씨를 못 받았으면 .weather, 받았으면 .llm(원자료 보존).
                if self.weather == nil {
                    // 날씨 실패 — 캐시가 있으면 함께 노출(텍스트 채워 폴백 카드에 표시).
                    if let cache = self.store.loadBriefingCache() {
                        self.briefingText = cache.text
                        self.loadedFromCache = true
                    }
                    self.phase = .failed(.weather)
                } else {
                    self.phase = .failed(.llm)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - 프롬프트 조립(§5)

    /// system 프롬프트 — 아침 브리핑 비서 지침 + 프로필(비면 생략).
    private static func systemPrompt(store: AppSettingsStore) -> String {
        var s = "당신은 사용자의 아침을 챙기는 친근한 브리핑 비서입니다. "
        s += "주어진 날씨 정보를 바탕으로 2~4문장으로 짧게 브리핑하세요. "
        s += "우산·겉옷·자외선 등 실생활에 도움이 되는 구체적 조언을 한 가지 이상 포함하고, "
        s += "한국어로 따뜻하게 말하세요. 마크다운을 가볍게 활용해도 좋습니다."
        s += profileSuffix(store: store)
        return s
    }

    /// user 메시지 — 날짜·요일·도시·날씨 요약(코드북 설명 포함)·프로필 맥락.
    private static func userPrompt(weather w: WeatherToday, store: AppSettingsStore) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy년 M월 d일 EEEE"
        df.timeZone = TimeZone(identifier: "Asia/Seoul")
        let dateLine = df.string(from: Date())

        var lines: [String] = []
        lines.append("오늘은 \(dateLine)입니다.")
        lines.append("위치: \(w.cityName)")
        // 날씨 요약 — 코드북 한국어 설명을 함께 제공(모델이 숫자를 해석하기 쉽게).
        lines.append("현재 날씨: \(w.description)(WMO 코드 \(w.weatherCode))")
        lines.append("기온: 현재 \(Self.t(w.temperature)), 체감 \(Self.t(w.apparentTemperature)), 최고 \(Self.t(w.highTemperature)) / 최저 \(Self.t(w.lowTemperature))")
        lines.append("습도: \(w.humidity)%, 바람: \(Self.oneDecimal(w.windSpeed)) km/h, 현재 강수량: \(Self.oneDecimal(w.precipitation)) mm")
        if let pop = w.precipitationProbability {
            lines.append("오늘 강수확률: \(pop)%")
        }
        lines.append("\n위 정보를 바탕으로 오늘 아침 브리핑을 만들어 주세요.")
        return lines.joined(separator: "\n")
    }

    /// 프로필 주입(이름·소개 비면 생략, §4·§5 동일 규칙).
    private static func profileSuffix(store: AppSettingsStore) -> String {
        let name = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = store.userIntro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !intro.isEmpty else { return "" }
        var parts: [String] = []
        if !name.isEmpty { parts.append("이름: \(name)") }
        if !intro.isEmpty { parts.append("소개: \(intro)") }
        return "\n\n[사용자 정보] " + parts.joined(separator: ", ")
    }

    // MARK: - 표시 헬퍼

    /// 날씨 원자료 한 줄 요약(캐시·폴백 칩 보조 텍스트).
    static func weatherSnapshot(_ w: WeatherToday) -> String {
        var s = "\(w.cityName) \(w.description) \(t(w.temperature)) (최고 \(t(w.highTemperature))/최저 \(t(w.lowTemperature)))"
        if let pop = w.precipitationProbability { s += " 강수 \(pop)%" }
        return s
    }

    private static func t(_ v: Double) -> String { "\(Int(v.rounded()))℃" }
    private static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    /// 오늘 날짜 키(yyyy-MM-dd, Asia/Seoul) — 당일 캐시 판단용.
    static func todayKey() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "Asia/Seoul")
        return df.string(from: Date())
    }
}
