//
//  MessagesRequest.swift
//  PocketLlama
//
//  Anthropic 호환 POST /v1/messages 요청 바디(§7.1~7.2).
//  ⚠️ max_tokens 는 필수(누락 시 400). model 은 "local"(llama-server 단일 모델 별칭).
//  멀티턴은 messages 에 user/assistant 교대로 채워 전송한다.
//
//  [Phase T1 — tools 확장]
//  - tools: [ToolDefinition]? 추가(nil 이면 인코딩 생략 → 기존 일반 채팅 wire 불변).
//  - Wire.content 를 String 단형에서 String | [블록] 양형(WireContent)으로 확장.
//    tool 왕복 회신(assistant tool_use + user tool_result)을 인코딩하기 위함(§3).
//    기존 텍스트 턴은 .text(String) 로 인코딩되어 와이어상 동일(회귀 0).
//

import Foundation

struct MessagesRequest: Encodable {
    let model: String
    let max_tokens: Int          // ⚠️ Anthropic 필수
    var system: String?          // top-level 시스템 프롬프트(생략 가능)
    let messages: [Wire]
    var stream: Bool?            // 비스트림이면 nil/false, 스트림이면 true
    /// [Phase T1] 도구 정의 배열. nil 이면 인코딩 생략(웹검색 비활성/일반 생성 경로).
    var tools: [ToolDefinition]?

    struct Wire: Encodable {
        let role: String         // "user" | "assistant"
        let content: WireContent // String | [블록] 양형(§3)

        /// 기존 호출부 호환: 문자열 content 로 텍스트 턴 생성(.text 로 인코딩).
        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
        }

        /// 블록 배열 content 로 턴 생성(tool 왕복 회신용, §3).
        init(role: String, blocks: [WireBlock]) {
            self.role = role
            self.content = .blocks(blocks)
        }
    }
}

/// [Phase T1] wire 메시지의 content 양형(§3 — String | 블록 배열).
/// Anthropic 은 content 가 문자열이거나 블록 배열일 수 있다. 인코딩만 필요(요청 본문).
enum WireContent: Encodable {
    case text(String)
    case blocks([WireBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s):
            try container.encode(s)
        case .blocks(let b):
            try container.encode(b)
        }
    }
}

/// [Phase T1] tool 왕복 회신용 content 블록(§3 — tool_use / tool_result).
/// 인코딩 전용. 단일 tool 왕복에 필요한 필드만 갖는다.
enum WireBlock: Encodable {
    /// assistant 가 호출한 도구: {type:"tool_use", id, name, input}
    /// input 은 원본 JSON 문자열(스트림에서 누적한 partial_json) → object 로 재인코딩.
    case toolUse(id: String, name: String, inputJSON: String)
    /// 앱이 회신하는 도구 결과: {type:"tool_result", tool_use_id, content}
    case toolResult(toolUseID: String, content: String)

    private enum CodingKeys: String, CodingKey {
        case type, id, name, input, tool_use_id, content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .toolUse(let id, let name, let inputJSON):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            // inputJSON(문자열)을 object 로 재인코딩. 파싱 실패 시 빈 객체로 방어(§3 — object 기준).
            let inputObject = JSONValue(rawJSON: inputJSON) ?? .object([:])
            try container.encode(inputObject, forKey: .input)
        case .toolResult(let toolUseID, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .tool_use_id)
            try container.encode(content, forKey: .content)
        }
    }
}

/// [Phase T1] tool 정의(§3 — 요청 tools 배열 요소).
///
/// [v0.2 M4] InputSchema 다중 속성 일반화(리뷰 ③-E Blocker 해소).
/// 기존 query 단일 하드코딩 → `properties: [String: Property]` 사전 + `required: [String]` 로 일반화.
/// save_memory(text/type/importance) 같은 다중 인자 tool 을 표현하기 위함. 인코딩 키 순서는
/// sorted 로 안정화(같은 입력이면 같은 바이트 → prefix cache·재현성 보존, M-D10 정신).
/// webSearch 정의는 동일 와이어(properties:{query:{...}}, required:["query"])로 유지 → 회귀 0.
struct ToolDefinition: Encodable {
    let name: String
    let description: String
    let input_schema: InputSchema

