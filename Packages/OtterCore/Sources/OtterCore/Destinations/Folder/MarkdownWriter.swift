import Foundation

/// Renders what a folder destination writes (ARCHITECTURE §5.1). Pure: no disk access. Output uses
/// `\n` line endings only; callers encode it as UTF-8 without a BOM.
public enum MarkdownWriter {
    /// A new note file: optional frontmatter, then the text, ending with one newline. A note named
    /// with `⌘S` gets a `title` field in its frontmatter. `embeds` (one per attachment) go at the
    /// end, after a blank line.
    public static func newFile(
        text: String,
        title: String? = nil,
        createdAt: Date,
        timeZone: TimeZone,
        frontmatter: Bool,
        embeds: [String] = []
    ) -> String {
        var output = ""
        if frontmatter {
            let created = FileNamer.format(createdAt, "yyyy-MM-dd'T'HH:mm:ssxxxxx", in: timeZone)
            output += "---\n"
            if let title {
                output += "title: \(yamlQuoted(title))\n"
            }
            output += "created: \(created)\nsource: otter\n---\n"
        }
        return output + appending(embeds, to: body(text)) + "\n"
    }

    /// One block for an append file, rendered from `template` (see `AppendTemplate`), without a
    /// trailing newline. `embeds` (one per attachment) fill `{{attachments}}`, one per line; a
    /// template without it gets them at the end of `{{text}}`, after a blank line.
    public static func appendBlock(
        template: String,
        text: String,
        createdAt: Date,
        timeZone: TimeZone,
        embeds: [String] = []
    ) -> String {
        let template = normalizedLineEndings(template)
        let noteBody = body(text)
        let hasAttachmentsTag = template.range(of: #"\{\{\s*attachments\s*\}\}"#, options: .regularExpression) != nil
        let text = hasAttachmentsTag ? noteBody : appending(embeds, to: noteBody)
        let values = [
            "time": FileNamer.format(createdAt, "HH:mm", in: timeZone),
            "date": FileNamer.format(createdAt, "yyyy-MM-dd", in: timeZone),
            "text": text,
            "title": FileNamer.title(from: noteBody),
            "attachments": hasAttachmentsTag ? embeds.joined(separator: "\n") : "",
        ]
        let rendered = AppendTemplate.render(template, isMultiLine: text.contains("\n"), values: values)
        return String(rendered.reversed().drop(while: \.isNewline).reversed())
    }

    /// What to write at the end of an append file whose last bytes are `tail` (up to two; empty
    /// for a new file): enough newlines to leave one blank line before `block`, then the block and
    /// a newline.
    public static func appendText(_ block: String, toFileEndingWith tail: Data) -> String {
        let newline = UInt8(ascii: "\n")
        let separator: String
        if tail.isEmpty || tail.suffix(2).elementsEqual([newline, newline]) {
            separator = ""
        } else if tail.last == newline {
            separator = "\n"
        } else {
            separator = "\n\n"
        }
        return separator + block + "\n"
    }

    // MARK: - Private

    /// `body`, then a blank line and one embed per line. Just the embeds for a note with no text.
    private static func appending(_ embeds: [String], to body: String) -> String {
        guard !embeds.isEmpty else {
            return body
        }
        let lines = embeds.joined(separator: "\n")
        return body.isEmpty ? lines : body + "\n\n" + lines
    }

    /// The note's text with `\n` line endings, without blank lines at either end or trailing
    /// whitespace. A one-line note is trimmed on both sides.
    private static func body(_ text: String) -> String {
        var lines = normalizedLineEndings(text).split(separator: "\n", omittingEmptySubsequences: false)
        while let first = lines.first, first.allSatisfy(\.isWhitespace) {
            lines.removeFirst()
        }
        while let last = lines.last, last.allSatisfy(\.isWhitespace) {
            lines.removeLast()
        }
        if lines.count == 1 {
            return lines[0].trimmingCharacters(in: .whitespaces)
        }
        return String(lines.joined(separator: "\n").reversed().drop(while: \.isWhitespace).reversed())
    }

    /// A YAML double-quoted scalar on one line. Control characters, newlines included, become spaces.
    private static func yamlQuoted(_ text: String) -> String {
        var quoted = "\""
        for character in text {
            switch character {
            case "\\", "\"":
                quoted += "\\\(character)"
            case _ where character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }):
                quoted += " "
            default:
                quoted.append(character)
            }
        }
        return quoted + "\""
    }

    private static func normalizedLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

/// The append-block template: a tiny hand-rolled renderer, no templating dependency
/// (ARCHITECTURE §5.1).
///
/// - Variables: `{{time}}` (`HH:mm`), `{{date}}` (`yyyy-MM-dd`), `{{text}}`, `{{title}}` and
///   `{{attachments}}`. Unknown tags are written as they are. Values are never re-scanned, so a
///   note containing `{{time}}` keeps it.
/// - Sections: `{{#single_line}}…{{/single_line}}` is kept only for a one-line note,
///   `{{#multi_line}}…{{/multi_line}}` only for a longer one. A line holding nothing but section
///   tags, or emptied by a dropped section, is removed with its newline.
public enum AppendTemplate {
    public static let `default` = """
        {{#single_line}}- {{time}} {{text}}{{/single_line}}
        {{#multi_line}}
        ### {{time}}
        {{text}}
        {{/multi_line}}
        """

    private enum Token {
        case text(Substring)
        case variable(String)
        case open(String)
        case close(String)
    }

    public static func render(_ template: String, isMultiLine: Bool, values: [String: String]) -> String {
        let sections = ["single_line": !isMultiLine, "multi_line": isMultiLine]
        var output = ""
        /// Whether each open section is kept, innermost last.
        var open: [Bool] = []

        let lines = template.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var rendered = ""
            var hasSectionTag = false
            for token in tokens(in: line, sections: sections.keys, variables: values.keys) {
                let isKept = !open.contains(false)
                switch token {
                case let .text(text):
                    if isKept {
                        rendered += text
                    }
                case let .variable(name):
                    if isKept {
                        rendered += values[name, default: ""]
                    }
                case let .open(name):
                    hasSectionTag = true
                    open.append(sections[name] ?? true)
                case .close:
                    hasSectionTag = true
                    _ = open.popLast()
                }
            }
            if hasSectionTag, rendered.allSatisfy(\.isWhitespace) {
                continue
            }
            output += rendered
            if index < lines.count - 1, !open.contains(false) {
                output += "\n"
            }
        }
        return output
    }

    private static func tokens(
        in line: Substring,
        sections: Dictionary<String, Bool>.Keys,
        variables: Dictionary<String, String>.Keys
    ) -> [Token] {
        var tokens: [Token] = []
        var rest = line[...]
        while let start = rest.range(of: "{{"), let end = rest[start.upperBound...].range(of: "}}") {
            if start.lowerBound > rest.startIndex {
                tokens.append(.text(rest[..<start.lowerBound]))
            }
            let raw = rest[start.lowerBound..<end.upperBound]
            let name = rest[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("#"), sections.contains(String(name.dropFirst())) {
                tokens.append(.open(String(name.dropFirst())))
            } else if name.hasPrefix("/"), sections.contains(String(name.dropFirst())) {
                tokens.append(.close(String(name.dropFirst())))
            } else if variables.contains(name) {
                tokens.append(.variable(name))
            } else {
                tokens.append(.text(raw))
            }
            rest = rest[end.upperBound...]
        }
        if !rest.isEmpty {
            tokens.append(.text(rest))
        }
        return tokens
    }
}
