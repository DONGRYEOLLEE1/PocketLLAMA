//
//  AppSettingsStore.swift
//  PocketLlama
//
//  설정(base URL + 선택적 API Key)과 최근 대화 1세션을 UserDefaults 에 저장/복원한다.
//  - 설정: base URL 만 저장(클라이언트가 경로 조립, §7.1)
//  - 기록: 최근 대화 1세션(§ Phase 8) — 껐다 켜도 이어서 사용
//

import Foundation
import Observation

@Observable @MainActor
final class AppSettingsStore {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let baseURL = "baseURL"
        static let apiKey = "apiKey"          // [P0] 레거시 UserDefaults 키 — 마이그레이션 후 삭제
        static let session = "recentSession"
        static let useStreaming = "useStreaming"
        // [Phase W2] 브리핑·프로필 설정(비밀 아님 → UserDefaults).
        static let briefingEnabled = "briefingEnabled"
        static let briefingHour = "briefingHour"
        static let briefingMinute = "briefingMinute"
        static let cityID = "cityID"
        static let userName = "userName"
        static let userIntro = "userIntro"
        // [Phase W3] 당일 브리핑 캐시(yyyy-MM-dd + 텍스트 + 날씨 요약).
        static let briefingCache = "briefing.cache"
    }

    /// 사용자가 입력한 base URL 문자열(정규화 전 원문 보관 — 편집 편의).
    var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Key.baseURL) }
    }

    /// 선택적 서버 API Key(무인증이면 빈 문자열).
    /// [Phase P0] 저장소를 Keychain 으로 전환 — 외부 인터페이스(String getter/setter)는 그대로 유지해
    /// 기존 호출부(SettingsView·ChatView·RootView)가 무수정 컴파일된다.
    /// @Observable 의 변경 추적을 위해 내부 백킹 프로퍼티(_apiKey)를 두고 didSet 에서 Keychain 에 반영한다.
    var apiKey: String {
        didSet { KeychainStore.set(apiKey, for: .serverAPIKey) }
    }

    /// Tavily 웹검색 API 키(Keychain 백킹).
    /// [Phase P0] 비어 있으면 앱이 웹검색 tool 을 비활성화한다(§0·§4 웹검색 가능 조건).
    var tavilyAPIKey: String {
        didSet { KeychainStore.set(tavilyAPIKey, for: .tavilyAPIKey) }
    }

    /// 스트리밍 응답 사용 여부(기본 true=스트림 경로 Phase 7 / false=비스트림 경로 Phase 6).
    var useStreaming: Bool {
        didSet { defaults.set(useStreaming, forKey: Key.useStreaming) }
    }

    // MARK: - [Phase W2] 아침 브리핑 설정(비밀 아님 → UserDefaults, didSet 즉시 저장)

    /// 매일 아침 브리핑 알림 켜짐 여부(기본 false — 사용자가 명시적으로 켤 때만 예약).
    var briefingEnabled: Bool {
        didSet { defaults.set(briefingEnabled, forKey: Key.briefingEnabled) }
    }
    /// 브리핑 알림 시(0~23, 기본 8).
    var briefingHour: Int {
        didSet { defaults.set(briefingHour, forKey: Key.briefingHour) }
    }
    /// 브리핑 알림 분(0~59, 기본 0).
    var briefingMinute: Int {
        didSet { defaults.set(briefingMinute, forKey: Key.briefingMinute) }
    }
    /// 날씨/브리핑 대상 도시 id(KoreanCity.rawValue, 기본 서울).
    var cityID: String {
        didSet { defaults.set(cityID, forKey: Key.cityID) }
    }

    // MARK: - [Phase W2] 프로필(system 주입용 — 비면 생략)

    /// 사용자 이름(기본 빈 문자열 — 비면 system 에 주입 안 함).
    var userName: String {
        didSet { defaults.set(userName, forKey: Key.userName) }
    }
    /// 한 줄 자기소개(기본 빈 문자열 — 비면 system 에 주입 안 함).
    var userIntro: String {
        didSet { defaults.set(userIntro, forKey: Key.userIntro) }
    }

    init() {
        baseURLString = defaults.string(forKey: Key.baseURL) ?? ""

        // [Phase P0] 서버 apiKey: UserDefaults → Keychain 1회 마이그레이션.
        // 레거시 UserDefaults 값이 있으면 Keychain 에 옮기고 평문 키를 삭제한다.
        if let legacy = defaults.string(forKey: Key.apiKey), !legacy.isEmpty {
            if KeychainStore.get(.serverAPIKey) == nil {
                KeychainStore.set(legacy, for: .serverAPIKey)
            }
            defaults.removeObject(forKey: Key.apiKey)
        }
        // didSet 재진입(Keychain 재기록)을 피하려고 백킹 직접 대입은 불가하므로,
        // 초기화 순서상 apiKey 대입 시점엔 위 마이그레이션이 끝나 Keychain 이 SSOT 다.
        apiKey = KeychainStore.get(.serverAPIKey) ?? ""

        // [Phase P0] Tavily 키: Keychain 이 비어 있고 Secrets 시드가 있으면 1회 주입(Secrets 는 불변).
        if let existing = KeychainStore.get(.tavilyAPIKey), !existing.isEmpty {
            tavilyAPIKey = existing
        } else if !Secrets.tavilyAPIKey.isEmpty {
            KeychainStore.set(Secrets.tavilyAPIKey, for: .tavilyAPIKey)
            tavilyAPIKey = Secrets.tavilyAPIKey
        } else {
            tavilyAPIKey = ""
        }

        // 키가 없으면 기본 true(object(forKey:) 로 미설정과 false 를 구분).
        useStreaming = (defaults.object(forKey: Key.useStreaming) as? Bool) ?? true

        // [Phase W2] 브리핑·프로필 설정 로드(미설정 시 기본값).
        briefingEnabled = (defaults.object(forKey: Key.briefingEnabled) as? Bool) ?? false
        briefingHour = (defaults.object(forKey: Key.briefingHour) as? Int) ?? 8
        briefingMinute = (defaults.object(forKey: Key.briefingMinute) as? Int) ?? 0
        cityID = defaults.string(forKey: Key.cityID) ?? KoreanCity.seoul.rawValue
        userName = defaults.string(forKey: Key.userName) ?? ""
        userIntro = defaults.string(forKey: Key.userIntro) ?? ""
    }

    // MARK: - [Phase W2] 도시 매핑 헬퍼

    /// 저장된 cityID → KoreanCity(유효하지 않으면 서울 폴백).
    var selectedCity: KoreanCity {
        KoreanCity(rawValue: cityID) ?? .seoul
    }

    /// 웹검색 tool 사용 가능 여부(§4 — Tavily 키 보유 시에만 tools 주입).
    var isWebSearchEnabled: Bool {
        !tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 정규화된 base URL(없으면 nil → 설정 미완료로 간주).
    var baseURL: URL? { ServerURL.normalize(baseURLString) }

    /// 설정 완료 여부(RootView 분기 기준).
    var isConfigured: Bool { baseURL != nil }

    // MARK: - 최근 대화 1세션 저장/복원(Phase 8)

    func saveSession(_ turns: [ChatTurn]) {
        guard let data = try? JSONEncoder().encode(turns) else { return }
        defaults.set(data, forKey: Key.session)
    }

    func loadSession() -> [ChatTurn] {
        guard let data = defaults.data(forKey: Key.session),
              let turns = try? JSONDecoder().decode([ChatTurn].self, from: data) else { return [] }
        return turns
    }

    func clearSession() {
        defaults.removeObject(forKey: Key.session)
    }

    // MARK: - [Phase W3] 당일 브리핑 캐시(§5 — date·text·weatherSnapshot)

    func saveBriefingCache(_ cache: BriefingCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Key.briefingCache)
    }

    func loadBriefingCache() -> BriefingCache? {
        guard let data = defaults.data(forKey: Key.briefingCache),
              let cache = try? JSONDecoder().decode(BriefingCache.self, from: data) else { return nil }
        return cache
    }
}

/// [Phase W3] 브리핑 당일 캐시(§5). date 는 yyyy-MM-dd(로컬), text 는 LLM 브리핑,
/// weatherSnapshot 은 날씨 원자료 요약(LLM 무관 칩 표시 보존용).
struct BriefingCache: Codable, Equatable {
    let date: String          // yyyy-MM-dd (Asia/Seoul 로컬 날짜)
    let text: String          // 생성된 브리핑 마크다운
    let weatherSnapshot: String // 날씨 요약 한 줄(칩/폴백 표시용)
}
