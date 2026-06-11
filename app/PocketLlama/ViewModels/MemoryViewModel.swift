//
//  MemoryViewModel.swift
//  PocketLlama
//
//  [v0.2 M3] 기억 관리 페이지 상태(M-D8 — 투명 메모리 페이지).
//  - 목록(최신순), verified=0 "검토 필요" 배지.
//  - 물리 삭제(M-D8), 텍스트 수정(수정 시 재임베딩 시도 — 실패 NULL), verified 토글(검토 완료).
//  - MemoryStore 단일 인스턴스 + 선택적 EmbeddingService(재임베딩). @MainActor.
//

import Foundation
import Observation

@Observable @MainActor
final class MemoryViewModel {
    var memories: [Memory] = []

    private let store: MemoryStore
    private let embedding: EmbeddingServiceProtocol?

    init(store: MemoryStore = .shared, embedding: EmbeddingServiceProtocol? = nil) {
        self.store = store
        self.embedding = embedding
    }

    /// 목록 로드(최신순). 화면 진입·변경 후 호출.
    func reload() {
        memories = store.all()
    }

    /// 물리 삭제(M-D8 — 진짜 삭제). 즉시 목록에서 제거.
    func delete(_ memory: Memory) {
        store.delete(id: memory.id)
        memories.removeAll { $0.id == memory.id }
    }

    /// 텍스트 수정 — 변경 시 재임베딩 시도(실패하면 임베딩 NULL 로 두고 LIKE 폴백 대상화).
    /// 텍스트 외 type/importance/verified 도 한 번에 반영할 수 있게 Memory 를 통째로 받는다.
    func update(_ edited: Memory, textChanged: Bool) async {
        var updated = edited
        if textChanged {
            // 텍스트가 바뀌면 기존 임베딩은 무효 → 재임베딩 시도. 실패 시 NULL(폴백).
            if let embedding {
                updated.embedding = try? await embedding.embedDocument(edited.text)
            } else {
                updated.embedding = nil
            }
        }
        store.update(updated)
        reload()
    }

    /// verified 토글(검토 완료/검토 필요). 텍스트 미변경이므로 임베딩 유지.
    func toggleVerified(_ memory: Memory) {
        var m = memory
        m.verified.toggle()
        store.update(m)
        reload()
    }
}
