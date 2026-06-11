//
//  NotificationManager.swift
//  PocketLlama
//
//  [Phase W2 — 알림] 매일 아침 브리핑 로컬 알림(§0·§5 M1).
//  - UNCalendarNotificationTrigger(dateMatching: 시:분, repeats: true) — 시스템 스케줄러가
//    백그라운드 실행 없이 정시 발화한다(D3). 백그라운드 fetch 불요.
//  - identifier 고정("morning-briefing") → 시간/도시 변경 시 같은 id 로 덮어써 중복 예약 차단.
//  - 권한 요청·예약·취소·pending 조회(검증용)·(DEBUG)단축 트리거.
//
//  설계 판단: @MainActor 싱글톤. UNUserNotificationCenter 호출은 메인에서 해도 비용이 작고,
//  SettingsView/AppDelegate 등 메인 컨텍스트에서만 부른다. 주입 대신 .shared 로 단순화하되
//  테스트성 호출은 인스턴스 메서드라 mock 교체 여지를 남긴다.
//
//  플랫폼: UserNotifications 는 iOS 전용 경로를 쓰되, build-check macOS 폴백 호환을 위해
//  canImport(UIKit) 로 가드한다(폴백 컴파일 시 no-op 스텁).
//

import Foundation

#if canImport(UIKit)
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// 매일 반복 알림 식별자(고정 — 재예약 시 덮어쓰기).
    static let dailyID = "morning-briefing"
    /// DEBUG 단축 트리거 식별자.
    static let testID = "morning-briefing-test"

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - 권한

    /// 알림 권한 요청. 사용자가 허용했는지 반환(이미 결정됐으면 현재 상태 반영).
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 현재 권한 상태(설정 UI 안내용).
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - 매일 예약

    /// 매일 hour:minute 에 반복 발화하도록 예약(고정 id 로 덮어쓰기 = 재예약).
    func scheduleDaily(hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🦙 아침 브리핑이 준비됐어요"
        content.body = "탭하면 지금 날씨로 브리핑을 만들어 드려요"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        // dateMatching + repeats:true → 매일 같은 시:분에 발화(시스템 스케줄러).
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: Self.dailyID, content: content, trigger: trigger)
        // 같은 id 의 기존 예약은 add 가 자동으로 대체(중복 차단).
        center.add(request)
    }

    /// 매일 예약 취소.
    func cancelDaily() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyID])
    }

    // MARK: - 검증용 조회

    /// 매일 예약이 존재하면 (hour, minute) 반환. 없으면 nil(QA/검증·재예약 판단용).
    func pendingSummary() async -> (hour: Int, minute: Int)? {
        let requests = await center.pendingNotificationRequests()
        guard let req = requests.first(where: { $0.identifier == Self.dailyID }),
              let trigger = req.trigger as? UNCalendarNotificationTrigger else {
            return nil
        }
        let c = trigger.dateComponents
        guard let h = c.hour, let m = c.minute else { return nil }
        return (h, m)
    }

    // MARK: - DEBUG 단축 트리거(시뮬레이터 발화 확인용 — 정시 실발화는 실기기 체크리스트)

    #if DEBUG
    /// seconds 후 1회 발화(배너/라우팅 스모크). 매일 예약과 별도 id.
    func scheduleTest(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "🦙 아침 브리핑이 준비됐어요"
        content.body = "탭하면 지금 날씨로 브리핑을 만들어 드려요"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: Self.testID, content: content, trigger: trigger)
        center.add(request)
    }
    #endif
}

#else

// macOS build-check 폴백용 no-op 스텁(UserNotifications 의 iOS 경로 미사용).
// 실제 앱 타깃은 iOS 이므로 런타임에는 위 구현이 쓰인다.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    static let dailyID = "morning-briefing"
    static let testID = "morning-briefing-test"
    private init() {}

    @discardableResult
    func requestAuthorization() async -> Bool { false }
    func scheduleDaily(hour: Int, minute: Int) {}
    func cancelDaily() {}
    func pendingSummary() async -> (hour: Int, minute: Int)? { nil }
    #if DEBUG
    func scheduleTest(after seconds: TimeInterval) {}
    #endif
}

#endif
