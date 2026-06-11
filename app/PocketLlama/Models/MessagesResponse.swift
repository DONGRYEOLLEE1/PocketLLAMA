//
//  MessagesResponse.swift
//  PocketLlama
//
//  비스트리밍 POST /v1/messages 응답(§7.3).
//  ⚠️ content[0] 을 가정하지 말 것 — content 는 블록 배열이고 THINK=on 이면
//  thinking 블록이 먼저 올 수 있다. type == "text" 블록만 골라 합친다.
//

import Foundation

struct MessagesResponse: Decodable {
    let content: [Block]
    let stop_reason: String?     // end_turn / max_tokens / tool_use / ...

    struct Block: Decodable {
        let type: String         // "text" | "thinking" | "tool_use" | ...
        let text: String?
        // [Phase T1] tool_use 블록(§3 비스트림 실측: {id, name, input(object)}).
        let id: String?
        let name: String?
        let input: ToolInput?

        /// tool_use input(object). 디코딩만 하고 다시 JSON 문자열로 재직렬화해 wire 회신에 쓴다.
        struct ToolInput: Decodable {
            let json: String     // input object 를 그대로 보존한 JSON 문자열

            init(from decoder: Decoder) throws {
                // input 은 임의 object → JSONValue 로 받아 표준 JSON 문자열로 재인코딩.
                let value = try JSONValue(from: decoder)
                let data = try JSONEncoder().encode(value)
                self.json = String(data: data, encoding: .utf8) ?? "{}"
            }
        }
    }

    /// type == "text" 블록만 합친 사용자 표시용 텍스트.
    var text: String {
        content.filter { $0.type == "text" }.compactMap(\.text).joined()
    }

    /// [Phase T1] 첫 tool_use 블록(없으면 nil). 비스트림 tool 루프(§4 T2)용.
    var toolUse: (id: String, name: String, inputJSON: String)? {
        guard let block = content.first(where: { $0.type == "tool_use" }),
              let id = block.id, let name = block.name else { return nil }
        return (id, name, block.input?.json ?? "{}")
    }

    /// stop_reason == "tool_use" 여부(§3).
    var wantsToolUse: Bool { stop_reason == "tool_use" }

    /// max_tokens 로 잘렸는지(잘림 안내용, Phase 6).
    var wasTruncated: Bool { stop_reason == "max_tokens" }
}
