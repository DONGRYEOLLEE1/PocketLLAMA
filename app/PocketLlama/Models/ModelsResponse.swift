//
//  ModelsResponse.swift
//  PocketLlama
//
//  GET /v1/models (OpenAI 호환) 응답(§7.5).
//  표시값은 data[0].id. 실패해도 /health 만 200이면 fallback 으로 진행(ModelInfoView).
//

import Foundation

struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}
