//
//  ClientError.swift
//  PocketLlama
//
//  네트워크/계약 오류를 사용자 친화 메시지로 분류하는 공통 enum.
//  계획서 §7.6 — 타임아웃 / 연결 거부 / 로컬 네트워크 권한 / 형식·HTTP 오류를 구분 표시.
//

import Foundation

enum ClientError: Error, LocalizedError, Equatable {
    case badURL                // 서버 주소 형식 오류
    case notConnected          // 연결 거부(서버 꺼짐/포트 불일치) + 로컬 네트워크 권한 거부 통합
    case timedOut              // 타임아웃(35B 지연 포함)
    /// iOS 로컬 네트워크 권한 거부 전용. 단, iOS 는 이 상황을 NSURLError 로 명확히 구분하지 못해
    /// map() 에서 실제로 반환되지 않는다(dead case). 권한 안내는 .notConnected 설명에 병기했다.
    /// 향후 권한 API(NWPathMonitor/Local Network entitlement)로 명시 구분이 가능해지면 여기서 분기한다.
    case localNetworkDenied
    case http(Int, String?)    // 4xx/5xx + 본문 메시지
    case decoding(String)      // 응답 해석 실패
    case cancelled             // 요청 취소

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "서버 주소 형식이 올바르지 않습니다. (예: http://192.168.0.10:8080)"
        case .notConnected:
            return "서버에 연결할 수 없습니다. 맥북에서 서버가 0.0.0.0으로 떠 있는지, 같은 Wi-Fi인지, 그리고 로컬 네트워크 권한(설정 앱 > PocketLlama > 로컬 네트워크)을 허용했는지 확인하세요."
        case .timedOut:
            return "응답이 지연되고 있습니다. 모델이 큰 경우 첫 응답이 느릴 수 있습니다."
        case .localNetworkDenied:
            return "로컬 네트워크 접근 권한이 필요합니다. 설정 앱에서 허용해 주세요."
        case .http(let code, let msg):
            return "서버 오류(HTTP \(code))\(msg.map { ": \($0)" } ?? "")"
        case .decoding(let detail):
            return "응답 해석에 실패했습니다: \(detail)"
        case .cancelled:
            return "요청이 취소되었습니다."
        }
    }
}
