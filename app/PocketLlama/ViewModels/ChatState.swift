//
//  ChatState.swift
//  PocketLlama
//
//  채팅 상태 머신(§8.4). 단순 isLoading 불리언 금지 — 35B TTFT 가 길어
//  "멈춘 듯" 오해를 부르므로 각 단계에 구체적 한글 안내를 둔다.
//

import Foundation

enum ChatState: Equatable {
    case idle          // 입력 대기
    case connecting    // 서버 연결 시도 중
    case ingesting     // 첫 토큰 대기(35B는 수 초~1분+)
    case generating    // 스트리밍 수신 중
    case cancelled     // 사용자 취소
    case failed(String) // 오류(사용자 메시지)

    /// 진행 중 안내 문구(없으면 nil).
    var notice: String? {
        switch self {
        case .connecting: return "서버에 연결 중…"
        case .ingesting:  return "맥북이 프롬프트를 분석하고 있습니다 (첫 응답이 느릴 수 있어요)…"
        case .generating: return "답변을 생성하고 있습니다…"
        case .cancelled:  return "요청이 취소되었습니다."
        default:          return nil
        }
    }

    /// 요청 진행 중인지(전송 버튼 비활성/Cancel 노출 판단).
    var isBusy: Bool {
        switch self {
        case .connecting, .ingesting, .generating: return true
        default: return false
        }
    }

    /// 오류 배너에 표시할 메시지(아니면 nil).
    var errorMessage: String? {
        if case .failed(let msg) = self { return msg }
        return nil
    }
}
