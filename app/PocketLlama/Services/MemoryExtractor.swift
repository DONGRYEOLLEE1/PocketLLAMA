//
//  MemoryExtractor.swift
//  PocketLlama
//
//  [v0.2 M3] pending 큐 처리기(§3 2단 — 유휴 시 멱등 처리).
//  - enqueue(transcript:): 빠른 동기 INSERT(1단). 사용자 대기 0.
//  - processQueue(): async(2단) — 각 row 에 대해
//      ① M0 검증 추출 프롬프트(+ 부정문 few-shot 2쌍)로 LLM 비스트림 추출(LLMChatClient.send 재사용)
//      ② JSON 디코딩(코드펜스 방어) 실패 → attempts+1(3회 초과 DELETE 폐기)
//      ③ 항목별: 문서측 임베딩(실패 시 NULL) → 룰 NOOP(max 코사인 ≥ 0.75 면 skip) → 미만 ADD(verified=0)
//      ④ type=일정 이면 transcript 의 날짜 표현에서 valid_to 단순 휴리스틱 추정(불가하면 NULL)
//      ⑤ 전 항목 완료 시에만 row DELETE(멱등 — 중간 사망 시 다음 기회 재처리)
//  - 동시 실행 1개 가드(isProcessing).
//

import Foundation

@MainActor
final class MemoryExtractor {
    private let store: MemoryStore
    private let client: LLMChatClient
    private let embedding: EmbeddingServiceProtocol?

    /// 동시 실행 1개 가드(중복 트리거 무시 — 멱등 보장 보조).
    private var isProcessing = false

    /// 룰 NOOP 임계(θ_same, M-D9 잠정). 기존 기억과 max 코사인 ≥ 이 값이면 중복으로 보고 skip.
    private let thetaSame: Float = 0.75
    private let extractMaxTokens = 512
    /// JSON 실패 재시도 한도(초과분은 폐기, §3).
    private let maxAttempts = 3

    init(store: MemoryStore = .shared, client: LLMChatClient, embedding: EmbeddingServiceProtocol?) {
        self.store = store
        self.client = client
        self.embedding = embedding
    }

    // MARK: - 1단: 빠른 기록

    /// transcript 를 pending 큐에 동기 INSERT(빈 입력 무시).
    func enqueue(transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.enqueuePending(transcript: trimmed)
    }

    // MARK: - 2단: 유휴 처리(멱등)

