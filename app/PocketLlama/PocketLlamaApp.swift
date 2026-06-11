//
//  PocketLlamaApp.swift
//  PocketLlama
//
//  맥북 llama-server(Anthropic 호환 /v1/messages)에 접속해 채팅하는 iOS 앱.
//
//  [Phase W3 — 수술 M1] AppDelegate(UNUserNotificationCenterDelegate)로 알림 탭을 받아
//  NotificationRouter.pendingBriefing 을 켠다 → RootView 가 브리핑 시트로 라우팅.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
import UserNotifications

/// 알림 델리게이트. 탭(didReceive)·foreground 발화(willPresent)를 처리한다.
/// 콜드 스타트(앱 종료 상태에서 알림 탭)도 시스템이 launchOptions 대신 didReceive 를
/// 앱 기동 직후 호출하므로(델리게이트가 didFinishLaunching 에서 배선되면) 별도 launchOptions
/// 파싱 없이 didReceive 한 곳에서 처리된다.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 델리게이트 배선은 여기서. 이후 콜드 스타트 탭은 시스템이 didReceive 로 전달한다.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 알림 탭(앱 백그라운드/종료 상태 포함) → 브리핑 라우팅 신호.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NotificationRouter.shared.pendingBriefing = true
        }
        completionHandler()
    }

    /// 앱 foreground 중 발화 → 배너·소리로 표시(무시되지 않게).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
#endif

@main
struct PocketLlamaApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        #if DEBUG
        // [Phase Q — E2E] 콜드 스타트 알림 탭과 동일한 라우팅 경로를 런치 아규먼트로 재현.
        // (ChatView.onAppear 의 router 선소비 경로를 실제로 통과한다)
        if E2EDriver.briefingOnLaunch {
            NotificationRouter.shared.pendingBriefing = true
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
