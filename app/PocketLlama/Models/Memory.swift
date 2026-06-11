//
//  Memory.swift
//  PocketLlama
//
//  [v0.2 M3] 장기 기억 1건(§1 memory 테이블 1행에 대응).
//  SQLite 영속·검색·UI(MemoryView) 가 공유하는 값 타입. embedding 은 [Float](1024) ↔ BLOB.
//  type 은 "선호|사실|일정|관계" 자유 문자열(스키마상 enum 강제 없음 — 추출/사용자 입력 유연성).
//

import Foundation

/// 장기 기억 1건. created_at/last_accessed/valid_to 는 ISO8601 문자열로 저장(§1 TEXT).
struct Memory: Identifiable, Equatable {
    let id: String              // UUID 문자열
    var text: String
    var embedding: [Float]?     // nil = 임베딩 대기/실패 → LIKE 폴백 대상
    var type: String            // 선호|사실|일정|관계
    var importance: Int         // 1~10
    let createdAt: Date
    var lastAccessed: Date?
    var validTo: Date?          // 일정형 만료(M-D12). nil = 무기한
    var source: String?
    var verified: Bool          // false = 검토 필요(자동 추출). true = 사용자 명시/검토 완료

    init(
        id: String = UUID().uuidString,
        text: String,
        embedding: [Float]? = nil,
        type: String,
        importance: Int,
        createdAt: Date = Date(),
        lastAccessed: Date? = nil,
        validTo: Date? = nil,
        source: String? = nil,
        verified: Bool = false
    ) {
        self.id = id
        self.text = text
        self.embedding = embedding
        self.type = type
        self.importance = importance
        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
        self.validTo = validTo
        self.source = source
        self.verified = verified
    }
}

/// 기억 타입 표준값(§1 — 추출/명시 저장이 따르는 권장 집합). 자유 문자열도 허용하나 UI 칩 표준은 이 4종.
enum MemoryType: String, CaseIterable {
    case preference = "선호"
    case fact = "사실"
    case schedule = "일정"
    case relation = "관계"
}
