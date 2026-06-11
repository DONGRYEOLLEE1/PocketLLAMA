//
//  ChatViewModel.swift
//  PocketLlama
//
//  채팅 화면의 상태/동작. ChatState 머신(§8.4) + 멀티턴 슬라이딩 윈도우(§7.2) + 취소(§8.5).
//  @MainActor 로 UI 갱신을 메인에서 처리한다.
//

import Foundation
import Observation

@Observable @MainActor
final class ChatViewModel {
    var messages: [ChatTurn] = []
    var input: String = ""
    var state: ChatState = .idle

    private var task: Task<Void, Never>?
    private let client: LLMChatClient
    private let store: AppSettingsStore
    private let searchService: SearchServiceProtocol   // [Phase T2] 웹검색(§4)
    private let historyWindow = 12   // 최근 N 메시지만 전송(§7.2 슬라이딩 윈도우)
    private let maxTokens = 1024
    private let maxToolRounds = 3    // [Phase T2] 진입 3회 = tool 2라운드 + 최종(§4)
    private let baseSystemPrompt = "당신은 PocketLlama의 친절한 한국어 비서입니다. 간결하고 정확하게 답하고, 코드에는 마크다운 코드블록을 사용하도록 하세요."

    // MARK: - [v0.2 M2] 세션 요약(③ 계층)
    //
    // ① conversationSummary: 윈도우(historyWindow) 밖으로 잘려나간 구간의 누적 요약(대화 내 연속성).
    //    send() 시 system 가변부에 `[이전 대화 요약]` 으로 주입. newChat 시 초기화.
    // ② lastSummarizedCount: 어디까지 요약에 반영했는지(요약 대상 경계). 윈도우 초과 첫 시점부터 갱신.
    // ③ summaryTask: 요약 LLM 콜은 스트리밍과 경합하지 않게 별도 Task. 취소 전파 불요(실패 시 미주입).
    private var conversationSummary: String?
    private var lastSummarizedCount = 0
    private var summaryTask: Task<Void, Never>?
    private let summaryMaxTokens = 300

    // MARK: - [v0.2 M3] 장기기억(② 계층)
    //
    // ① memoryStore: SQLite 단일 인스턴스(검색·저장·last_accessed). ② embedding: 입력/문서 임베딩(실패 허용).
    // ③ extractor: pending 큐 처리기(발화→추출→저장). ④ accessedThisSession: last_accessed 세션당 1회 상한(M-D14).
    // ⑤ injectMaxTokens-relevant: send 직전 회상 검색이 응답을 0.5s 이상 지연시키지 않게 임베딩 race 타임아웃 짧게.
    private let memoryStore: MemoryStore
    private let embedding: EmbeddingServiceProtocol?
    private let extractor: MemoryExtractor
    private var accessedThisSession: Set<String> = []
    private let memoryInjectMax = 5      // 주입 상한(M-D9 top 3~5)
    private let memoryInjectMin = 3      // 후보 충분 시 최소 노출 목표
    private let thetaTopic: Float = 0.60 // 동주제 dedup 임계(M-D9')
    /// 입력 임베딩 race 타임아웃(초) — 이 안에 응답 없으면 LIKE 폴백(send 지연 방지).
    private let embedRaceTimeout: Double = 0.4

    init(
        client: LLMChatClient,
        store: AppSettingsStore,
        searchService: SearchServiceProtocol? = nil,
        memoryStore: MemoryStore = .shared,
        embedding: EmbeddingServiceProtocol? = nil
    ) {
        self.client = client
        self.store = store
        // 기본 구현체는 init 본문에서 생성(기본 인자식이 nonisolated 컨텍스트에서 평가되는 경고 회피).
        self.searchService = searchService ?? TavilySearchService()
        self.memoryStore = memoryStore
        self.embedding = embedding
        self.extractor = MemoryExtractor(store: memoryStore, client: client, embedding: embedding)
        self.messages = store.loadSession()   // 최근 대화 복원(Phase 8)
    }

    /// [v0.2 M3] send() 직전 회상 검색이 채우는 기억 주입 블록(가변부). 0건이면 nil → 블록 생략(M-D9).
    /// systemPrompt 계산 시 코어·프로필 뒤·대화 요약 앞에 배치(M-D10). send 마다 갱신.
    private var recalledMemoryBlock: String?

