//
//  SettingsView.swift
//  PocketLlama
//
//  Phase 3(설정) + Phase 4(연결 테스트) + Phase 5(모델 표시).
//  - base URL / apiKey 는 draft 로 편집하고 "완료" 시에만 store 에 커밋한다.
//    (입력 도중 store 가 바뀌면 RootView 분기·ChatView .id 재생성이 트리거되어
//     화면이 채팅으로 튕기거나 설정 시트가 닫히는 버그가 난다.)
//  - GET /health 연결 테스트 + 에러 분류 / GET /v1/models 모델 표시(실패 시 fallback)
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme

    @Bindable var settings: AppSettingsStore
    /// 채팅에서 시트로 열렸을 때 닫기 콜백(루트에서 열리면 nil).
    var onDone: (() -> Void)? = nil

    // 편집용 draft. store 는 commit() 에서만 갱신한다(입력 도중 화면 튕김 방지).
    @State private var draftURL: String = ""
    @State private var draftAPIKey: String = ""
    @State private var draftUseStreaming: Bool = false
    // [Phase W2] 브리핑/프로필/웹검색 draft. commit() 에서만 store 반영(튕김·중복예약 방지).
    @State private var draftBriefingEnabled: Bool = false
    @State private var draftBriefingTime: Date = Date()   // .hourAndMinute 만 사용
    @State private var draftCity: KoreanCity = .seoul
    @State private var draftUserName: String = ""
    @State private var draftUserIntro: String = ""
    @State private var draftTavilyKey: String = ""
    @State private var loaded = false

    // [Phase W2] 토글 on 시 권한 거부 안내.
    @State private var notificationDenied = false

    @State private var connectionState: ConnectionState = .idle
    @State private var modelName: String?
    @State private var testTask: Task<Void, Never>?

    enum ConnectionState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    private var validationMessage: String? { ServerURL.validationMessage(draftURL) }
    private var isValid: Bool { validationMessage == nil }
    private var draftBaseURL: URL? { ServerURL.normalize(draftURL) }

    var body: some View {
        Form {
            serverSection
            connectionSection
            apiKeySection
            responseSection
            briefingSection
            profileSection
            webSearchSection
            helpSection
        }
        // [DesignSystem] Form 동작(섹션 그룹·인셋)은 그대로 두고 배경만 보라 기운으로 통일 —
        // 다른 화면과 일관된 톤. scrollContentBackground 로 시스템 회색 그룹배경을 우리 토큰으로.
        .scrollContentBackground(.hidden)
        .background(Color.plBgPrimary.ignoresSafeArea())
        .navigationTitle("서버 설정")
        .toolbar {
            // 완료 = draft 를 store 에 커밋. 루트(onDone=nil)에서는 커밋만 해도
            // isConfigured 가 true 가 되어 RootView 가 채팅 화면으로 전환한다.
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button("완료") { commit() }.disabled(!isValid)
            }
            #else
            ToolbarItem(placement: .confirmationAction) {
                Button("완료") { commit() }.disabled(!isValid)
            }
            #endif
        }
        .onAppear {
            // 뷰가 동일 인스턴스로 재등장(re-appear)할 때 store 값으로 draft 를 덮어쓰지 않도록 최초 1회만 로드.
            guard !loaded else { return }
            draftURL = settings.baseURLString
            draftAPIKey = settings.apiKey
            draftUseStreaming = settings.useStreaming
            // [Phase W2] 브리핑/프로필/웹검색 draft 초기화.
            draftBriefingEnabled = settings.briefingEnabled
            draftBriefingTime = Self.dateFrom(hour: settings.briefingHour, minute: settings.briefingMinute)
            draftCity = settings.selectedCity
            draftUserName = settings.userName
            draftUserIntro = settings.userIntro
            draftTavilyKey = settings.tavilyAPIKey
            loaded = true
        }
        .onDisappear { testTask?.cancel() }
    }

    /// draft 를 store 에 반영(이때 비로소 RootView/ChatView 가 새 값을 본다).
    private func commit() {
        settings.baseURLString = draftURL
        settings.apiKey = draftAPIKey
        settings.useStreaming = draftUseStreaming
        // [Phase W2] 브리핑/프로필/웹검색 커밋.
        settings.briefingEnabled = draftBriefingEnabled
        let (h, m) = Self.hourMinute(from: draftBriefingTime)
        settings.briefingHour = h
        settings.briefingMinute = m
        settings.cityID = draftCity.rawValue
        settings.userName = draftUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.userIntro = draftUserIntro.trimmingCharacters(in: .whitespacesAndNewlines)
        // tavilyAPIKey setter 가 Keychain 에 저장(빈 값이면 삭제 → 웹검색 비활성).
        settings.tavilyAPIKey = draftTavilyKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // [Phase W2] 알림 재예약: 켜짐이면 권한 요청 후 schedule, 꺼짐이면 cancel.
        let enabled = draftBriefingEnabled
        Task {
            if enabled {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    NotificationManager.shared.scheduleDaily(hour: h, minute: m)
                    notificationDenied = false
                } else {
                    // 권한 거부 → 토글은 켰어도 예약 불가. store 토글은 사용자 의도 보존하되 안내.
                    notificationDenied = true
                }
            } else {
                NotificationManager.shared.cancelDaily()
                notificationDenied = false
            }
        }
        onDone?()
    }

    // MARK: - [Phase W2] 시:분 ↔ Date 변환 헬퍼(DatePicker .hourAndMinute 용)

    private static func dateFrom(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func hourMinute(from date: Date) -> (Int, Int) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 8, comps.minute ?? 0)
    }

    // MARK: - 섹션

    private var serverSection: some View {
        Section {
            TextField("http://192.168.0.10:8080", text: $draftURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: draftURL) { _, _ in
                    // 주소가 바뀌면 이전 테스트 결과 무효화.
                    connectionState = .idle
                    modelName = nil
                }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.plCaption)
                    .foregroundStyle(.plWarmAccent)
            } else if let url = draftBaseURL {
                Label("연결 대상: \(url.absoluteString)", systemImage: "link")
                    .font(.plCaption)
                    .foregroundStyle(.plTextSecondary)
            }
        } header: {
            Text("서버 주소")
        } footer: {
            Text("맥북에서 작동 중인 llama-server 의 주소(base URL)만 입력하세요. /v1/messages 같은 경로는 앱이 자동으로 붙입니다.")
        }
    }

    private var connectionSection: some View {
        Section("연결") {
            Button {
                runConnectionTest()
            } label: {
                HStack {
                    Label("연결 테스트", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if connectionState == .testing {
                        ProgressView()
                    }
                }
            }
            .disabled(!isValid || connectionState == .testing)

            switch connectionState {
            case .idle:
                EmptyView()
            case .testing:
                Label("서버에 연결 중…", systemImage: "ellipsis.circle")
                    .foregroundStyle(.plTextSecondary)
            case .success:
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Label("연결 성공", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.plSuccess)
                    if let modelName {
                        Text("모델: \(modelName)")
                            .font(.plBody)
                            .foregroundStyle(.plTextSecondary)
                    } else {
                        // Phase 5 fallback: /health 는 되지만 /v1/models 실패.
                        Text("모델: (이름 미상) — 채팅은 가능합니다")
                            .font(.plBody)
                            .foregroundStyle(.plTextSecondary)
                    }
                }
            case .failure(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.plDanger)
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("(선택) API Key", text: $draftAPIKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } header: {
            Text("API Key (선택)")
        } footer: {
            Text("서버를 --api-key 로 보호한 경우에만 입력하세요. 무인증 LAN 환경이면 비워 두세요.")
        }
    }

    private var responseSection: some View {
        Section {
            Toggle("스트리밍 응답", isOn: $draftUseStreaming)
        } header: {
            Text("응답 방식")
        } footer: {
            Text("켜면 토큰을 받는 즉시 표시합니다(권장). 끄면 응답이 모두 완성된 뒤 한 번에 표시합니다.")
        }
    }

    // MARK: - [Phase W2] 아침 브리핑 섹션(토글·시간·도시 — draft, commit 에서 재예약)

    private var briefingSection: some View {
        Section {
            Toggle("매일 아침 브리핑", isOn: $draftBriefingEnabled)
            if draftBriefingEnabled {
                DatePicker(
                    "알림 시각",
                    selection: $draftBriefingTime,
                    displayedComponents: .hourAndMinute
                )
                Picker("도시", selection: $draftCity) {
                    ForEach(KoreanCity.allCases) { city in
                        Text(city.displayName).tag(city)
                    }
                }
            }
            if notificationDenied {
                Label("알림 권한이 거부되어 예약할 수 없습니다. 설정 > 알림에서 허용해 주세요.",
                      systemImage: "bell.slash")
                    .font(.plCaption)
                    .foregroundStyle(.plWarmAccent)
            }
        } header: {
            Text("아침 브리핑")
        } footer: {
            Text("켜면 매일 설정한 시각에 알림이 와요. 탭하면 그 시점 날씨로 브리핑을 만들어 드립니다. (완료를 눌러야 예약이 반영됩니다.)")
        }
    }

    // MARK: - [Phase W2] 프로필 섹션(이름·한 줄 소개 — system 주입용)

    private var profileSection: some View {
        Section {
            TextField("이름 (선택)", text: $draftUserName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            TextField("한 줄 소개 (선택)", text: $draftUserIntro, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        } header: {
            Text("프로필")
        } footer: {
            Text("입력하면 비서가 답변에 참고합니다. 비워 두면 사용하지 않아요.")
        }
    }

    // MARK: - [Phase W2] 웹 검색 섹션(Tavily 키 — draft, commit 시 Keychain 저장)

    private var webSearchSection: some View {
        Section {
            SecureField("Tavily API Key (선택)", text: $draftTavilyKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } header: {
            Text("웹 검색")
        } footer: {
            if draftTavilyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("키가 없으면 웹 검색이 비활성화됩니다. 최신 정보·시세·뉴스 질문에 답하려면 Tavily 키를 입력하세요.")
            } else {
                Text("최신 정보가 필요한 질문에 한해 비서가 웹을 검색합니다. 키는 기기 Keychain 에 안전하게 저장됩니다.")
            }
        }
    }

    private var helpSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("같은 Wi-Fi 에 연결되어 있어야 하며, 맥북 서버는 0.0.0.0 으로 떠 있어야 합니다.")
        }
    }

    // MARK: - 연결 테스트(§7.5 + fallback) — draft 기준으로 테스트한다.

    private func runConnectionTest() {
        guard let baseURL = draftBaseURL else {
            connectionState = .failure(ClientError.badURL.errorDescription ?? "주소 오류")
            return
        }
        testTask?.cancel()
        connectionState = .testing
        modelName = nil

        let client = AnthropicChatClient(
            baseURL: baseURL,
            apiKey: draftAPIKey.isEmpty ? nil : draftAPIKey
        )

        testTask = Task {
            do {
                let healthy = try await client.health()
                guard !Task.isCancelled else { return }
                guard healthy else {
                    connectionState = .failure("서버가 응답했지만 /health 가 200이 아닙니다.")
                    return
                }
                // health 성공 → 모델 조회 시도(실패해도 fallback).
                if let ids = try? await client.models(), let first = ids.first {
                    modelName = first
                } else {
                    modelName = nil
                }
                guard !Task.isCancelled else { return }
                connectionState = .success
            } catch let error as ClientError {
                guard !Task.isCancelled else { return }
                connectionState = .failure(error.errorDescription ?? "연결 실패")
            } catch {
                guard !Task.isCancelled else { return }
                connectionState = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(settings: AppSettingsStore())
    }
}
