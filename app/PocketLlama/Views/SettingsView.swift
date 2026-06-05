//
//  SettingsView.swift
//  PocketLlama
//
//  Phase 3(설정) + Phase 4(연결 테스트) + Phase 5(모델 표시).
//  - base URL 입력/검증(빈값·스킴·포트)/저장/복원
//  - GET /health 연결 테스트 + 에러 분류 표시
//  - GET /v1/models 모델 표시(실패 시 fallback)
//  - 선택적 API Key 입력
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettingsStore
    /// 채팅에서 시트로 열렸을 때 닫기 콜백(루트에서 열리면 nil).
    var onDone: (() -> Void)? = nil

    @State private var connectionState: ConnectionState = .idle
    @State private var modelName: String?
    @State private var testTask: Task<Void, Never>?

    enum ConnectionState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    private var validationMessage: String? {
        ServerURL.validationMessage(settings.baseURLString)
    }

    private var isValid: Bool { validationMessage == nil }

    var body: some View {
        Form {
            serverSection
            connectionSection
            apiKeySection
            responseSection
            helpSection
        }
        .navigationTitle("서버 설정")
        .toolbar {
            if let onDone {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { onDone() }.disabled(!isValid)
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { onDone() }.disabled(!isValid)
                }
                #endif
            }
        }
        .onDisappear { testTask?.cancel() }
    }

    // MARK: - 섹션

    private var serverSection: some View {
        Section {
            TextField("http://192.168.0.10:8080", text: $settings.baseURLString)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: settings.baseURLString) { _, _ in
                    // 주소가 바뀌면 이전 테스트 결과 무효화.
                    connectionState = .idle
                    modelName = nil
                }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let url = settings.baseURL {
                Label("연결 대상: \(url.absoluteString)", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            case .success:
                VStack(alignment: .leading, spacing: 4) {
                    Label("연결 성공", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let modelName {
                        Text("모델: \(modelName)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        // Phase 5 fallback: /health 는 되지만 /v1/models 실패.
                        Text("모델: (이름 미상) — 채팅은 가능합니다")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            case .failure(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("(선택) API Key", text: $settings.apiKey)
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
            Toggle("스트리밍 응답", isOn: $settings.useStreaming)
        } header: {
            Text("응답 방식")
        } footer: {
            Text("켜면 토큰을 받는 즉시 표시합니다(권장). 끄면 응답이 모두 완성된 뒤 한 번에 표시합니다.")
        }
    }

    private var helpSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("같은 Wi-Fi 에 연결되어 있어야 하며, 맥북 서버는 0.0.0.0 으로 떠 있어야 합니다.")
        }
    }

    // MARK: - 연결 테스트(§7.5 + fallback)

    private func runConnectionTest() {
        guard let baseURL = settings.baseURL else {
            connectionState = .failure(ClientError.badURL.errorDescription ?? "주소 오류")
            return
        }
        testTask?.cancel()
        connectionState = .testing
        modelName = nil

        let client = AnthropicChatClient(
            baseURL: baseURL,
            apiKey: settings.apiKey.isEmpty ? nil : settings.apiKey
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
