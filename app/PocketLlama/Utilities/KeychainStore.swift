//
//  KeychainStore.swift
//  PocketLlama
//
//  [Phase P0 — 보안 선결] 민감 키(서버 apiKey·Tavily 키)를 Keychain(SecItem)에 보관하는 CRUD 래퍼.
//  계획서 §0(D10 — Keychain 단일 경로): 평문 UserDefaults 대신 SecItem 으로 이관해
//  번들 평문/실기기 키 변경 문제를 해소한다.
//  - kSecClassGenericPassword + service "drlee.PocketLlama"(번들 id) + account 키로 식별.
//  - 빈 문자열 set 은 delete 와 동일 취급(빈 값 잔존 방지).
//
//  설계 판단: 동기 API 로 둔다 — 키 길이가 짧고 호출 빈도가 낮아(설정 저장/런타임 조회)
//  비동기 래핑의 이득이 없고, AppSettingsStore 의 동기 프로퍼티 getter/setter 와 모양을 맞추기 쉽다.
//

import Foundation
import Security

enum KeychainStore {
    /// 이 앱의 Keychain service 네임스페이스(번들 id 와 동일).
    private static let service = "drlee.PocketLlama"

    /// account 키 — 항목 구분자. 문자열 오타 방지를 위해 enum 으로 고정.
    enum Account: String {
        case serverAPIKey
        case tavilyAPIKey
    }

    // MARK: - 조회

    /// 값이 없거나 디코딩 실패면 nil.
    static func get(_ account: Account) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    // MARK: - 저장 / 삭제

    /// 빈 문자열은 delete 와 동일 취급(빈 값 잔존 차단). 그 외에는 upsert.
    static func set(_ value: String, for account: Account) {
        guard !value.isEmpty else {
            delete(account)
            return
        }
        let data = Data(value.utf8)
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account.rawValue,
        ]
        // 이미 존재하면 update, 없으면 add(upsert).
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData] = data
            // 잠금 화면 후에도 백그라운드 발화(알림 등) 시 읽을 수 있게 unlock-first-after-restart.
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    /// 항목 삭제(없어도 무해).
    static func delete(_ account: Account) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
