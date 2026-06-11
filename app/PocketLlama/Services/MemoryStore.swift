//
//  MemoryStore.swift
//  PocketLlama
//
//  [v0.2 M3] 온디바이스 장기 기억 저장소 — raw sqlite3(import SQLite3) 얇은 래퍼(M-D2).
//  - DB: Application Support/memory.sqlite. 생성 시 NSFileProtectionCompleteUntilFirstUserAuthentication 부여(P1-4).
//  - 스키마: memory + pending_extraction (§1 그대로, CREATE IF NOT EXISTS).
//  - prepared statement·트랜잭션 캡슐화. TEXT 바인딩엔 SQLITE_TRANSIENT 필수(C 매크로가 Swift 에
//    노출 안 됨 → unsafeBitCast(-1, …)로 직접 정의; 누락 시 바인딩 후 버퍼 해제로 댕글링).
//  - 임베딩 [Float](1024) ↔ BLOB. 코사인은 Accelerate vDSP_dotpr(M-D3). 차원 불일치 레코드는 코사인 제외(§1 가드).
//  - 검색: ① searchByEmbedding(점수 = 0.5·cos + 0.3·recency + 0.2·importance/10, M-D9)
//          ② searchByKeyword(LIKE '%?%', M-D4) ③ CRUD(물리 DELETE — M-D8 진짜 삭제).
//
//  스레딩: @MainActor 로 묶어 단일 직렬 접근(여러 곳에서 동시 호출 없음 — ChatViewModel/Extractor/MemoryViewModel
//  모두 MainActor). sqlite3 핸들은 단일 연결. 무거운 작업(임베딩·LLM)은 호출측이 await 로 빼고 결과만 넘긴다.
//

import Foundation
import SQLite3
import Accelerate

@MainActor
final class MemoryStore {
    /// 앱 전역 단일 인스턴스(ChatViewModel·MemoryExtractor·MemoryViewModel 가 공유).
    static let shared = MemoryStore()

    private var db: OpaquePointer?
    private let embeddingDimension = 1024   // M0 실측(§1 — 1024차원 float32)

