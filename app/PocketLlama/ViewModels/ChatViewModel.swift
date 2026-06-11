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

    init(client: LLMChatClient, store: AppSettingsStore, searchService: SearchServiceProtocol? = nil) {
        self.client = client
        self.store = store
        // 기본 구현체는 init 본문에서 생성(기본 인자식이 nonisolated 컨텍스트에서 평가되는 경고 회피).
        self.searchService = searchService ?? TavilySearchService()
        self.messages = store.loadSession()   // 최근 대화 복원(Phase 8)
    }

    /// [Phase T2] system 프롬프트 — 웹검색 지침 + 프로필 주입(§4). 키 없으면 검색 지침 생략.
    private var systemPrompt: String {
        var s = baseSystemPrompt
        if store.isWebSearchEnabled {
            s += "\n\n최신 정보·시세·뉴스·날씨 등 실시간성 질문에만 web_search 도구를 사용하세요. "
            s += "일반 지식·잡담에는 사용하지 마세요. 검색 결과로 답할 때는 출처를 마크다운 링크로 표기하세요."
        }
        // 프로필 주입(이름·소개 비면 생략).
        let name = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = store.userIntro.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty || !intro.isEmpty {
            var parts: [String] = []
            if !name.isEmpty { parts.append("이름: \(name)") }
            if !intro.isEmpty { parts.append("소개: \(intro)") }
            s += "\n\n[사용자 정보] " + parts.joined(separator: ", ")
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

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
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
            let tools: [ToolDefinition]? = (webEnabled && round < maxToolRounds - 1) ? [.webSearch] : nil

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

            // tool_use 수신 → 검색 수행 후 wireContext 에 왕복 회신 append(§4).
            let query = Self.queryFromInput(tool.inputJSON)
            state = .searching(query)

            let resultText: String
            if let cached = searchCache[query] {
                resultText = cached   // 동일 query 재사용(재검색 안 함, §4).
            } else {
                do {
                    let results = try await searchService.search(query: query, apiKey: store.tavilyAPIKey)
                    try Task.checkCancellation()
                    resultText = TavilySearchService.formatResults(results)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let e as ClientError where e == .cancelled {
                    throw CancellationError()
                } catch {
                    // 검색 실패 → 오류 문구를 tool_result 로 모델에 전달(§4 — 모델이 폴백 답변).
                    let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
                    resultText = "검색 실패: \(reason)"
                }
                searchCache[query] = resultText
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

    // MARK: - 새 대화(Phase 8)

    func newChat() {
        cancel()
        task = nil
        messages.removeAll()
        input = ""
        state = .idle
        store.clearSession()
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

    // MARK: - 오류 배너 닫기

    func dismissError() {
        if case .failed = state { state = .idle }
        if case .cancelled = state { state = .idle }
    }
}