    /// [Phase T2] system 프롬프트 — 웹검색 지침 + 프로필(불변 코어) + 가변 기억/요약 주입.
    /// 주입 순서(M-D10): 불변 코어 지침 → core 프로필(자주 안 바뀜) → 가변(기억 슬라이스 → 이전 대화 요약).
    private var systemPrompt: String {
        var s = baseSystemPrompt
        if store.isWebSearchEnabled {
            s += "\n\n최신 정보·시세·뉴스·날씨 등 실시간성 질문에만 web_search 도구를 사용하세요. "
            s += "일반 지식·잡담에는 사용하지 마세요. 검색 결과로 답할 때는 출처를 마크다운 링크로 표기하세요."
        }
        // [v0.2 M4] 명시 저장 tool 지침(웹검색과 무관하게 항상 — saveMemory 는 키 없이도 제공).
        s += "\n\n사용자가 명시적으로 기억을 요청할 때만 save_memory 를 사용하세요."
        // [v0.2 M1] 프로필 주입 — 구조화 블록(coreProfileBlock)으로 일원화. 불변 쪽(여기) 배치.
        if let profile = store.coreProfileBlock() {
            s += "\n\n" + profile
        }
        // [v0.2 M3] 가변부(1) — 회상된 장기 기억(send 직전 검색 결과). 코어·프로필 뒤, 대화 요약 앞.
        if let mem = recalledMemoryBlock, !mem.isEmpty {
            s += "\n\n" + mem
        }
        // [v0.2 M2] 가변부(2) — 윈도우 밖으로 잘린 대화 요약이 있으면 system 에 주입(연속성 유지).
        let summary = conversationSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let summary, !summary.isEmpty {
            s += "\n\n[이전 대화 요약] " + summary
        }
        return s
    }

