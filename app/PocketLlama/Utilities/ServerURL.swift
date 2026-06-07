//
//  ServerURL.swift
//  PocketLlama
//
//  base URL 정규화(§7.1). 사용자는 base 만 저장(http://192.168.0.10:8080).
//  클라이언트가 경로(/v1/messages, /health, /v1/models)를 조립한다.
//  여기서는 끝 슬래시 제거, 실수로 들어온 경로(/v1/messages 등) 잘라냄, 스킴 보정만 한다.
//

import Foundation

enum ServerURL {
    /// 사용자가 입력한 base 문자열 → 정규화된 base URL. 형식이 깨졌으면 nil.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // 스킴이 없으면 http:// 보정.
        if !s.contains("://") { s = "http://" + s }

        func trimTrailingSlash() { while s.hasSuffix("/") { s.removeLast() } }

        // 사용자가 실수로 붙인 경로 접미사 제거(긴 것부터 검사).
        let strip = ["/v1/messages", "/v1/models", "/health", "/v1"]
        trimTrailingSlash()
        for suffix in strip where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
            break
        }
        trimTrailingSlash()

        // host 가 IP/도메인(점 포함)이거나 localhost 일 때만 유효한 서버 주소로 본다.
        // (이게 없으면 "1" 한 글자가 "http://1" 로 보정돼 멀쩡한 주소로 오인된다 → 화면 튕김의 근본 원인.)
        guard let url = URL(string: s), url.scheme != nil,
              let host = url.host, host == "localhost" || host.contains(".")
        else { return nil }
        return url
    }

    /// 빈값/스킴/형식 검증 결과를 사용자 안내 문자열로(§ Phase 3 검증). 정상이면 nil.
    static func validationMessage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "서버 주소를 입력하세요." }
        guard let url = normalize(trimmed) else {
            return "주소 형식이 올바르지 않습니다. (예: http://192.168.0.10:8080)"
        }
        if let scheme = url.scheme, scheme != "http", scheme != "https" {
            return "http:// 또는 https:// 만 지원합니다."
        }
        return nil
    }
}
