//
//  Haptics.swift
//  PocketLlama — DesignSystem
//
//  외형 트리거(버튼 탭 등)용 햅틱 헬퍼. ViewModel 로직에 끼워넣지 않는다 — UI 이벤트에서만.
//  iOS 외 플랫폼(빌드 폴백)에서는 no-op 으로 컴파일된다.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum Haptics {
    /// 가벼운 탭(전송·열기·이어서 대화).
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// 부드러운 강조(브리핑 카드 도착 등).
    static func soft() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    /// 완료 알림.
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 오류 알림.
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