    /// sqlite3 의 SQLITE_TRANSIENT(= (sqlite3_destructor_type)-1). C 매크로라 Swift 에 직접 노출되지 않아
    /// 비트 패턴(-1)을 destructor 타입으로 캐스팅한다. 바인딩 시 sqlite 가 값 복사를 보장(댕글링 방지).
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // ISO8601(분수초 없음) — 저장/파싱 일관 포맷. UTC 기준.
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private init() {
        open()
        createSchema()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - 연결/스키마

    /// DB 파일을 Application Support 하위에 열고 파일 보호 속성을 부여한다.
    private func open() {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let url = dir.appendingPathComponent("memory.sqlite")

        // 파일이 아직 없으면 먼저 만들어 보호 속성을 건다(없으면 sqlite 가 만든 뒤라 보호 속성 시점이 늦음).
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        #if os(iOS)
        // 첫 잠금해제 이후에만 복호 — 기억 유출면 차단(§9-3). macOS 빌드(폴백 컴파일)에선 미적용.
        try? fm.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif

        if sqlite3_open(url.path, &db) != SQLITE_OK {
            // 열기 실패는 메모리 기능 전체 비활성으로 이어진다(앱 크래시 금지 — 채팅은 계속).
            db = nil
        }
    }

    /// §1 스키마(CREATE IF NOT EXISTS). 멱등 — 매 기동 안전.
    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS memory (
          id            TEXT PRIMARY KEY,
          text          TEXT NOT NULL,
          embedding     BLOB,
          type          TEXT NOT NULL,
          importance    INTEGER NOT NULL,
          created_at    TEXT NOT NULL,
          last_accessed TEXT,
          valid_to      TEXT,
          source        TEXT,
          verified      INTEGER NOT NULL DEFAULT 0
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS pending_extraction (
          id            TEXT PRIMARY KEY,
          transcript    TEXT NOT NULL,
          created_at    TEXT NOT NULL,
          attempts      INTEGER NOT NULL DEFAULT 0
        );
        """)
    }

    /// 결과를 읽지 않는 DDL/단순 실행.
    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - BLOB ↔ [Float] 변환

    /// [Float] → little-endian float32 BLOB(Data).
    private func blob(from vector: [Float]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    /// BLOB(Data) → [Float]. 길이가 4의 배수 아니면 nil(손상 방어).
    private func vector(from data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        var out = [Float](repeating: 0, count: count)
        out.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst)
        }
        return out
    }

    // MARK: - 코사인 유사도(vDSP 가속, M-D3)

    /// 두 벡터의 코사인 유사도. 차원 다르거나 0벡터면 0(§1 가드). 정규화 안 된 임베딩 가정.
    func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        let n = vDSP_Length(a.count)
        vDSP_dotpr(a, 1, b, 1, &dot, n)       // a·b
        vDSP_dotpr(a, 1, a, 1, &na, n)        // |a|²
        vDSP_dotpr(b, 1, b, 1, &nb, n)        // |b|²
        let denom = (na * nb).squareRoot()
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - CRUD

    /// 기억 1건 INSERT(신규). 같은 id 존재 시 무시(OR IGNORE — 멱등).
    func insert(_ m: Memory) {
        guard let db else { return }
        let sql = """
        INSERT OR IGNORE INTO memory
          (id, text, embedding, type, importance, created_at, last_accessed, valid_to, source, verified)
        VALUES (?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, m.id)
        bindText(stmt, 2, m.text)
        if let e = m.embedding { bindBlob(stmt, 3, blob(from: e)) } else { sqlite3_bind_null(stmt, 3) }
        bindText(stmt, 4, m.type)
        sqlite3_bind_int(stmt, 5, Int32(m.importance))
        bindText(stmt, 6, iso.string(from: m.createdAt))
        if let la = m.lastAccessed { bindText(stmt, 7, iso.string(from: la)) } else { sqlite3_bind_null(stmt, 7) }
        if let vt = m.validTo { bindText(stmt, 8, iso.string(from: vt)) } else { sqlite3_bind_null(stmt, 8) }
        if let s = m.source { bindText(stmt, 9, s) } else { sqlite3_bind_null(stmt, 9) }
        sqlite3_bind_int(stmt, 10, m.verified ? 1 : 0)

        sqlite3_step(stmt)
    }

    /// 텍스트·타입·importance·valid_to·verified·embedding 갱신(MemoryView 편집·재임베딩).
    func update(_ m: Memory) {
        guard let db else { return }
        let sql = """
        UPDATE memory SET text=?, embedding=?, type=?, importance=?, valid_to=?, source=?, verified=?
        WHERE id=?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, m.text)
        if let e = m.embedding { bindBlob(stmt, 2, blob(from: e)) } else { sqlite3_bind_null(stmt, 2) }
        bindText(stmt, 3, m.type)
        sqlite3_bind_int(stmt, 4, Int32(m.importance))
        if let vt = m.validTo { bindText(stmt, 5, iso.string(from: vt)) } else { sqlite3_bind_null(stmt, 5) }
        if let s = m.source { bindText(stmt, 6, s) } else { sqlite3_bind_null(stmt, 6) }
        sqlite3_bind_int(stmt, 7, m.verified ? 1 : 0)
        bindText(stmt, 8, m.id)

        sqlite3_step(stmt)
    }

    /// 물리 DELETE(M-D8 — 사용자 삭제는 진짜 삭제).
    func delete(id: String) {
        guard let db else { return }
        let sql = "DELETE FROM memory WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        sqlite3_step(stmt)
    }

    /// 전체 기억(최신순). MemoryView 목록·NOOP 검사(extractor)가 사용.
    func all() -> [Memory] {
        fetch(sql: "SELECT * FROM memory ORDER BY created_at DESC;", bind: { _ in })
    }

    /// last_accessed 갱신(세션당 1회 상한은 호출측 ChatViewModel 이 id 집합으로 관리, M-D14).
    func touchLastAccessed(id: String, now: Date = Date()) {
        guard let db else { return }
        let sql = "UPDATE memory SET last_accessed=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, iso.string(from: now))
        bindText(stmt, 2, id)
        sqlite3_step(stmt)
    }

    // MARK: - 검색

    /// 점수식 가중치(M-D9 잠정값 — 실사용 후 보정). 합 = 1.0.
    private let wRelevance: Float = 0.5
    private let wRecency: Float = 0.3
    private let wImportance: Float = 0.2
    /// recency 지수감쇠 반감기(일). 30일이면 점수 절반.
    private let recencyHalfLifeDays: Double = 30

    /// ① 임베딩 코사인 + recency + importance 종합 점수로 정렬(유효 레코드 전체 스캔).
    /// - 일정형 만료(valid_to < now) 레코드 제외(M-D12).
    /// - 저장 차원 ≠ 질의 차원이면 코사인 제외(점수 0 취급) — §1 가드.
    /// - 임베딩 NULL 레코드는 코사인 0(relevance 0)이라 자연히 후순위(호출측은 이때 LIKE 폴백 병행).
    func searchByEmbedding(query: [Float], now: Date = Date()) -> [(memory: Memory, score: Float)] {
        let candidates = validMemories(now: now)
        guard query.count == embeddingDimension else { return [] }

        return candidates.map { m -> (Memory, Float) in
            let relevance: Float
            if let e = m.embedding, e.count == query.count {
                // cos 는 [-1,1] → [0,1] 로 클램프(음수는 무관으로 본다).
                relevance = max(0, cosine(query, e))
            } else {
                relevance = 0
            }
            let recency = recencyScore(m.createdAt, now: now)
            let importance = Float(min(max(m.importance, 1), 10)) / 10
            let score = wRelevance * relevance + wRecency * recency + wImportance * importance
            return (m, score)
        }
        .sorted { $0.1 > $1.1 }
    }

    /// ② 키워드 폴백(M-D4) — LIKE '%?%'. 임베딩 서버 다운 시 회상 경로. 만료 일정 제외.
    func searchByKeyword(query: String, now: Date = Date()) -> [Memory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let rows = fetch(
            sql: "SELECT * FROM memory WHERE text LIKE '%' || ? || '%' ORDER BY created_at DESC;",
            bind: { [weak self] stmt in self?.bindText(stmt, 1, trimmed) }
        )
        return rows.filter { !isExpired($0, now: now) }
    }

    /// 유효 기억(일정형 만료 제외, M-D12) 전체.
    private func validMemories(now: Date) -> [Memory] {
        all().filter { !isExpired($0, now: now) }
    }

    /// 일정형 만료 여부(type=일정 && valid_to < now). 다른 타입·NULL valid_to 는 만료 없음.
    private func isExpired(_ m: Memory, now: Date) -> Bool {
        guard m.type == MemoryType.schedule.rawValue, let vt = m.validTo else { return false }
        return vt < now
    }

    /// 생성 시각 기준 지수감쇠 recency 점수(0~1].
    private func recencyScore(_ created: Date, now: Date) -> Float {
        let days = max(0, now.timeIntervalSince(created) / 86_400)
        let decay = exp(-Double.ln2 / recencyHalfLifeDays * days)
        return Float(decay)
    }

    // MARK: - pending_extraction 큐(§3 — MemoryExtractor 가 사용)

    /// 큐에 transcript 동기 INSERT(1단 — 빠른 기록).
    func enqueuePending(id: String = UUID().uuidString, transcript: String, now: Date = Date()) {
        guard let db else { return }
        let sql = "INSERT OR IGNORE INTO pending_extraction (id, transcript, created_at, attempts) VALUES (?,?,?,0);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        bindText(stmt, 2, transcript)
        bindText(stmt, 3, iso.string(from: now))
        sqlite3_step(stmt)
    }

    /// 큐 항목 1건(가장 오래된 것부터). 없으면 nil.
    func nextPending() -> PendingExtraction? {
        guard let db else { return nil }
        let sql = "SELECT id, transcript, created_at, attempts FROM pending_extraction ORDER BY created_at ASC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return PendingExtraction(
            id: columnText(stmt, 0) ?? "",
            transcript: columnText(stmt, 1) ?? "",
            attempts: Int(sqlite3_column_int(stmt, 3))
        )
    }

    /// 큐에 남은 개수(트리거 판단용).
    func pendingCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM pending_extraction;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// attempts 증가(JSON 추출 실패 시).
    func incrementPendingAttempts(id: String) {
        guard let db else { return }
        let sql = "UPDATE pending_extraction SET attempts = attempts + 1 WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        sqlite3_step(stmt)
    }

    /// 큐 항목 제거(전 과정 완료 또는 3회 초과 폐기 시 — §3 멱등 종료점).
    func deletePending(id: String) {
        guard let db else { return }
        let sql = "DELETE FROM pending_extraction WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        sqlite3_step(stmt)
    }

    // MARK: - 행 → Memory 매핑

    /// SELECT * 결과를 Memory 로 디코딩(컬럼 순서는 §1 정의 순서 고정).
    private func fetch(sql: String, bind: (OpaquePointer?) -> Void) -> [Memory] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)

        var out: [Memory] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            // 컬럼: 0 id 1 text 2 embedding 3 type 4 importance 5 created_at 6 last_accessed 7 valid_to 8 source 9 verified
            let id = columnText(stmt, 0) ?? UUID().uuidString
            let text = columnText(stmt, 1) ?? ""
            var embedding: [Float]? = nil
            if sqlite3_column_type(stmt, 2) == SQLITE_BLOB,
               let bytes = sqlite3_column_blob(stmt, 2) {
                let n = Int(sqlite3_column_bytes(stmt, 2))
                let data = Data(bytes: bytes, count: n)
                embedding = vector(from: data)
            }
            let type = columnText(stmt, 3) ?? MemoryType.fact.rawValue
            let importance = Int(sqlite3_column_int(stmt, 4))
            let createdAt = columnText(stmt, 5).flatMap { iso.date(from: $0) } ?? Date()
            let lastAccessed = columnText(stmt, 6).flatMap { iso.date(from: $0) }
            let validTo = columnText(stmt, 7).flatMap { iso.date(from: $0) }
            let source = columnText(stmt, 8)
            let verified = sqlite3_column_int(stmt, 9) != 0

            out.append(Memory(
                id: id, text: text, embedding: embedding, type: type, importance: importance,
                createdAt: createdAt, lastAccessed: lastAccessed, validTo: validTo,
                source: source, verified: verified
            ))
        }
        return out
    }

    // MARK: - 바인딩 헬퍼(SQLITE_TRANSIENT 캡슐화)

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        // SQLITE_TRANSIENT 로 sqlite 가 즉시 복사 → Swift String 임시버퍼 해제와 무관(댕글링 방지).
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    private func bindBlob(_ stmt: OpaquePointer?, _ idx: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, idx, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }
}

/// pending_extraction 1행(§1).
struct PendingExtraction: Equatable {
    let id: String
    let transcript: String
    let attempts: Int
}

private extension Double {
    static let ln2 = log(2.0)
}
