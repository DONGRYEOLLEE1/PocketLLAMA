//
//  MarkdownMessage.swift
//  PocketLlama
//
//  블록 파서 + 블록별 AttributedString(markdown:) inline 렌더 (접근 A·C 종합).
//  - content 를 문단/헤딩/리스트/인용/코드펜스/수평선 블록으로 분리(MarkdownBlockParser).
//  - 각 텍스트 줄의 **굵게**/*기울임*/`인라인코드`/[링크]는 AttributedString(markdown:)로 inline.
//  - 코드펜스는 파싱하지 않고 등폭 텍스트 그대로(미완성 ``` 안전) + 가로스크롤·언어라벨·테두리로 가독성.
//  - 수평선(---/***/___)은 Divider.
//  - 순수 값 타입 파서 → Swift 6 strict concurrency 안전, 스트리밍 재파싱에도 가볍다.
//

import SwiftUI

// MARK: - 블록 모델

enum MarkdownBlock: Equatable, Hashable {
    case heading(level: Int, text: String)        // # ~ ######
    case paragraph(String)                        // 인라인 마크다운 포함 텍스트(여러 줄은 \n 결합)
    case bullet(items: [String])                  // -, *, +
    case ordered(items: [String])                 // 1. 2. ...
    case quote(String)                            // > ...
    case codeBlock(language: String?, code: String)
    case thematicBreak                            // ---, ***, ___ (수평선)
}

// MARK: - 블록 파서 (순수 함수, 한 번의 선형 스캔)

enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        // 줄 분리(개행 정규화). 마지막 빈 줄 유지는 불필요.
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            blocks.append(.paragraph(paragraphBuffer.joined(separator: "\n")))
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        while i < lines.count {
            let raw = lines[i]
            let line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1) 코드펜스 ``` (미완성도 안전하게 끝까지 흡수)
            if let fenceLang = fenceLanguage(trimmed) {
                flushParagraph()
                var code: [String] = []
                i += 1
                var closed = false
                while i < lines.count {
                    let inner = lines[i]
                    if inner.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        closed = true
                        i += 1
                        break
                    }
                    code.append(inner)
                    i += 1
                }
                _ = closed // 닫히지 않아도(스트리밍 중) 지금까지 모은 코드를 블록으로.
                blocks.append(.codeBlock(language: fenceLang.isEmpty ? nil : fenceLang,
                                         code: code.joined(separator: "\n")))
                continue
            }

            // 2) 빈 줄 → 문단 경계
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // 2.5) 수평선 ---, ***, ___ (불릿/문단보다 먼저: "---" 단독만 매칭)
            if isThematicBreak(trimmed) {
                flushParagraph()
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // 3) 헤딩 #~######
            if let (level, text) = heading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            // 4) 인용 > (연속 줄 묶음)
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var rest = String(t.dropFirst())
                    if rest.hasPrefix(" ") { rest.removeFirst() }
                    quoteLines.append(rest)
                    i += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // 5) 불릿 리스트 -, *, +
            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isBullet(t) else { break }
                    items.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.bullet(items: items))
                continue
            }

            // 6) 번호 리스트 1. 2. ...
            if orderedMarker(trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let marker = orderedMarker(t) else { break }
                    items.append(String(t.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.ordered(items: items))
                continue
            }

            // 7) 일반 문단 누적
            paragraphBuffer.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // ``` 또는 ```swift → 언어("" 가능). 펜스 아니면 nil.
    private static func fenceLanguage(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    // 수평선: 공백 제거 후 같은 문자(-, *, _) 3개 이상만으로 이뤄진 줄.
    // "- 항목"(공백 포함) 같은 불릿은 공백 제거 시 다른 문자가 섞여 매칭 안 됨.
    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        let condensed = trimmed.filter { $0 != " " }
        guard condensed.count >= 3 else { return false }
        return condensed.allSatisfy { $0 == first }
    }

    private static func heading(_ trimmed: String) -> (Int, String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx] == "#", level < 6 {
            level += 1
            idx = trimmed.index(after: idx)
        }
        // # 다음엔 공백이 있어야 헤딩(#tag 같은 건 문단).
        guard idx < trimmed.endIndex, trimmed[idx] == " " else { return nil }
        let text = String(trimmed[idx...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isBullet(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "+" else { return false }
        // "- " 형태(마커 뒤 공백). 단독 "-" 도 빈 항목으로 허용.
        let rest = trimmed.dropFirst()
        return rest.isEmpty || rest.first == " "
    }

    // "1." "23." 같은 접두 마커 문자열 반환(예: "1.").
    private static func orderedMarker(_ trimmed: String) -> String? {
        var digits = ""
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx].isNumber {
            digits.append(trimmed[idx])
            idx = trimmed.index(after: idx)
        }
        guard !digits.isEmpty, idx < trimmed.endIndex else { return nil }
        let sep = trimmed[idx]
        guard sep == "." || sep == ")" else { return nil }
        return digits + String(sep)
    }
}

// MARK: - 인라인 렌더(AttributedString markdown, 실패 시 평문 폴백)

enum MarkdownInline {
    /// 한 줄/문단 텍스트를 inline 마크다운으로. 미완성 토큰(닫히지 않은 ** 등)은
    /// AttributedString 이 던지면 평문으로 폴백 → 크래시/깨짐 없음.
    static func attributed(_ text: String) -> AttributedString {
        // .inlineOnlyPreservingWhitespace: 블록 문법 무시(블록은 우리가 처리), 공백 보존.
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}

// MARK: - 어시스턴트 마크다운 뷰

struct MarkdownMessageView: View {
    let content: String

    // 파싱 결과를 캐싱한다: content(스트리밍 토큰)가 실제로 바뀔 때만 재파싱하고,
    // body 재평가(레이아웃 등)에서는 다시 파싱하지 않는다 → 매 프레임 재파싱(O(n²)) 방지.
    // 블록 식별은 내용 기반(Hashable)이라 스트리밍 중 앞쪽(불변) 블록의 뷰 정체성이 유지되어
    // 깜빡임/텍스트 선택 소실이 없다.
    @State private var blocks: [MarkdownBlock]

    init(content: String) {
        self.content = content
        _blocks = State(initialValue: MarkdownBlockParser.parse(content))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks, id: \.self) { block in
                blockView(block)
            }
        }
        .onChange(of: content) { _, newValue in
            blocks = MarkdownBlockParser.parse(newValue)
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(MarkdownInline.attributed(text))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)

        case let .paragraph(text):
            Text(MarkdownInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)

        case let .bullet(items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }

        case let .ordered(items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    listRow(marker: "\(idx + 1).", text: item)
                }
            }

        case let .quote(text):
            HStack(spacing: 8) {
                // [DesignSystem] 인용 막대를 브랜드 액센트로 — 어시스턴트 말풍선 안에서 톤 통일.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.plAccent.opacity(0.55))
                    .frame(width: 3)
                Text(MarkdownInline.attributed(text))
                    .foregroundStyle(.plTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .codeBlock(language, code):
            CodeBlockView(language: language, code: code)

        case .thematicBreak:
            Divider().padding(.vertical, 2)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // [DesignSystem] 리스트 마커를 액센트로 — 가독성 + 브랜드 톤.
            Text(marker)
                .monospacedDigit()
                .foregroundStyle(.plAccent)
            Text(MarkdownInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

// MARK: - 코드블록 뷰

/// 등폭 + 가로 스크롤 + 언어 라벨 + 보조 배경/테두리.
/// 어시스턴트(연회색) 말풍선 안에서도 대비를 확보하고, 긴 코드 줄은 줄바꿈 대신 가로 스크롤.
/// 코드만 따로 선택 가능(.textSelection(.enabled)).
private struct CodeBlockView: View {
    @Environment(\.theme) private var theme
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.plCaption2)
                    .foregroundStyle(.plTextSecondary)
                    .padding(.horizontal, theme.spacing.s + 2)
                    .padding(.top, theme.spacing.xs + 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                // 등폭 + Dynamic Type 연동(.callout 텍스트 스타일 기반) — 코드 가독성 의도.
                Text(code.isEmpty ? " " : code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(theme.spacing.s + 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.plBgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.small, style: .continuous)
                .strokeBorder(Color.plAccent.opacity(0.12), lineWidth: 1)
        )
    }
}
