//
//  NotificationRouter.swift
//  PocketLlama
//
//  [Phase W3 — 알림 라우팅(수술 M1)] 알림 탭 → 브리핑 시트 라우팅 신호(§5).
//  AppDelegate(UNUserNotificationCenterDelegate)의 didReceive 가 pendingBriefing 을 true 로 세팅하고,
//  RootView 가 .onChange 로 감지해 BriefingView 시트를 띄운다.
//
//  @Observable 싱글톤 — 앱 델리게이트(비 SwiftUI 컨텍스트)와 RootView 가 같은 인스턴스를 공유해야
//  하므로 .shared 로 둔다. 메인 액터 격리(알림 콜백·UI 갱신 모두 메인).
//

import Foundation
import Observation

@Observable @MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()
    private init() {}

    /// 알림 탭으로 브리핑을 열어야 하면 true. RootView 가 시트 표시 후 false 로 되돌린다.
    var pendingBriefing = false
}
