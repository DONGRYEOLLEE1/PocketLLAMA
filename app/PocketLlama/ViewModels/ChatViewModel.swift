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
    private let historyWindow = 12   // 최근 N 메시지만 전송(§7.2 슬라이딩 윈도우)
    private let maxTokens = 1024
    private let systemPrompt = "You are a helpful assistant."

    init(client: LLMChatClient, store: AppSettingsStore) {
        self.client = client
        self.store = store
        self.messages = store.loadSession()   // 최근 대화 복원(Phase 8)
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

        let streaming = store.useStreaming

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                if streaming {
                    try await self.runStreaming(window: window, reply: &reply)
                } else {
                    try await self.runNonStreaming(window: window, reply: &reply)
                }
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

    /// 스트림 경로(Phase 7). 첫 delta 수신 시 .generating, .done(truncated:) 시 잘림 안내.
    private func runStreaming(window: [ChatTurn], reply: inout ChatTurn) async throws {
        // 요청/스트림 시작 직전: 프롬프트 분석 대기 단계.
        state = .ingesting
        for try await event in client.stream(messages: window, system: systemPrompt, maxTokens: maxTokens) {
            switch event {
            case .delta(let text):
                if state != .generating { state = .generating }
                reply.content += text
                applyReply(reply)
            case .done(let truncated):
                if truncated {
                    reply.content += Self.truncationNotice
                    applyReply(reply)
                }
            }
        }
    }

    /// 비스트림 경로(Phase 6). 응답을 한 번에 표시하고 잘림 시 안내를 덧붙인다.
    private func runNonStreaming(window: [ChatTurn], reply: inout ChatTurn) async throws {
        // 요청 시작 직전: 프롬프트 분석 대기 단계(비스트림은 응답이 한 번에 온다).
        state = .ingesting
        let completion = try await client.send(messages: window, system: systemPrompt, maxTokens: maxTokens)
        try Task.checkCancellation()
        state = .generating
        reply.content = completion.text + (completion.truncated ? Self.truncationNotice : "")
        applyReply(reply)
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

    // MARK: - 오류 배너 닫기

    func dismissError() {
        if case .failed = state { state = .idle }
        if case .cancelled = state { state = .idle }
    }
}