    /// 다중 속성 입력 스키마(§3 — {type:"object", properties:{…}, required:[…]}).
    struct InputSchema: Encodable {
        let type: String
        let properties: [String: Property]
        let required: [String]

        struct Property: Encodable {
            let type: String          // "string" | "integer" | ...
            let description: String
        }

        private enum CodingKeys: String, CodingKey { case type, properties, required }

        /// properties 사전을 키 정렬해 인코딩(키 순서 안정화 — 재현성·캐시 보존).
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(SortedProperties(properties), forKey: .properties)
            try container.encode(required, forKey: .required)
        }

        /// 키 정렬 인코딩을 강제하는 properties 래퍼(Swift Dictionary 의 비결정 순서 제거).
        private struct SortedProperties: Encodable {
            let dict: [String: Property]
            init(_ d: [String: Property]) { self.dict = d }

            private struct DynamicKey: CodingKey {
                let stringValue: String
                init(stringValue: String) { self.stringValue = stringValue }
                var intValue: Int? { nil }
                init?(intValue: Int) { nil }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: DynamicKey.self)
                for key in dict.keys.sorted() {
                    try container.encode(dict[key], forKey: DynamicKey(stringValue: key))
                }
            }
        }
    }

    /// 웹검색 tool 표준 정의(§3·§4). description 은 §4 의 사용 지침을 반영.
    static let webSearch = ToolDefinition(
        name: "web_search",
        description: "최신 정보·시세·뉴스·날씨 등 실시간성 질문에 한해 웹을 검색한다. query 에 검색어를 넣어 호출하라.",
        input_schema: InputSchema(
            type: "object",
            properties: ["query": .init(type: "string", description: "검색할 질의문")],
            required: ["query"]
        )
    )

    /// [v0.2 M4] 명시 저장 tool(M-D11). description 을 좁혀 "기억해 줘" 류 명시 요청에만 발동.
    /// 인자: text(필수)·type(선호|사실|일정|관계)·importance(1~10). 라우팅은 ChatViewModel(§4).
    static let saveMemory = ToolDefinition(
        name: "save_memory",
        description: "사용자가 명시적으로 '기억해 달라'고 요청한 사실을 저장한다. 명시 요청이 있을 때만 사용",
        input_schema: InputSchema(
            type: "object",
            properties: [
                "text": .init(type: "string", description: "기억할 내용(간결한 한 문장)"),
                "type": .init(type: "string", description: "선호|사실|일정|관계 중 하나"),
                "importance": .init(type: "integer", description: "중요도 1~10"),
            ],
            required: ["text"]
        )
    )
}

/// [Phase T1] 임의 JSON 값을 표현하는 최소 타입(tool_use input object 디코딩·재인코딩용).
/// 스트림에서 누적한 input JSON 문자열을 파싱해 그대로 다시 인코딩한다(타입 보존).
/// 비스트림 응답(MessagesResponse)에서는 Decodable 로 input object 를 받는다.
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    /// 원본 JSON 문자열을 파싱(실패 시 nil).
    init?(rawJSON: String) {
        guard let data = rawJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        self = JSONValue(any: obj)
    }

    private init(any: Any) {
        switch any {
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            // JSONSerialization 은 숫자·bool 모두 NSNumber 로 준다 → CFBoolean 으로 bool 판별.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let d as [String: Any]:
            self = .object(d.mapValues { JSONValue(any: $0) })
        case let a as [Any]:
            self = .array(a.map { JSONValue(any: $0) })
        case is NSNull:
            self = .null
        default:
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):  try container.encode(s)
        case .number(let n):  try container.encode(n)
        case .bool(let b):    try container.encode(b)
        case .object(let o):  try container.encode(o)
        case .array(let a):   try container.encode(a)
        case .null:           try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            // Bool 을 Double 보다 먼저 시도(true→1.0 로 흡수되는 것 방지).
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }
}
