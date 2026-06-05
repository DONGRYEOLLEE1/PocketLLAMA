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
        static let apiKey = "apiKey"
        static let session = "recentSession"
        static let useStreaming = "useStreaming"
    }

    /// 사용자가 입력한 base URL 문자열(정규화 전 원문 보관 — 편집 편의).
    var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Key.baseURL) }
    }

    /// 선택적 API Key(무인증이면 빈 문자열).
    var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Key.apiKey) }
    }

    /// 스트리밍 응답 사용 여부(기본 true=스트림 경로 Phase 7 / false=비스트림 경로 Phase 6).
    var useStreaming: Bool {
        didSet { defaults.set(useStreaming, forKey: Key.useStreaming) }
    }

    init() {
        baseURLString = defaults.string(forKey: Key.baseURL) ?? ""
        apiKey = defaults.string(forKey: Key.apiKey) ?? ""
        // 키가 없으면 기본 true(object(forKey:) 로 미설정과 false 를 구분).
        useStreaming = (defaults.object(forKey: Key.useStreaming) as? Bool) ?? true
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
}