    /// 큐를 비울 때까지 순차 처리. 이미 처리 중이거나 빈 큐면 즉시 반환.
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // 무한루프 방지: 한 사이클당 최대 처리 수(폐기 못 한 row 가 계속 잡히는 사고 차단).
        var safety = 50
        while safety > 0, let row = store.nextPending() {
            safety -= 1
            await process(row)
        }
    }

    /// 큐 1건 처리(§3 절차). 어떤 단계가 실패해도 크래시 0 — 폐기 또는 다음 기회.
    private func process(_ row: PendingExtraction) async {
        // ① LLM 추출.
        let user = ChatTurn(role: "user", content: row.transcript)
        let raw: String
        do {
            raw = try await client.send(messages: [user], system: Self.extractionSystem, maxTokens: extractMaxTokens).text
        } catch {
            // LLM 호출 자체 실패(네트워크 등)는 시도 소진 없이 다음 기회로(서버 다운에 attempts 소모 방지).
            return
        }

        // ② JSON 디코딩(코드펜스 방어).
        guard let items = Self.decodeItems(raw) else {
            // JSON 파싱 실패 → attempts+1. 한도 초과면 폐기(§3).
            if row.attempts + 1 >= maxAttempts {
                store.deletePending(id: row.id)
            } else {
                store.incrementPendingAttempts(id: row.id)
            }
            return
        }

        // 빈 배열([])도 정상 — "기억할 것 없음"으로 큐 종료(재처리 안 함).
        let existing = store.all()
        for item in items {
            await ingest(item, existingSnapshot: existing, transcript: row.transcript)
        }

        // ⑤ 전 항목 완료 → row DELETE(멱등 종료점).
        store.deletePending(id: row.id)
    }

    /// 추출 항목 1건을 임베딩·NOOP 판정 후 저장(verified=0).
    private func ingest(_ item: ExtractedItem, existingSnapshot: [Memory], transcript: String) async {
        // ③ 문서측 임베딩(실패 시 NULL — LIKE 폴백 대상).
        var vector: [Float]? = nil
        if let embedding {
            vector = try? await embedding.embedDocument(item.text)
        }

        // 룰 NOOP: 기존 기억과 max 코사인 ≥ θ_same 이면 중복으로 보고 skip(임베딩 있을 때만 판정).
        if let v = vector {
            let maxCos = existingSnapshot.compactMap { $0.embedding }
                .map { store.cosine(v, $0) }
                .max() ?? 0
            if maxCos >= thetaSame { return }
        }

        // ④ type=일정 이면 valid_to 단순 휴리스틱(불가하면 NULL — 과도한 파싱 금지).
        var validTo: Date? = nil
        if item.normalizedType == MemoryType.schedule.rawValue {
            validTo = Self.inferValidTo(from: transcript)
        }

        let memory = Memory(
            text: item.text,
            embedding: vector,
            type: item.normalizedType,
            importance: item.normalizedImportance,
            validTo: validTo,
            source: "extracted",
            verified: false
        )
        store.insert(memory)
    }

    // MARK: - 추출 프롬프트(M0 검증 프롬프트 + 부정문 few-shot 2쌍)

    /// M0 게이트 8/8 PASS 프롬프트(§3) + 부정문·폐기 few-shot 보강(M-D6).
    /// 출력은 JSON 배열만. 지속성 없는 발화는 빈 배열([]).
    static let extractionSystem = """
    너는 사용자와 비서의 대화에서 "사용자에 대해 장기적으로 기억할 만한 사실"만 추출하는 도구다.
    - 사용자 발화 중심으로, 시간이 지나도 유효한 지속적 사실(선호·습관·관계·일정 등)만 추출한다.
    - 일시적 질문, 일반 지식 요청, 단순 인사, 비서의 발화는 추출하지 않는다.
    - 부정문도 사실이면 추출한다(예: "매운 거 못 먹어" → 저장). 단순히 무엇을 물었는지(예: "매운 거 좋아하냐고 물었음")는 폐기한다.
    - 각 항목: {"text": 간결한 한 문장, "type": "선호|사실|일정|관계", "importance": 1~10}
    - 기억할 것이 없으면 빈 배열 [] 만 출력한다.
    - 반드시 JSON 배열만 출력한다(설명·코드펜스 없이).

    예시:
    입력: "나 매운 거 못 먹어"
    출력: [{"text":"매운 음식을 못 먹는다","type":"선호","importance":8}]

    입력: "아까 매운 거 좋아하냐고 물었잖아"
    출력: []

    입력: "오늘 날씨 어때?"
    출력: []

    입력: "6월 말에 부산으로 출장 가"
    출력: [{"text":"6월 말 부산 출장 예정","type":"일정","importance":7}]
    """

    // MARK: - JSON 디코딩(코드펜스 방어)

    struct ExtractedItem: Decodable, Equatable {
        let text: String
        let type: String?
        let importance: Int?

        /// type 정규화 — 표준 4종 외 값은 "사실"로 폴백(기본값 M4 규칙과 통일).
        var normalizedType: String {
            guard let t = type?.trimmingCharacters(in: .whitespacesAndNewlines),
                  MemoryType.allCases.map(\.rawValue).contains(t) else {
                return MemoryType.fact.rawValue
            }
            return t
        }
        /// importance 정규화 — 1~10 클램프, 누락 시 7.
        var normalizedImportance: Int {
            guard let i = importance else { return 7 }
            return min(max(i, 1), 10)
        }
    }

    /// LLM 출력에서 JSON 배열을 추출·디코딩. 코드펜스(```json … ```)·앞뒤 텍스트 방어.
    /// 파싱 불가면 nil(호출측이 attempts 증가). 빈 배열은 [](정상 — 기억 없음).
    static func decodeItems(_ raw: String) -> [ExtractedItem]? {
        let cleaned = stripCodeFence(raw)
        // 첫 '[' ~ 마지막 ']' 구간만 취해 잡텍스트 제거.
        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]"), start <= end else {
            // 배열이 전혀 없으면 모델이 빈 응답/거부일 수 있음 → 실패로 보고 재시도(빈 배열과 구분).
            return nil
        }
        let jsonSlice = String(cleaned[start...end])
        guard let data = jsonSlice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ExtractedItem].self, from: data)
    }

    /// 코드펜스 제거(```json / ``` 래핑 방어).
    private static func stripCodeFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            // 첫 줄(``` 또는 ```json) 제거.
            if let nl = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: nl)...])
            }
            if let close = t.range(of: "```", options: .backwards) {
                t = String(t[..<close.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - valid_to 단순 휴리스틱(M-D12 — 과도한 파싱 금지)

    /// transcript 의 단순 날짜 표현에서 만료일을 추정. 못 찾으면 nil.
    /// - "N월 말/초/중순" → 해당 월 말일(말은 마지막날, 초/중순도 보수적으로 말일까지 유효로 본다).
    /// - "N월 D일" → 그 날.
    /// - 못 찾으면 nil(휴리스틱 실패는 무기한으로 둔다 — 과소만료보다 안전).
    static func inferValidTo(from transcript: String, now: Date = Date()) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: now)

        // "N월 D일"
        if let m = firstMatch(in: transcript, pattern: "([0-9]{1,2})\\s*월\\s*([0-9]{1,2})\\s*일") {
            if let month = Int(m[1]), let day = Int(m[2]) {
                return makeDate(year: year, month: month, day: day, now: now, cal: cal)
            }
        }
        // "N월 말/초/중순/중" → 해당 월 말일
        if let m = firstMatch(in: transcript, pattern: "([0-9]{1,2})\\s*월\\s*(말|초|중순|중)") {
            if let month = Int(m[1]) {
                let day = lastDay(year: year, month: month, cal: cal)
                return makeDate(year: year, month: month, day: day, now: now, cal: cal)
            }
        }
        return nil
    }

    /// 정규식 첫 매치의 캡처 그룹 배열([0]=전체, [1..]=그룹).
    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = re.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    private static func lastDay(year: Int, month: Int, cal: Calendar) -> Int {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let date = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: date) else { return 28 }
        return range.upperBound - 1
    }

    /// 연/월/일 → Date(만료는 그 날 끝). 과거로 추정되면 내년으로 보정(미래 일정 의도).
    private static func makeDate(year: Int, month: Int, day: Int, now: Date, cal: Calendar) -> Date? {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = 23; comps.minute = 59; comps.second = 59
        guard var date = cal.date(from: comps) else { return nil }
        // 추정일이 이미 과거면(연말 근처 다음 해 일정 등) 내년으로 보정.
        if date < now {
            comps.year = year + 1
            date = cal.date(from: comps) ?? date
        }
        return date
    }
}