    var isEmpty: Bool { messages.isEmpty }

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.isBusy
    }

    // MARK: - 전송(스트리밍 Phase 7 / 비스트림 Phase 6 분기)

    /// max_tokens 로 잘렸을 때 답변 끝에 덧붙이는 안내.
    private static let truncationNotice = "\n\n⚠️ 응답이 max_tokens 로 잘렸습니다"

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, task == nil else { return }   // 디바운스 / in-flight 1개(§8.5)
        input = ""

        // 이전 오류/취소 표시 정리.
        if case .failed = state { state = .idle }
        if case .cancelled = state { state = .idle }

        messages.append(ChatTurn(role: "user", content: text))
        var reply = ChatTurn(role: "assistant", content: "")
        messages.append(reply)
        store.saveSession(messages)

        // 서버 연결 시도 단계(§8.4). 요청/스트림 시작 직전에 .ingesting 으로 전환한다.
        state = .connecting

        // 마지막(in-flight 빈 assistant turn) 제외 + 빈 content turn 일반 제외 + 슬라이딩 윈도우(§7.2).
        var window = Array(
            messages.dropLast()
                .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .suffix(historyWindow)
        )
        // 윈도우가 assistant 로 시작하면 "첫 메시지는 user" 계약(§7.2) 위반 → 제거(400 방지).
        if window.first?.role == "assistant" { window.removeFirst() }

        // [v0.2 M2] 윈도우 초과 재귀 요약 트리거 — 잘려나간 구간을 비동기로 요약(스트리밍과 별도 Task).
        // send() 본 경로(아래 task)는 그대로 진행한다(요약은 뒤에서, 미완료 시 그냥 미주입).
        maybeSummarizeOverflow()

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                // [v0.2 M3] 회상 검색 → 기억 블록 주입(systemPrompt 가변부). runToolLoop 전에 채운다.
                //   임베딩 race 타임아웃 짧게 → 실패 즉시 LIKE → LIKE 도 실패하면 무주입(send 지연 방지).
                await self.recallAndInjectMemory(for: text)
                try await self.runToolLoop(window: window, reply: &reply)
                self.state = .idle
                self.store.saveSession(self.messages)
            } catch is CancellationError {
                // 사용자 Cancel → 외부 Task 취소로 for try await 가 CancellationError 를 던진다(§8.5).
                self.handleFailure(.cancelled, replyID: reply.id)
            } catch let error as ClientError {
                self.handleFailure(error, replyID: reply.id)
            } catch {
                self.handleFailure(.http(-1, error.localizedDescription), replyID: reply.id)
            }
        }
    }

    // MARK: - [Phase T2] tool 루프(§4 — 엄격 한도)

    /// 최대 3회 진입 루프(tool 2라운드 + 최종 강제 답변, §4).
    /// - tool_use 수신 → .searching → (중복 query 재사용) → Tavily 검색 → wireContext 에
    ///   assistant(tool_use)+user(tool_result) append → 다음 라운드.
    /// - tool_use/tool_result 턴은 라운드 내부 휘발 컨텍스트로만 존재(영속 히스토리 제외, §4
    ///   슬라이딩 윈도우의 tool 쌍 절단 방지). 영속에는 user 질문 + 최종 assistant 텍스트만.
    /// - 취소: 스트림·검색 await 모두 같은 Task 내 → task.cancel() 즉시 전파(§8.5).
    private func runToolLoop(window: [ChatTurn], reply: inout ChatTurn) async throws {
        let streaming = store.useStreaming
        let webEnabled = store.isWebSearchEnabled

        // 휘발 wire 컨텍스트: 텍스트 히스토리 + 신규 user 턴(window 의 마지막이 이번 user 턴).
        var wireContext: [MessagesRequest.Wire] = window.map { .init(role: $0.role, content: $0.content) }

        // 이번 send 내 동일 query 결과 캐시(중복 검색 차단, §4).
        var searchCache: [String: String] = [:]

        state = .ingesting

        for round in 0..<maxToolRounds {
            // 라운드 0·1 = tools 포함, 마지막 라운드(2) = tools 제거 → 강제 최종 답변(§4).
            // [v0.2 M4] tools 구성: 웹검색 가능 시 [webSearch, saveMemory], 키 없으면 [saveMemory]만(§4).
            let tools: [ToolDefinition]?
            if round < maxToolRounds - 1 {
                tools = webEnabled ? [.webSearch, .saveMemory] : [.saveMemory]
            } else {
                tools = nil   // 마지막 라운드 — 강제 최종 답변
            }

            // 이번 라운드에서 tool_use 가 나오면 채운다(나오면 검색 후 다음 라운드).
            var pendingTool: ChatCompletion.ToolUse?
            // tool_use 전에 모델이 흘린 텍스트(생각)는 최종 답변에서 제외 → 라운드 시작 스냅샷으로 롤백.
            let contentBeforeRound = reply.content

            if streaming {
                for try await event in client.stream(wire: wireContext, system: systemPrompt, maxTokens: maxTokens, tools: tools) {
                    switch event {
                    case .delta(let t):
                        if !isGenerating(state) { state = .generating }
                        reply.content += t
                        applyReply(reply)
                    case .toolUse(let id, let name, let inputJSON):
                        pendingTool = .init(id: id, name: name, inputJSON: inputJSON)
                    case .done(let truncated):
                        if truncated, pendingTool == nil {
                            reply.content += Self.truncationNotice
                            applyReply(reply)
                        }
                    }
                }
                // tool_use 가 났으면 이 라운드의 선행 텍스트는 버린다(다음 라운드가 최종 답변).
                if pendingTool != nil {
                    reply.content = contentBeforeRound
                    applyReply(reply)
                }
            } else {
                let completion = try await client.send(wire: wireContext, system: systemPrompt, maxTokens: maxTokens, tools: tools)
                try Task.checkCancellation()
                if let tu = completion.toolUse, completion.stopReason == "tool_use" {
                    pendingTool = tu
                } else {
                    state = .generating
                    reply.content += completion.text + (completion.truncated ? Self.truncationNotice : "")
                    applyReply(reply)
                }
            }

            // tool_use 없으면 이번 라운드의 텍스트가 최종 답변 → 종료.
            guard let tool = pendingTool else { return }

            // [v0.2 M4] tool 라우팅 — name 으로 분기. save_memory 는 즉시 저장, 그 외(web_search)는 검색.
            let resultText: String
            if tool.name == ToolDefinition.saveMemory.name {
                // 명시 저장 — verified=1 즉시 INSERT(§4). 취소 체크 후 회신.
                resultText = await runSaveMemory(inputJSON: tool.inputJSON)
                try Task.checkCancellation()
            } else {
                // 웹검색 경로(기존 §4 — 변경 없음).
                let query = Self.queryFromInput(tool.inputJSON)
                state = .searching(query)

                if let cached = searchCache[query] {
                    resultText = cached   // 동일 query 재사용(재검색 안 함, §4).
                } else {
                    let fetched: String
                    do {
                        let results = try await searchService.search(query: query, apiKey: store.tavilyAPIKey)
                        try Task.checkCancellation()
                        fetched = TavilySearchService.formatResults(results)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let e as ClientError where e == .cancelled {
                        throw CancellationError()
                    } catch {
                        // 검색 실패 → 오류 문구를 tool_result 로 모델에 전달(§4 — 모델이 폴백 답변).
                        let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
                        fetched = "검색 실패: \(reason)"
                    }
                    searchCache[query] = fetched
                    resultText = fetched
                }
            }

            // 라운드 내부 휘발 컨텍스트에만 tool 쌍 append(영속 히스토리 제외, §4).
            wireContext.append(.init(role: "assistant", blocks: [
                .toolUse(id: tool.id, name: tool.name, inputJSON: tool.inputJSON)
            ]))
            wireContext.append(.init(role: "user", blocks: [
                .toolResult(toolUseID: tool.id, content: resultText)
            ]))
            // 다음 라운드 진입 전 상태(분석 대기) 복귀.
            state = .ingesting
        }
        // 루프를 다 돌았는데도 답변이 비어 있으면(연속 tool_use) 안내(방어).
        if reply.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reply.content = "검색을 여러 번 시도했지만 최종 답변을 만들지 못했어요. 질문을 조금 더 구체적으로 입력해 주세요."
            applyReply(reply)
        }
    }

    /// tool_use input JSON 에서 query 문자열 추출(파싱 실패 시 빈 문자열).
    private static func queryFromInput(_ inputJSON: String) -> String {
        guard let data = inputJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let q = obj["query"] as? String else { return "" }
        return q
    }

    // MARK: - [v0.2 M3] 회상 검색·주입(§4 읽기 경로 / M-D9·9'·10·14)

    /// 입력 텍스트로 장기 기억을 검색해 system 가변부(recalledMemoryBlock)에 주입한다.
    /// - 임베딩(짧은 race 타임아웃) → searchByEmbedding. 실패/무임베딩이면 LIKE 폴백. 둘 다 실패면 무주입.
    /// - 동주제 dedup(M-D9' — pairwise 코사인 ≥ θ_topic 이면 최신 1건). 3~5건 주입. 0건이면 블록 생략.
    /// - 주입 대상 last_accessed 세션당 1회 갱신(M-D14 — accessedThisSession 으로 중복 방지).
    private func recallAndInjectMemory(for text: String) async {
        recalledMemoryBlock = nil   // 매 send 초기화(이전 회상 잔존 방지)

        // 빠른 경로: 기억이 아예 없으면 검색 생략(0건 → 블록 생략).
        guard !memoryStore.all().isEmpty else { return }

        // 1) 임베딩 검색(짧은 race) → 실패 시 LIKE 폴백.
        var candidates: [Memory] = []
        if let queryVector = await embedWithRace(text) {
            candidates = memoryStore.searchByEmbedding(query: queryVector)
                .filter { $0.score > 0 }       // 임베딩 0(무관/무임베딩) 제외
                .prefix(memoryInjectMax * 2)   // dedup 여유분
                .map(\.memory)
        }
        if candidates.isEmpty {
            // LIKE 폴백 — 입력에서 2자 이상 토큰으로 매칭(공백 분리, 한국어 부분일치).
            candidates = keywordFallback(for: text)
        }
        guard !candidates.isEmpty else { return }

        // 2) 동주제 dedup(M-D9' — pairwise 코사인 ≥ θ_topic 이면 최신 1건만).
        let deduped = dedupByTopic(candidates)

        // 3) 상위 N(3~5) 주입.
        let chosen = Array(deduped.prefix(memoryInjectMax))
        guard !chosen.isEmpty else { return }
        recalledMemoryBlock = Self.memoryBlockText(chosen)

        // 4) last_accessed 세션당 1회 갱신(M-D14).
        for m in chosen where !accessedThisSession.contains(m.id) {
            memoryStore.touchLastAccessed(id: m.id)
            accessedThisSession.insert(m.id)
        }
    }

    /// 입력 임베딩을 짧은 타임아웃 race 로 시도(실패/타임아웃이면 nil → 호출측 LIKE 폴백).
    /// send 를 0.5s 이상 지연시키지 않기 위한 가드(embedRaceTimeout).
    private func embedWithRace(_ text: String) async -> [Float]? {
        guard let embedding else { return nil }
        return await withTaskGroup(of: [Float]?.self) { group in
            group.addTask { try? await embedding.embedQuery(text) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(self.embedRaceTimeout * 1_000_000_000))
                return nil
            }
            // 먼저 끝난 쪽 채택(임베딩 성공이면 벡터, 타임아웃이면 nil).
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// LIKE 폴백 — 입력에서 2자 이상 단어 토큰으로 OR 검색 후 중복 제거(최신순 유지).
    private func keywordFallback(for text: String) -> [Memory] {
        // 한글·영숫자는 alphanumerics 에 포함 → 그 외(공백·문장부호)로 분리. 2자 이상 토큰만(M-D4 2자 부분일치).
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        let queryTokens = tokens.isEmpty ? [text.trimmingCharacters(in: .whitespacesAndNewlines)] : tokens

        var seen = Set<String>()
        var out: [Memory] = []
        for token in queryTokens {
            for m in memoryStore.searchByKeyword(query: token) where !seen.contains(m.id) {
                seen.insert(m.id)
                out.append(m)
            }
        }
        return out
    }

    /// 동주제 dedup(M-D9') — 입력 순서(점수/최신 우선) 유지하며, 이미 채택된 것과 코사인 ≥ θ_topic 이면 제외.
    /// 임베딩 없는 항목은 dedup 비교 불가 → 그대로 통과(텍스트 동일성까진 안 봄 — 단순 룰).
    private func dedupByTopic(_ items: [Memory]) -> [Memory] {
        var kept: [Memory] = []
        for m in items {
            if let v = m.embedding {
                let dup = kept.contains { other in
                    guard let ov = other.embedding else { return false }
                    return memoryStore.cosine(v, ov) >= thetaTopic
                }
                if dup { continue }
            }
            kept.append(m)
        }
        return kept
    }

    /// 주입용 텍스트 블록(M-D10 형식 — type, yyyy-MM).
    private static func memoryBlockText(_ memories: [Memory]) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM"
        let lines = memories.map { m -> String in
            "- \(m.text) (\(m.type), \(df.string(from: m.createdAt)))"
        }
        return "[사용자에 대한 기억]\n" + lines.joined(separator: "\n")
    }

    // MARK: - [v0.2 M4] save_memory tool 실행(§4 명시 저장 — verified=1)

    /// save_memory tool_use input(JSON)을 파싱해 즉시 INSERT(verified=1)하고 tool_result 텍스트를 만든다.
    /// text 필수(없으면 안내). type 기본 "사실", importance 기본 7. 문서측 임베딩 시도(실패 NULL).
    private func runSaveMemory(inputJSON: String) async -> String {
        guard let data = inputJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawText = obj["text"] as? String,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "기억할 내용을 찾지 못했습니다. 무엇을 기억할지 알려 주세요."
        }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // type 정규화(표준 4종 외 → 사실). importance 1~10 클램프(누락 7).
        let rawType = (obj["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let type = MemoryType.allCases.map(\.rawValue).contains(rawType) ? rawType : MemoryType.fact.rawValue
        let importance: Int = {
            if let i = obj["importance"] as? Int { return min(max(i, 1), 10) }
            if let d = obj["importance"] as? Double { return min(max(Int(d), 1), 10) }
            return 7
        }()

        // 문서측 임베딩(실패 시 NULL — LIKE 폴백 대상).
        var vector: [Float]? = nil
        if let embedding {
            vector = try? await embedding.embedDocument(text)
        }

        memoryStore.insert(Memory(
            text: text, embedding: vector, type: type, importance: importance,
            source: "user_explicit", verified: true   // 사용자 명시 → 검토 불요(M-D8)
        ))
        return "기억했습니다: \(text)"
    }

    /// state 가 .generating 인지(연관값 없는 비교 헬퍼).
    private func isGenerating(_ s: ChatState) -> Bool {
        if case .generating = s { return true }
        return false
    }

    private func applyReply(_ reply: ChatTurn) {
        if let i = messages.lastIndex(where: { $0.id == reply.id }) {
            messages[i] = reply
        }
    }

    private func handleFailure(_ error: ClientError, replyID: UUID) {
        // 빈 assistant 응답이면 제거(빈 말풍선 방지).
        if let i = messages.lastIndex(where: { $0.id == replyID }), messages[i].content.isEmpty {
            messages.remove(at: i)
        }
        store.saveSession(messages)
        state = (error == .cancelled) ? .cancelled : .failed(error.errorDescription ?? "알 수 없는 오류")
    }

    // MARK: - 취소(§8.5)

    func cancel() {
        task?.cancel()   // onTermination → URLSession 작업 취소로 전파
    }

    // MARK: - 새 대화(Phase 8 + v0.2 M2 직전 세션 요약)

    func newChat() {
        // [v0.2 M2] 비우기 전에 transcript 스냅샷을 떠서 비동기 요약(fire-and-forget).
        //   즉시성(대화 비우기)은 절대 지연시키지 않는다 — 스냅샷 후 곧바로 클리어, 요약은 뒤에서.
        let snapshot = messages
        summarizeLastSession(snapshot: snapshot)

        // [v0.2 M3] 동일 스냅샷을 pending 큐에 동기 기록(1단) 후 큐 처리 fire-and-forget(2단).
        //   비우기 직전 시점이 대화 경계(§3) — transcript 가 비지 않을 때만 큐잉.
        enqueuePendingFromSnapshot(snapshot)
        Task { [weak self] in await self?.extractor.processQueue() }

        cancel()
        task = nil
        messages.removeAll()
        input = ""
        state = .idle
        store.clearSession()

        // [v0.2 M2] 대화 내 누적 요약 상태 초기화(새 대화이므로 연속성 리셋).
        conversationSummary = nil
        lastSummarizedCount = 0
        summaryTask?.cancel()
        summaryTask = nil

        // [v0.2 M3] 회상 상태 초기화(새 세션 — last_accessed 세션당 1회 카운트·주입 블록 리셋).
        accessedThisSession.removeAll()
        recalledMemoryBlock = nil
    }

    // MARK: - [v0.2 M3] pending 큐 트리거

    /// 스냅샷(user/assistant 턴)을 사용자 발화 중심 transcript 로 만들어 큐에 동기 기록(§3 1단).
    /// 빈 대화/사용자 발화 없음이면 큐잉 생략.
    private func enqueuePendingFromSnapshot(_ snapshot: [ChatTurn]) {
        let turns = snapshot.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard turns.contains(where: { $0.isUser }) else { return }
        extractor.enqueue(transcript: Self.transcriptText(turns))
    }

    /// 앱 시작/포그라운드 복귀 시 큐 처리(ChatView .onAppear 훅에서 호출). 동시 실행 가드는 extractor 가.
    func processMemoryQueueIfNeeded() {
        guard memoryStore.pendingCount() > 0 else { return }
        Task { [weak self] in await self?.extractor.processQueue() }
    }

    // MARK: - [Phase W3 — 세션 격리(수술 M2)] 브리핑에서 이어서 대화

    /// 브리핑 "이어서 대화하기" — 기존 대화를 비우고(newChat) user/assistant 2턴을 시드한다(§5).
    /// Anthropic 첫 턴 user 규칙을 지키려 user("오늘 아침 브리핑 해줘") + assistant(브리핑) 순서로 둔다.
    /// 기존 히스토리와 상호 오염되지 않도록 반드시 newChat() 후 시드한다.
    func seedFromBriefing(_ text: String) {
        newChat()
        messages = [
            ChatTurn(role: "user", content: "오늘 아침 브리핑 해줘"),
            ChatTurn(role: "assistant", content: text),
        ]
        store.saveSession(messages)
    }

    // MARK: - [v0.2 M2] 세션 요약 헬퍼

    /// 직전 세션 요약(newChat 시 호출) — 스냅샷을 떠서 fire-and-forget 으로 LLM 1콜 요약 후 store 저장.
    /// 비어 있으면 생략. 실패는 조용히 무시(다음 기회). 본 newChat 흐름을 절대 막지 않는다(스냅샷 값 캡처).
    private func summarizeLastSession(snapshot: [ChatTurn]) {
        let turns = snapshot.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard turns.count >= 2 else { return }   // user+assistant 최소 1쌍 없으면 요약 의미 없음

        // ChatTurn 생성은 MainActor 컨텍스트(여기)에서 — detached Task 안에서 만들면 격리 경고.
        let user = ChatTurn(role: "user", content: Self.transcriptText(turns))
        let client = self.client
        let store = self.store
        let maxTokens = self.summaryMaxTokens

        // 본 흐름과 독립된 Task(취소 전파 불요 — 실패·미완료 시 그냥 미저장).
        Task.detached(priority: .utility) {
            let system = "다음 대화를 2~3문장으로 요약하라. 사용자가 한 말·결정·진행 중인 일 중심으로, 한국어로 간결하게 쓴다. 군더더기 없이 요약만 출력한다."
            guard let summary = try? await client.send(messages: [user], system: system, maxTokens: maxTokens).text else { return }
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            await MainActor.run { store.saveLastSessionSummary(trimmed) }
        }
    }

    /// 윈도우 초과 시 잘려나간 구간을 비동기로 재귀 요약(대화 내 연속성).
    /// 메시지 수가 historyWindow 를 처음 초과하는 시점부터, 윈도우 밖으로 밀려난 완료 턴들을 요약 대상으로 삼는다.
    /// 기존 conversationSummary(있으면) + 새로 잘린 턴 → 갱신 요약(재귀). 스트리밍과 경합 없게 별도 Task.
    private func maybeSummarizeOverflow() {
        // 완료(비어있지 않은) 턴 목록 — in-flight 빈 assistant 는 자동 제외(공백 필터).
        let completed = messages.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // 윈도우 밖으로 밀려난(=요약 대상) 턴 경계: 앞쪽 (completed.count - historyWindow) 개.
        let boundary = completed.count - historyWindow
        guard boundary > lastSummarizedCount else { return }   // 새로 잘린 턴이 없으면 스킵

        // 이번에 새로 잘려나간 구간(이전 요약 경계 ~ 새 경계).
        let newlyDropped = Array(completed[lastSummarizedCount..<boundary])
        guard !newlyDropped.isEmpty else { return }

        // 이미 요약 Task 가 진행 중이면 중복 트리거 방지(다음 send 에서 다시 시도).
        guard summaryTask == nil else { return }

        lastSummarizedCount = boundary   // 경계를 먼저 전진(중복 요약 방지). 실패해도 다음 기회 갱신.
        let prior = conversationSummary
        let droppedText = Self.transcriptText(newlyDropped)
        let client = self.client
        let maxTokens = self.summaryMaxTokens

        summaryTask = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.summaryTask = nil } }
            var system = "다음은 한 대화의 일부다. 핵심을 2~4문장 한국어로 요약하라. 사용자가 한 말·결정·진행 중인 일 중심. 요약만 출력한다."
            var userText = droppedText
            if let prior, !prior.isEmpty {
                // 재귀: 기존 요약 + 새로 잘린 턴 → 통합 갱신 요약.
                system = "기존 요약과 새 대화 구간을 통합해 2~4문장 한국어로 갱신 요약하라. 사용자가 한 말·결정·진행 중인 일 중심. 요약만 출력한다."
                userText = "[기존 요약]\n\(prior)\n\n[새 대화 구간]\n\(droppedText)"
            }
            let user = ChatTurn(role: "user", content: userText)
            guard let summary = try? await client.send(messages: [user], system: system, maxTokens: maxTokens).text else { return }
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            await MainActor.run { [weak self] in self?.conversationSummary = trimmed }
        }
    }

    /// 턴 배열 → "역할: 내용" 줄들의 transcript 텍스트(요약 입력용).
    private static func transcriptText(_ turns: [ChatTurn]) -> String {
        turns.map { turn in
            let speaker = turn.isUser ? "사용자" : "비서"
            return "\(speaker): \(turn.content)"
        }.joined(separator: "\n")
    }

    // MARK: - 오류 배너 닫기

    func dismissError() {
        if case .failed = state { state = .idle }
        if case .cancelled = state { state = .idle }
    }
}
