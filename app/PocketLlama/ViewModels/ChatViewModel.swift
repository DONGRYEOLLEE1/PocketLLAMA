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

    // MARK: - 전송(스트리밍, Phase 7 본선)

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

        state = .ingesting
        // 마지막(빈 assistant turn) 제외 + 슬라이딩 윈도우.
        var window = Array(messages.dropLast().suffix(historyWindow))
        // 윈도우가 assistant 로 시작하면 "첫 메시지는 user" 계약(§7.2) 위반 → 제거(400 방지).
        if window.first?.role == "assistant" { window.removeFirst() }

        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                for try await delta in self.client.stream(messages: window, system: self.systemPrompt, maxTokens: self.maxTokens) {
                    if self.state != .generating { self.state = .generating }
                    reply.content += delta
                    if let i = self.messages.lastIndex(where: { $0.id == reply.id }) {
                        self.messages[i] = reply
                    }
                }
                self.state = .idle
                self.store.saveSession(self.messages)
            } catch let error as ClientError {
                self.handleFailure(error, replyID: reply.id)
            } catch {
                self.handleFailure(.http(-1, error.localizedDescription), replyID: reply.id)
            }
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
