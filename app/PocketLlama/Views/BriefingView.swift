//
//  BriefingView.swift
//  PocketLlama
//
//  [Phase W3 — 브리핑 시트] 날씨 요약 칩(원자료)+브리핑 카드(스트리밍)+새로고침+이어서 대화+폴백(§5).
//  - 날씨 칩은 LLM 무관 원자료(SF Symbol·기온·최고/최저·강수확률).
//  - 브리핑 카드는 MarkdownMessageView 재사용(스트리밍 표시).
//  - failed 상태별 폴백 UI + 재시도. "이어서 대화하기"는 콜백으로 ChatViewModel.seedFromBriefing.
//

import SwiftUI

struct BriefingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var viewModel: BriefingViewModel
    /// "이어서 대화하기" — 브리핑 텍스트를 채팅 세션에 시드(세션 격리 M2). 시트는 닫는다.
    var onContinue: (String) -> Void
    /// 닫기 콜백.
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.l) {
                    greetingHeader
                    if let weather = viewModel.weather {
                        weatherChip(weather)
                    }
                    contentArea
                }
                .padding(theme.spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // [DesignSystem] 시그니처 화면 — 아침 새벽빛 배경.
            .plScreenBackground()
            .navigationTitle("아침 브리핑")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .onAppear {
            // 시트가 처음 뜰 때 idle 이면 생성 시작(캐시 우선, force=false).
            if viewModel.phase == .idle { viewModel.generate(force: false) }
        }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - 시그니처 인사 헤더(시각 장식 — 새 데이터 없음)

    /// "포켓 속 라마, 아침의 따뜻함" — 새벽빛 글리프 + 인사. 브리핑 화면의 시그니처 모먼트.
    private var greetingHeader: some View {
        HStack(spacing: theme.spacing.m) {
            ZStack {
                Circle()
                    .fill(LinearGradient.plMorning.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "sun.haze.fill")
                    .font(.title2)
                    .foregroundStyle(LinearGradient.plMorning)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text("좋은 아침이에요")
                    .font(.plTitle)
                    .foregroundStyle(.plTextPrimary)
                Text("오늘 하루를 함께 시작해요")
                    .font(.plCaption)
                    .foregroundStyle(.plTextSecondary)
            }
            Spacer()
        }
    }

    // MARK: - 날씨 칩(원자료 — LLM 무관)

    private func weatherChip(_ w: WeatherToday) -> some View {
        HStack(spacing: theme.spacing.l) {
            // 새벽빛 원반 위 날씨 심볼 — 시그니처 디테일.
            ZStack {
                Circle()
                    .fill(LinearGradient.plMorning.opacity(0.14))
                    .frame(width: 60, height: 60)
                Image(systemName: w.sfSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 32))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                HStack(spacing: theme.spacing.xs + 2) {
                    Text(w.cityName).font(.plHeadline).foregroundStyle(.plTextPrimary)
                    Text(w.description).font(.plCaption).foregroundStyle(.plTextSecondary)
                }
                Text("\(temp(w.temperature)) (체감 \(temp(w.apparentTemperature)))")
                    .font(.plTitle)
                HStack(spacing: theme.spacing.m) {
                    Label("\(temp(w.highTemperature))", systemImage: "arrow.up")
                        .foregroundStyle(.plWeatherHigh)
                    Label("\(temp(w.lowTemperature))", systemImage: "arrow.down")
                        .foregroundStyle(.plWeatherLow)
                    if let pop = w.precipitationProbability {
                        Label("\(pop)%", systemImage: "umbrella")
                            .foregroundStyle(.plWeatherPop)
                    }
                }
                .font(.plCaption)
                .fontWeight(.medium)
            }
            Spacer()
        }
        .signatureCardStyle()
    }

    // MARK: - 본문(상태별)

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.phase {
        case .idle, .fetchingWeather:
            HStack(spacing: theme.spacing.m) {
                ProgressView()
                Text(viewModel.phase == .fetchingWeather ? "지금 날씨를 가져오는 중…" : "준비 중…")
                    .font(.plBody)
                    .foregroundStyle(.plTextSecondary)
            }
            .padding(.vertical, theme.spacing.s)

        case .generating, .done:
            briefingCard
            doneActions

        case .failed(let reason):
            failureView(reason)
        }
    }

    private var briefingCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.xs + 2) {
                Image(systemName: "text.quote").foregroundStyle(.plWarmAccent)
                Text("오늘의 브리핑").font(.plHeadline).foregroundStyle(.plTextPrimary)
                if viewModel.loadedFromCache {
                    Text("· 저장됨").font(.plCaption2).foregroundStyle(.plTextSecondary)
                }
                Spacer()
                if viewModel.phase == .generating {
                    ProgressView().controlSize(.small)
                }
            }
            MarkdownMessageView(content: viewModel.briefingText.isEmpty ? " " : viewModel.briefingText)
                .font(.plBody)
                .foregroundStyle(.plTextPrimary)
                .textSelection(.enabled)
        }
        .signatureCardStyle()
    }

    // MARK: - 실패 폴백(§5)

    @ViewBuilder
    private func failureView(_ reason: BriefingViewModel.Phase.Reason) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            switch reason {
            case .weather:
                Label("날씨 정보를 가져오지 못했어요", systemImage: "cloud.slash")
                    .font(.plHeadline).foregroundStyle(.plWarmAccent)
                Text("네트워크를 확인하고 다시 시도해 주세요.")
                    .font(.plBody).foregroundStyle(.plTextSecondary)
                if !viewModel.briefingText.isEmpty {
                    // 캐시가 있으면 함께 노출.
                    Divider()
                    Text("최근 저장된 브리핑").font(.plCaption).foregroundStyle(.plTextSecondary)
                    MarkdownMessageView(content: viewModel.briefingText)
                        .font(.plBody)
                        .foregroundStyle(.plTextPrimary)
                }
            case .llm:
                Label("브리핑 생성에 실패했어요", systemImage: "exclamationmark.bubble")
                    .font(.plHeadline).foregroundStyle(.plWarmAccent)
                Text("날씨 정보는 위에서 확인할 수 있어요. 서버 연결을 확인하고 다시 시도해 주세요.")
                    .font(.plBody).foregroundStyle(.plTextSecondary)
            }
            Button {
                Haptics.tap()
                viewModel.generate(force: true)
            } label: {
                Label("다시 시도", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(.plAccentFill)
        }
        .cardStyle()
    }

    // MARK: - 완료 액션(새로고침 / 이어서 대화)

    @ViewBuilder
    private var doneActions: some View {
        if viewModel.phase == .done {
            VStack(spacing: theme.spacing.m) {
                Button {
                    Haptics.tap()
                    onContinue(viewModel.briefingText)
                } label: {
                    Label("이어서 대화하기", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.plHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.spacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .tint(.plAccentFill)

                Button {
                    Haptics.tap()
                    viewModel.generate(force: true)
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                        .font(.plBody)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.spacing.xxs)
                }
                .buttonStyle(.bordered)
                .tint(.plAccent)
            }
            .padding(.top, theme.spacing.xs)
        }
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            Button("닫기") { viewModel.cancel(); onClose() }
        }
        #else
        ToolbarItem {
            Button("닫기") { viewModel.cancel(); onClose() }
        }
        #endif
    }

    // MARK: - 헬퍼

    private func temp(_ v: Double) -> String { "\(Int(v.rounded()))℃" }
}
