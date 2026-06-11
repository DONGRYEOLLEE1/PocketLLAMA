//
//  MemoryView.swift
//  PocketLlama
//
//  [v0.2 M3] 기억 관리 페이지(M-D8 — 투명 메모리). SettingsView 에서 NavigationLink 로 진입.
//  - 목록(최신순) · verified=0 "검토 필요" 배지 · 스와이프 물리 삭제 · 행 탭 → 편집 시트.
//  - 편집: 텍스트/타입/중요도/검토 토글. 텍스트 변경 시 재임베딩 시도(MemoryViewModel).
//  - DesignSystem 토큰(색·간격·타이포) 사용. 빈 상태 안내.
//

import SwiftUI

struct MemoryView: View {
    @Environment(\.theme) private var theme
    @State private var viewModel: MemoryViewModel
    @State private var editing: Memory?

    init(embedding: EmbeddingServiceProtocol? = nil) {
        _viewModel = State(initialValue: MemoryViewModel(embedding: embedding))
    }

    var body: some View {
        Group {
            if viewModel.memories.isEmpty {
                emptyState
            } else {
                memoryList
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.plBgPrimary.ignoresSafeArea())
        .navigationTitle("기억 관리")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { viewModel.reload() }
        .sheet(item: $editing) { memory in
            NavigationStack {
                MemoryEditSheet(memory: memory) { edited, textChanged in
                    Task {
                        await viewModel.update(edited, textChanged: textChanged)
                        editing = nil
                    }
                } onCancel: {
                    editing = nil
                }
            }
        }
    }

    // MARK: - 목록

    private var memoryList: some View {
        List {
            ForEach(viewModel.memories) { memory in
                Button {
                    editing = memory
                } label: {
                    MemoryRow(memory: memory)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.plBgElevated)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.delete(memory)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: theme.spacing.m) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundStyle(LinearGradient.plAccentSweep)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("아직 저장된 기억이 없어요")
                .font(.plHeadline)
                .foregroundStyle(.plTextPrimary)
            Text("대화에서 사용자에 대한 지속적인 사실이 자동으로 기억됩니다.\n\"…를 기억해 줘\" 라고 말해도 저장돼요.")
                .font(.plCaption)
                .foregroundStyle(.plTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(theme.spacing.xl)
    }
}

// MARK: - 행

private struct MemoryRow: View {
    @Environment(\.theme) private var theme
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(spacing: theme.spacing.s) {
                Text(memory.type)
                    .font(.plCaption2)
                    .foregroundStyle(.plAccent)
                    .padding(.horizontal, theme.spacing.s)
                    .padding(.vertical, theme.spacing.xxs)
                    .background(Color.plAccent.opacity(0.12), in: Capsule())
                if !memory.verified {
                    Label("검토 필요", systemImage: "exclamationmark.circle")
                        .font(.plCaption2)
                        .foregroundStyle(.plWarmAccent)
                }
                Spacer()
                Text(Self.shortDate(memory.createdAt))
                    .font(.plCaption2)
                    .foregroundStyle(.plTextSecondary)
            }
            Text(memory.text)
                .font(.plBody)
                .foregroundStyle(.plTextPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, theme.spacing.xxs)
        .contentShape(Rectangle())
    }

    private static func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy.MM.dd"
        return df.string(from: date)
    }
}

// MARK: - 편집 시트

private struct MemoryEditSheet: View {
    @Environment(\.theme) private var theme
    let memory: Memory
    let onSave: (Memory, _ textChanged: Bool) -> Void
    let onCancel: () -> Void

    @State private var draftText: String
    @State private var draftType: String
    @State private var draftImportance: Double
    @State private var draftVerified: Bool

    init(memory: Memory, onSave: @escaping (Memory, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.memory = memory
        self.onSave = onSave
        self.onCancel = onCancel
        _draftText = State(initialValue: memory.text)
        _draftType = State(initialValue: memory.type)
        _draftImportance = State(initialValue: Double(memory.importance))
        _draftVerified = State(initialValue: memory.verified)
    }

    var body: some View {
        Form {
            Section("내용") {
                TextField("기억 내용", text: $draftText, axis: .vertical)
                    .lineLimit(1...5)
            }
            Section("분류") {
                Picker("타입", selection: $draftType) {
                    ForEach(MemoryType.allCases, id: \.rawValue) { t in
                        Text(t.rawValue).tag(t.rawValue)
                    }
                    // 표준 외 값 보존(추출이 만든 비표준 type 도 선택 유지).
                    if !MemoryType.allCases.map(\.rawValue).contains(draftType) {
                        Text(draftType).tag(draftType)
                    }
                }
                VStack(alignment: .leading) {
                    Text("중요도: \(Int(draftImportance))")
                        .font(.plCaption)
                        .foregroundStyle(.plTextSecondary)
                    Slider(value: $draftImportance, in: 1...10, step: 1)
                }
            }
            Section {
                Toggle("검토 완료", isOn: $draftVerified)
            } footer: {
                Text("자동으로 추출된 기억은 처음엔 '검토 필요' 상태예요. 확인했다면 검토 완료로 표시하세요.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.plBgPrimary.ignoresSafeArea())
        .navigationTitle("기억 편집")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button("취소") { onCancel() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("저장") { save() }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            #else
            ToolbarItem(placement: .cancellationAction) { Button("취소") { onCancel() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") { save() }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            #endif
        }
    }

    private func save() {
        let newText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textChanged = newText != memory.text
        var edited = memory
        edited.text = newText
        edited.type = draftType
        edited.importance = Int(draftImportance)
        edited.verified = draftVerified
        onSave(edited, textChanged)
    }
}
