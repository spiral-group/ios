//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (coverage walk F6): an agent writes Markdown in a plain
// `body` (a structured reply's heading is `**Summary**`, a quote `> …`, and a
// model's own replies use the same syntax). This turns that body into the
// HTML the timeline already renders for a formatted message, so it shows
// bold, quotes, lists and code instead of the literal marks.
//

import Foundation

nonisolated enum SpiralAgentMarkdown {
    /// The body as HTML, or nil when it has no Markdown in it (it then stays plain text).
    ///
    /// Links are left as text: a link's words never hide where it goes, and the
    /// timeline still makes a bare URL tappable.
    static func html(fromBody body: String) -> String? {
        var renderer = Renderer()
        renderer.render(body)
        return renderer.didFormat ? renderer.html : nil
    }

    private enum Block: Equatable {
        case none
        case paragraph
        case quote
        case list(ordered: Bool)
        case code
    }

    private struct Renderer {
        private(set) var html = ""
        private(set) var didFormat = false
        private var block = Block.none
        private var linesInBlock = 0

        mutating func render(_ body: String) {
            for rawLine in body.components(separatedBy: .newlines) {
                if block == .code {
                    if isFence(rawLine) {
                        close()
                    } else {
                        appendCodeLine(rawLine)
                    }
                    continue
                }

                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    // A structured reply puts a blank line between its bullets; the list goes on.
                    if case .list = block { continue }
                    close()
                } else if isFence(line) {
                    open(.code)
                    didFormat = true
                } else if let heading = Self.heading(in: line) {
                    close()
                    html += "<p><strong>\(inline(heading))</strong></p>"
                    didFormat = true
                } else if let quoted = Self.quote(in: line) {
                    open(.quote)
                    appendLine(inline(quoted))
                    didFormat = true
                } else if let (item, ordered) = Self.listItem(in: line) {
                    open(.list(ordered: ordered))
                    html += "<li>\(inline(item))</li>"
                    didFormat = true
                } else {
                    open(.paragraph)
                    appendLine(inline(line))
                }
            }
            close()
        }

        // MARK: Blocks

        private mutating func open(_ newBlock: Block) {
            guard block != newBlock else { return }
            close()
            block = newBlock
            linesInBlock = 0
            switch newBlock {
            case .none: break
            case .paragraph: html += "<p>"
            case .quote: html += "<blockquote>"
            case .list(let ordered): html += ordered ? "<ol>" : "<ul>"
            case .code: html += "<pre><code>"
            }
        }

        private mutating func close() {
            switch block {
            case .none: break
            case .paragraph: html += "</p>"
            case .quote: html += "</blockquote>"
            case .list(let ordered): html += ordered ? "</ol>" : "</ul>"
            case .code: html += "</code></pre>"
            }
            block = .none
            linesInBlock = 0
        }

        private mutating func appendLine(_ lineHTML: String) {
            if linesInBlock > 0 { html += "<br>" }
            html += lineHTML
            linesInBlock += 1
        }

        private mutating func appendCodeLine(_ line: String) {
            if linesInBlock > 0 { html += "\n" }
            html += Self.escape(line)
            linesInBlock += 1
        }

        private func isFence(_ line: String) -> Bool {
            line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        }

        private static func heading(in line: String) -> String? {
            let hashes = line.prefix { $0 == "#" }
            guard (1...6).contains(hashes.count) else { return nil }
            let rest = line.dropFirst(hashes.count)
            guard rest.first == " " else { return nil }
            return rest.trimmingCharacters(in: .whitespaces)
        }

        private static func quote(in line: String) -> String? {
            guard line.hasPrefix(">") else { return nil }
            return line.dropFirst().trimmingCharacters(in: .whitespaces)
        }

        private static func listItem(in line: String) -> (String, ordered: Bool)? {
            // "• " is what compose_structured_reply writes for a bullet block.
            for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
                return (String(line.dropFirst(marker.count)), false)
            }
            let digits = line.prefix(while: \.isNumber)
            guard !digits.isEmpty, digits.count <= 3 else { return nil }
            let rest = line.dropFirst(digits.count)
            guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
            return (String(rest.dropFirst(2)), true)
        }

        // MARK: Inline

        /// Emphasis, code and strikethrough through Foundation's CommonMark parser.
        private mutating func inline(_ text: String) -> String {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                                  failurePolicy: .returnPartiallyParsedIfPossible)
            guard let parsed = try? AttributedString(markdown: text, options: options) else {
                return Self.escape(text)
            }

            var result = ""
            for run in parsed.runs {
                var piece = Self.escape(String(parsed[run.range].characters))
                if let link = run.link, piece != Self.escape(link.absoluteString) {
                    piece += " (\(Self.escape(link.absoluteString)))"
                }
                let intent = run.inlinePresentationIntent ?? []
                if intent.contains(.code) { piece = "<code>\(piece)</code>"; didFormat = true }
                if intent.contains(.strikethrough) { piece = "<del>\(piece)</del>"; didFormat = true }
                if intent.contains(.emphasized) { piece = "<em>\(piece)</em>"; didFormat = true }
                if intent.contains(.stronglyEmphasized) { piece = "<strong>\(piece)</strong>"; didFormat = true }
                if run.link != nil { didFormat = true }
                result += piece
            }
            return result
        }

        private static func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
    }
}
