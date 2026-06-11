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
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase   // [v0.2 M3] 포그라운드 복귀 → 큐 처리

    @Bindable var settings: AppSettingsStore
    let baseURL: URL

    @State private var viewModel: ChatViewModel
    @State private var client: AnthropicChatClient
    @State private var showSettings = false

    // [Phase W3] 브리핑 시트 + 독립 BriefingViewModel(세션 격리 — 자체 클라이언트).
    @State private var briefingViewModel: BriefingViewModel
    @State private var showBriefing = false
    @State private var confirmSeedFromBriefing = false   // 기존 대화 있을 때 확인 다이얼로그
    @State private var pendingSeedText: String?
    @State private var router = NotificationRouter.shared
    @State private var autoBriefingChecked = false       // 하루 첫 진입 자동 1회 가드

    init(settings: AppSettingsStore, baseURL: URL) {
        self.settings = settings
        self.baseURL = baseURL
        let client = AnthropicChatClient(
            baseURL: baseURL,
            apiKey: settings.apiKey.isEmpty ? nil : settings.apiKey
        )
        _client = State(initialValue: client)
        // [v0.2 M3] 임베딩 클라이언트(채팅 host 재사용 + :8081). host 추출 실패 시 nil → LIKE 폴백.
        let embedding = EmbeddingClient(chatBaseURL: baseURL)
        _viewModel = State(initialValue: ChatViewModel(client: client, store: settings, embedding: embedding))

        // [Phase W3] 브리핑용 독립 클라이언트(세션 격리, §5) + Open-Meteo 날씨.
        let briefingClient = AnthropicChatClient(
            baseURL: baseURL,
            apiKey: settings.apiKey.isEmpty ? nil : settings.apiKey
        )
        _briefingViewModel = State(initialValue: BriefingViewModel(
            weatherService: OpenMeteoWeatherService(),
            client: briefingClient,
            store: settings
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                statusBar
                errorBanner
                inputBar
            }
            // [DesignSystem] 보라 기운 화면 배경 — 순백/순흑 탈피, 양 모드 깊이감.
            .plScreenBackground()
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
            // [Phase W3] 브리핑 시트(수동 ☀️ / 알림 탭 / 하루 첫 진입 자동).
            .sheet(isPresented: $showBriefing) {
                BriefingView(
                    viewModel: briefingViewModel,
                    onContinue: { text in handleContinue(text) },
                    onClose: { showBriefing = false }
                )
            }
            // [Phase W3] 기존 대화가 있을 때 "이어서 대화" 확인(세션 격리 안내).
            .confirmationDialog(
                "새 대화로 시작됩니다",
                isPresented: $confirmSeedFromBriefing,
                titleVisibility: .visible
            ) {
                Button("새 대화로 시작", role: .destructive) { commitSeed() }
                Button("취소", role: .cancel) { pendingSeedText = nil }
            } message: {
                Text("브리핑을 이어서 대화하면 지금까지의 대화는 사라집니다.")
            }
            // [Phase W3] 알림 탭 라우팅(M1): NotificationRouter 감지 → 브리핑 시트.
            .onChange(of: router.pendingBriefing) { _, pending in
                if pending {
                    router.pendingBriefing = false
                    showBriefing = true
                }
            }
            // [Phase W3] 하루 첫 진입 자동 브리핑(설정 켜짐 & 당일 캐시 없음 & 설정 진입 방해 금지).
            .onAppear {
                // 콜드 스타트 알림 탭: ChatView 가 뜨기 전에 router 가 이미 true 면 .onChange 가
                // 못 잡으므로 onAppear 에서 1회 소비한다(알림 라우팅 우선).
                if router.pendingBriefing {
                    router.pendingBriefing = false
                    showBriefing = true
                } else {
                    maybeAutoBriefing()
                }
                // [v0.2 M3] 앱 시작/화면 진입 시 pending 추출 큐 처리(유휴 멱등, §3 2단).
                viewModel.processMemoryQueueIfNeeded()
                #if DEBUG
                runE2EHooks()
                #endif
            }
            // [v0.2 M3] 포그라운드 복귀 시에도 큐 처리(중단 복구 — §3 멱등).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.processMemoryQueueIfNeeded() }
            }
        }
    }

    // MARK: - [Phase W3] 브리핑 라우팅/시드(세션 격리 M2)

    /// "이어서 대화하기" — 기존 대화가 있으면 확인, 비어 있으면 즉시 시드.
    private func handleContinue(_ text: String) {
        pendingSeedText = text
        showBriefing = false
        if viewModel.isEmpty {
            commitSeed()
        } else {
            confirmSeedFromBriefing = true
        }
    }

    private func commitSeed() {
        guard let text = pendingSeedText else { return }
        viewModel.seedFromBriefing(text)
        pendingSeedText = nil
    }

    /// 하루 첫 진입 자동 브리핑(1회). 설정 화면 진입은 방해하지 않음(showSettings 중엔 띄우지 않음).
    private func maybeAutoBriefing() {
        guard !autoBriefingChecked else { return }
        autoBriefingChecked = true
        guard settings.briefingEnabled, settings.isConfigured, !showSettings else { return }
        // 당일 캐시가 이미 있으면 자동으로 띄우지 않는다(§5 — 첫 진입 1회).
        let cache = settings.loadBriefingCache()
        if cache?.date == BriefingViewModel.todayKey() { return }
        showBriefing = true
    }

    // MARK: - 메시지 리스트 + 자동 스크롤

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: theme.spacing.m) {
                        ForEach(viewModel.messages) { turn in
                            MessageBubble(turn: turn)
                                .id(turn.id)
                                // [DesignSystem] 말풍선 등장 — reduce motion이면 페이드, 아니면 아래서 떠오름.
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .move(edge: .bottom).combined(with: .opacity)
                                )
                        }
                        // 스크롤 앵커.
                        Color.clear.frame(height: 1).id(scrollAnchor)
                    }
                    .padding(theme.spacing.l)
                    .animation(reduceMotion ? nil : theme.motion.spring, value: viewModel.messages.count)
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
        VStack(spacing: theme.spacing.l) {
            // [DesignSystem] 브랜드 모먼트 — 새벽빛 원반 위 라마 글리프.
            ZStack {
                Circle()
                    .fill(LinearGradient.plMorning.opacity(0.16))
                    .frame(width: 132, height: 132)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    // 순수 장식 글리프(아래 .accessibilityHidden) — 고정 크기 OK, 정보 전달 텍스트 아님.
                    .font(.system(size: 52))
                    .foregroundStyle(LinearGradient.plAccentSweep)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            Text("좋은 하루예요")
                .font(.plDisplay)
                .foregroundStyle(.plTextPrimary)
            Text("맥북의 라마와 조용히 대화해요.\n첫 응답은 모델이 커서 잠깐 느릴 수 있어요.")
                .font(.plBody)
                .foregroundStyle(.plTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.horizontal, theme.spacing.l)
        // reduce motion이면 페이드만, 아니면 아래에서 부드럽게 떠오른다.
        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
    }

    // MARK: - 상태 표시(§8.4)

    @ViewBuilder
    private var statusBar: some View {
        if let notice = viewModel.state.notice {
            // [DesignSystem] 검색 중(.searching)은 다른 상태와 외형으로 구분 — 돋보기 글리프 + 액센트 톤.
            let isSearching: Bool = { if case .searching = viewModel.state { return true } else { return false } }()
            HStack(spacing: theme.spacing.s) {
                if isSearching {
                    Image(systemName: "magnifyingglass")
                        .font(.plCaption)
                        .foregroundStyle(.plAccent)
                        .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                } else if viewModel.state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(notice)
                    .font(.plCaption)
                    .foregroundStyle(isSearching ? Color.plAccent : .plTextSecondary)
                    .fontWeight(isSearching ? .semibold : .regular)
                Spacer()
            }
            .padding(.horizontal, theme.spacing.l)
            .padding(.vertical, theme.spacing.s)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .overlay(alignment: .top) {
                // 상태바 상단 얇은 구분선 — 입력영역과 콘텐츠 경계를 부드럽게.
                Rectangle().fill(Color.plTextSecondary.opacity(0.12)).frame(height: 0.5)
            }
            .transition(.opacity)
        }
    }

    // MARK: - 에러 배너(Phase 8)

    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.state.errorMessage {
            // [DesignSystem] danger 토큰 + 흰 텍스트(대비 측정 PASS) + continuous 코너 + 그림자.
            HStack(alignment: .top, spacing: theme.spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(message)
                    .font(.plCaption)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    viewModel.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .frame(minWidth: 44, minHeight: 44)   // HIG 터치 타깃(글리프는 그대로, 탭 영역만 확장).
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("오류 닫기")
            }
            .padding(theme.spacing.m)
            .background(
                Color.plDanger,
                in: RoundedRectangle(cornerRadius: theme.radius.medium, style: .continuous)
            )
            .shadow(color: Color.plDanger.opacity(0.3), radius: 8, y: 3)
            .padding(.horizontal, theme.spacing.m)
            .padding(.bottom, theme.spacing.xs)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - 입력/전송/Cancel(§8.5)

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: theme.spacing.s) {
            // [DesignSystem] 입력 필드 — 캡슐형 elevated 표면 + 토큰 코너(시스템 roundedBorder 탈피).
            TextField("메시지를 입력하세요", text: $viewModel.input, axis: .vertical)
                .font(.plBody)
                .lineLimit(1...5)
                .disabled(viewModel.state.isBusy)
                .onSubmit { if viewModel.canSend { viewModel.send() } }
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, theme.spacing.s + 2)
                .background(
                    Color.plBgPrimary,
                    in: RoundedRectangle(cornerRadius: theme.radius.large, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.large, style: .continuous)
                        .strokeBorder(Color.plAccent.opacity(0.22), lineWidth: 1)
                )

            if viewModel.state.isBusy {
                Button {
                    viewModel.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.plDanger)
                        .symbolRenderingMode(.hierarchical)
                        .frame(minWidth: 44, minHeight: 44)   // HIG 터치 타깃.
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("취소")
            } else {
                Button {
                    Haptics.tap()
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(viewModel.canSend ? Color.plAccent : Color.plTextSecondary.opacity(0.5))
                        .symbolRenderingMode(.hierarchical)
                        // 보낼 수 있게 되는 순간 색이 부드럽게 살아난다(reduce motion이면 즉시).
                        .animation(reduceMotion ? nil : theme.motion.bouncy, value: viewModel.canSend)
                        .frame(minWidth: 44, minHeight: 44)   // HIG 터치 타깃.
                        .contentShape(Rectangle())
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("전송")
            }
        }
        .padding(theme.spacing.m)
        // 입력 영역을 살짝 떠 있는 elevated 바로 — 콘텐츠와 분리.
        .background(.bar)
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
            // [Phase W3] 브리핑 시트 수동 열기.
            Button {
                showBriefing = true
            } label: {
                Image(systemName: "sun.max")
            }
            .accessibilityLabel("아침 브리핑")
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
                showBriefing = true
            } label: {
                Image(systemName: "sun.max")
            }
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
    @Environment(\.theme) private var theme
    let turn: ChatTurn

    var body: some View {
        HStack {
            if turn.isUser { Spacer(minLength: theme.spacing.xxl + theme.spacing.s) }
            bubbleContent
                // [DesignSystem] 차별화 말풍선: user=보라 그라데이션+흰 텍스트+우하단 꼬리,
                // assistant=은은한 보라 표면+textPrimary+좌하단 꼬리. 외형만 토큰화(로직 동일).
                .font(.plBubble)
                .bubbleStyle(isUser: turn.isUser)
                .textSelection(.enabled)
            if !turn.isUser { Spacer(minLength: theme.spacing.xxl + theme.spacing.s) }
        }
        .frame(maxWidth: .infinity, alignment: turn.isUser ? .trailing : .leading)
    }

    // user 는 평문, assistant 는 마크다운 렌더.
    @ViewBuilder
    private var bubbleContent: some View {
        if turn.isUser {
            Text(turn.content.isEmpty ? " " : turn.content)
        } else {
            MarkdownMessageView(content: turn.content.isEmpty ? " " : turn.content)
        }
    }
}

