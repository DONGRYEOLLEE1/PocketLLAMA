//
//  E2EDriver.swift
//  PocketLlama
//
//  [Phase Q — E2E] DEBUG 전용 시뮬레이터 E2E 드라이버.
//  `xcrun simctl launch booted drlee.PocketLlama --e2e-...` 런치 아규먼트로 실제 UI 파이프라인
//  (전송→스트리밍→tool 루프, 알림 라우팅, 브리핑)을 구동한다. UI 탭 자동화(idb) 없이도
//  실동작 검증이 가능하도록 하되, 모든 경로가 #if DEBUG 라 릴리스 빌드에는 포함되지 않는다.
//
//  지원 아규먼트:
//    --e2e-send=<텍스트>       앱 진입 후 해당 텍스트를 실제 send() 경로로 전송
//    --e2e-briefing            콜드 스타트 알림 탭과 동일 경로(NotificationRouter)로 브리핑 시트 오픈
//    --e2e-notif=<초>          단축 테스트 알림 예약(포그라운드 배너 확인용)
//    --e2e-schedule-daily      매일 08:00 예약 후 pendingSummary 결과를 e2e.lastResult 에 기록
//    --e2e-clear-tavily        Tavily 키 제거(웹검색 비활성 강건성 테스트 — 같은 세션 한정)
//    --e2e-show-settings       설정 시트 오픈(스크린샷용)
//
//  검증 회수: 드라이버가 남기는 결과는 UserDefaults "e2e.lastResult" 로 읽는다
//  (`xcrun simctl spawn booted defaults read drlee.PocketLlama e2e.lastResult`).
//

#if DEBUG
import Foundation

enum E2EDriver {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// "--key=value" 형태에서 value 추출(없으면 nil).
    private static func value(for key: String) -> String? {
        guard let arg = args.first(where: { $0.hasPrefix(key + "=") }) else { return nil }
        return String(arg.dropFirst(key.count + 1))
    }

    private static func has(_ flag: String) -> Bool { args.contains(flag) }

    // MARK: - 개별 시나리오 질의

    static var sendText: String? { value(for: "--e2e-send") }
    static var briefingOnLaunch: Bool { has("--e2e-briefing") }
    static var notifAfterSeconds: TimeInterval? { value(for: "--e2e-notif").flatMap(TimeInterval.init) }
    static var scheduleDaily: Bool { has("--e2e-schedule-daily") }
    static var clearTavily: Bool { has("--e2e-clear-tavily") }
    static var showSettings: Bool { has("--e2e-show-settings") }

    static var isActive: Bool {
        sendText != nil || briefingOnLaunch || notifAfterSeconds != nil
            || scheduleDaily || clearTavily || showSettings
    }

    /// 검증 결과 기록(호스트에서 defaults read 로 회수).
    static func report(_ result: String) {
        UserDefaults.standard.set(result, forKey: "e2e.lastResult")
    }
}
#endif
