//
//  ChatView.swift
//  PocketLlama
//
//  Phase 6~8 채팅 본선.
//  - 메시지 리스트 + 자동 스크롤(ScrollViewReader)
//  - 입력/전송 + Cancel(상태 머신 §8.4 / §8.5)
//  - 상태 안내(.ingesting 등) / 에러 배너 / 빈 상태 / 새 대화 / 모델 표시
//

import SwiftUI

struct ChatView: View {
    @Bindable var settings: AppSettingsStore
    let baseURL: URL

    @State private var viewModel: ChatViewModel
    @State private var client: AnthropicChatClient
    @State private var showSettings = false

    init(settings: AppSettingsStore, baseURL: URL) {
        self.settings = settings
        self.baseURL = baseURL
        let client = AnthropicChatClient(
            baseURL: baseURL,
            apiKey: settings.apiKey.isEmpty ? nil : settings.apiKey
        )
        _client = State(initialValue: client)
        _viewModel = State(initialValue: ChatViewModel(client: client, store: settings))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                statusBar
                errorBanner
                inputBar
            }
            .navigationTitle("PocketLlama")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) {
                ModelInfoView(client: client)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(settings: settings, onDone: { showSettings = false })
                }
            }
        }
    }

    // MARK: - 메시지 리스트 + 자동 스크롤

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { turn in
                            MessageBubble(turn: turn)
                                .id(turn.id)
                        }
                        // 스크롤 앵커.
                        Color.clear.frame(height: 1).id(scrollAnchor)
                    }
                    .padding()
                }
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private let scrollAnchor = "bottom-anchor"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(scrollAnchor, anchor: .bottom)
        }
    }

    // MARK: - 빈 상태(Phase 8)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("대화를 시작해 보세요")
                .font(.headline)
            Text("맥북에서 작동 중인 로컬 LLM 과 채팅합니다.\n첫 응답은 모델이 커서 다소 느릴 수 있어요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal)
    }

    // MARK: - 상태 표시(§8.4)

    @ViewBuilder
    private var statusBar: some View {
        if let notice = viewModel.state.notice {
            HStack(spacing: 8) {
                if viewModel.state.isBusy {
                    ProgressView()
                }
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .transition(.opacity)
        }
    }

    // MARK: - 에러 배너(Phase 8)

    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.state.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    viewModel.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(Color.red.opacity(0.9))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - 입력/전송/Cancel(§8.5)

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("메시지를 입력하세요", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(viewModel.state.isBusy)
                .onSubmit { if viewModel.canSend { viewModel.send() } }

            if viewModel.state.isBusy {
                Button {
                    viewModel.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("취소")
            } else {
                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(viewModel.canSend ? Color.accentColor : Color.secondary)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("전송")
            }
        }
        .padding()
    }

    // MARK: - 툴바(새 대화 / 설정)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button {
                viewModel.newChat()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .disabled(viewModel.isEmpty && !viewModel.state.isBusy)
            .accessibilityLabel("새 대화")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("설정")
        }
        #else
        ToolbarItem {
            Button {
                viewModel.newChat()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .disabled(viewModel.isEmpty && !viewModel.state.isBusy)
        }
        ToolbarItem {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        #endif
    }
}

// MARK: - 메시지 말풍선

private struct MessageBubble: View {
    let turn: ChatTurn

    var body: some View {
        HStack {
            if turn.isUser { Spacer(minLength: 40) }
            Text(turn.content.isEmpty ? " " : turn.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(turn.isUser ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.18))
                .foregroundStyle(turn.isUser ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .textSelection(.enabled)
            if !turn.isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: turn.isUser ? .trailing : .leading)
    }
}
