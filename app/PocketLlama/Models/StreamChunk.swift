//
//  StreamChunk.swift
//  PocketLlama
//
//  SSE data: 한 줄에 담기는 JSON(§7.4).
//  누적 텍스트 = content_block_delta 중 delta.type == "text_delta" 의 delta.text.
//  종료 = message_stop. stop_reason 은 message_delta 안에 온다.
//  thinking_delta(THINK=on)는 MVP에서 무시한다.
//

import Foundation

struct StreamChunk: Decodable {
    let type: String             // message_start / content_block_start / content_block_delta / content_block_stop / message_delta / message_stop / ...
    let index: Int?              // [Phase T1] content_block_* 의 블록 인덱스(혼재 방어용)
    let delta: Delta?
    /// [Phase T1] content_block_start 의 블록 메타(tool_use 면 id/name 캡처, §3 실측).
    let content_block: ContentBlock?

    struct Delta: Decodable {
        let type: String?        // "text_delta" | "thinking_delta" | "input_json_delta" | nil
        let text: String?
        let stop_reason: String? // message_delta 에서 종료 사유(end_turn / max_tokens / tool_use)
        /// [Phase T1] input_json_delta 의 인자 JSON 단편(누적 대상, §3 실측).
        let partial_json: String?
    }

    /// [Phase T1] content_block_start 의 content_block(§3 실측 shape).
    struct ContentBlock: Decodable {
        let type: String?        // "text" | "tool_use" | ...
        let id: String?          // tool_use 블록 id
        let name: String?        // tool_use 블록 도구명(예: web_search)
    }
}
