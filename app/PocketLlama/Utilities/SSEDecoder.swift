//
//  SSEDecoder.swift
//  PocketLlama
//
//  버퍼 기반 SSE 파서(§7.4 normative). bytes.lines 의 '한 줄'을 push 하면
//  빈 줄(이벤트 경계)에서 이벤트 1개를 방출한다.
//  - 다중 data: 줄은 \n 으로 join (SSE 스펙, 단순 concat 아님)
//  - 끝의 \r 제거 (\r\n 대응)
//  - 주석(:) / 알 수 없는 필드 무시
//

import Foundation

struct SSEEvent {
    let event: String?
    let data: String
}

final class SSEDecoder {
    private var dataLines: [String] = []
    private var eventType: String?

    /// 한 줄 push. 빈 줄이면 누적된 이벤트 1개 방출, 아니면 nil.
    func push(_ rawLine: String) -> SSEEvent? {
        // \r\n 대응: 라인 끝 \r 제거.
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

        if line.isEmpty {
            defer { dataLines.removeAll(); eventType = nil }
            guard !dataLines.isEmpty else { return nil }
            // 다중 data: 줄 → \n join.
            return SSEEvent(event: eventType, data: dataLines.joined(separator: "\n"))
        }

        if line.hasPrefix(":") { return nil }            // 주석 무시

        if line.hasPrefix("event:") {
            eventType = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
        }
        // 그 외 필드(id:, retry: 등)는 MVP에서 무시.
        return nil
    }
}