// MARK: - [Phase Q — E2E] DEBUG 전용 드라이버 훅(릴리스 미포함)

#if DEBUG
extension ChatView {
    /// 런치 아규먼트 기반 E2E 시나리오 실행(실제 UI 파이프라인 경유 — E2EDriver.swift 참조).
    /// onAppear 재발화로 중복 실행되지 않도록 1회 가드.
    func runE2EHooks() {
        guard E2EDriver.isActive, !Self.e2eRan else { return }
        Self.e2eRan = true

        // 웹검색 비활성 강건성: 키 제거(이 세션 한정 — 다음 init 에서 Secrets 재시드됨).
        if E2EDriver.clearTavily {
            settings.tavilyAPIKey = ""
            E2EDriver.report("tavily-cleared isWebSearchEnabled=\(settings.isWebSearchEnabled)")
        }

        if E2EDriver.showSettings {
            showSettings = true
        }

        if let seconds = E2EDriver.notifAfterSeconds {
            Task { @MainActor in
                // 권한 요청은 비동기 발사(다이얼로그 응답 대기로 예약이 막히지 않게).
                Task { await NotificationManager.shared.requestAuthorization() }
                NotificationManager.shared.scheduleTest(after: seconds)
                E2EDriver.report("test-notif scheduled")
            }
        }

        if E2EDriver.scheduleDaily {
            Task { @MainActor in
                Task { await NotificationManager.shared.requestAuthorization() }
                NotificationManager.shared.scheduleDaily(hour: 8, minute: 0)
                let pending = await NotificationManager.shared.pendingSummary()
                E2EDriver.report("daily pending=\(pending.map { "\($0.hour):\($0.minute)" } ?? "none")")
            }
        }

        if let text = E2EDriver.sendText {
            Task { @MainActor in
                // 화면 안착 후 실제 전송 경로(send) 그대로 — canSend 게이트 포함.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                viewModel.input = text
                viewModel.send()
                E2EDriver.report("sent=\(text)")
            }
        }

        // [v0.2 M3 검증] 복원된 세션을 newChat → pending 큐 적재 + 추출 처리(쓰기 경로 그대로).
        if E2EDriver.newChatOnLaunch {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)   // 세션 복원 안착 대기
                viewModel.newChat()
                E2EDriver.report("newchat-triggered")
            }
        }
    }

    private static var e2eRan = false
}
#endif
