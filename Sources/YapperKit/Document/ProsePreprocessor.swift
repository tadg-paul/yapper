// ABOUTME: Normalizes prose markup into text that is safer for synthesis.
// ABOUTME: Records prose structure such as section breaks for diagnostics and assembly.

import Foundation

public enum ProsePauseKind: String, Sendable {
    case paragraph
    case section
}

public struct ProseSectionBreak: Equatable, Sendable {
    public let lineIndex: Int
    public let pause: ProsePauseKind

    public init(lineIndex: Int, pause: ProsePauseKind) {
        self.lineIndex = lineIndex
        self.pause = pause
    }
}

public enum ProsePreprocessDiagnosticKind: String, CaseIterable, Sendable {
    case cleanup
    case sectionBreak
    case emphasis
    case dialogueDash
    case substitution
}

public struct ProsePreprocessDiagnostic: Equatable, Sendable {
    public let kind: ProsePreprocessDiagnosticKind
    public let original: String
    public let replacement: String
    public let lineIndex: Int?

    public init(
        kind: ProsePreprocessDiagnosticKind,
        original: String,
        replacement: String,
        lineIndex: Int? = nil
    ) {
        self.kind = kind
        self.original = original
        self.replacement = replacement
        self.lineIndex = lineIndex
    }
}

public struct ProsePreprocessResult: Equatable, Sendable {
    public let text: String
    public let sectionBreaks: [ProseSectionBreak]
    public let diagnostics: [ProsePreprocessDiagnostic]

    public init(
        text: String,
        sectionBreaks: [ProseSectionBreak],
        diagnostics: [ProsePreprocessDiagnostic]
    ) {
        self.text = text
        self.sectionBreaks = sectionBreaks
        self.diagnostics = diagnostics
    }
}

public enum ProsePreprocessor {
    public static func preprocess(
        _ text: String,
        substitutions: [String: String] = [:]
    ) -> ProsePreprocessResult {
        var diagnostics: [ProsePreprocessDiagnostic] = []
        var sectionBreaks: [ProseSectionBreak] = []
        let cleaned = cleanMarkup(text, diagnostics: &diagnostics)
        let normalized = normalizeLines(
            cleaned,
            sectionBreaks: &sectionBreaks,
            diagnostics: &diagnostics
        )
        let substituted = applySubstitutions(
            normalized,
            substitutions: substitutions,
            diagnostics: &diagnostics
        )

        return ProsePreprocessResult(
            text: substituted,
            sectionBreaks: sectionBreaks,
            diagnostics: diagnostics
        )
    }

    private static func cleanMarkup(
        _ text: String,
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) -> String {
        var result = text
        let original = result

        result = result.replacingOccurrences(
            of: "<[^>]*>",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"!\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\{[^}]*\}"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?m)^:::.*$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "\\", with: "")
        result = result.replacingOccurrences(
            of: #"(?m)^\s*\[\]\s*$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "[]", with: "")

        if result != original {
            diagnostics.append(ProsePreprocessDiagnostic(
                kind: .cleanup,
                original: original,
                replacement: result
            ))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeLines(
        _ text: String,
        sectionBreaks: inout [ProseSectionBreak],
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) -> String {
        let lines = text.components(separatedBy: .newlines)
        let normalizedLines = lines.enumerated().map { lineIndex, line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isSectionBreak(trimmed) {
                sectionBreaks.append(ProseSectionBreak(lineIndex: lineIndex, pause: .section))
                diagnostics.append(ProsePreprocessDiagnostic(
                    kind: .sectionBreak,
                    original: trimmed,
                    replacement: "",
                    lineIndex: lineIndex
                ))
                return ""
            }

            if let quoted = quoteDialogueDashLine(trimmed) {
                diagnostics.append(ProsePreprocessDiagnostic(
                    kind: .dialogueDash,
                    original: trimmed,
                    replacement: quoted,
                    lineIndex: lineIndex
                ))
                return quoted
            }

            return quoteEmphasis(in: line, lineIndex: lineIndex, diagnostics: &diagnostics)
        }

        return collapseBlankLines(normalizedLines.joined(separator: "\n"))
    }

    private static func isSectionBreak(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        guard let first = line.first, first == "*" || first == "-" || first == "_" else {
            return false
        }
        return line.allSatisfy { $0 == first }
    }

    private static func quoteDialogueDashLine(_ line: String) -> String? {
        if line.hasPrefix("--- ") {
            return "\"\(line.dropFirst(4).trimmingCharacters(in: .whitespaces))\""
        }
        if line.hasPrefix("— ") {
            return "\"\(line.dropFirst(2).trimmingCharacters(in: .whitespaces))\""
        }
        return nil
    }

    private static func quoteEmphasis(
        in line: String,
        lineIndex: Int,
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) -> String {
        var result = line
        for delimiter in ["**", "__", "*", "_", "/"] {
            result = replaceDelimitedEmphasis(
                in: result,
                delimiter: delimiter,
                lineIndex: lineIndex,
                diagnostics: &diagnostics
            )
        }
        return result
    }

    private static func replaceDelimitedEmphasis(
        in line: String,
        delimiter: String,
        lineIndex: Int,
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) -> String {
        var result = line
        var searchStart = result.startIndex

        while let opening = result.range(of: delimiter, range: searchStart..<result.endIndex) {
            guard isValidOpeningDelimiter(in: result, range: opening) else {
                searchStart = opening.upperBound
                continue
            }

            let contentStart = opening.upperBound
            guard let closing = result.range(of: delimiter, range: contentStart..<result.endIndex) else {
                break
            }
            guard isValidClosingDelimiter(in: result, range: closing) else {
                searchStart = closing.upperBound
                continue
            }

            let content = String(result[contentStart..<closing.lowerBound])
            guard isValidEmphasisContent(content, delimiter: delimiter) else {
                searchStart = closing.upperBound
                continue
            }

            let original = String(result[opening.lowerBound..<closing.upperBound])
            let replacement = "\"\(content)\""
            result.replaceSubrange(opening.lowerBound..<closing.upperBound, with: replacement)
            diagnostics.append(ProsePreprocessDiagnostic(
                kind: .emphasis,
                original: original,
                replacement: replacement,
                lineIndex: lineIndex
            ))
            searchStart = result.index(opening.lowerBound, offsetBy: replacement.count)
        }

        return result
    }

    private static func isValidOpeningDelimiter(in text: String, range: Range<String.Index>) -> Bool {
        guard range.upperBound < text.endIndex else { return false }
        let next = text[range.upperBound]
        guard !next.isWhitespace else { return false }
        if range.lowerBound > text.startIndex {
            let previous = text[text.index(before: range.lowerBound)]
            return !previous.isAlphaNumeric
        }
        return true
    }

    private static func isValidClosingDelimiter(in text: String, range: Range<String.Index>) -> Bool {
        guard range.lowerBound > text.startIndex else { return false }
        let previous = text[text.index(before: range.lowerBound)]
        guard !previous.isWhitespace else { return false }
        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            return !next.isAlphaNumeric
        }
        return true
    }

    private static func isValidEmphasisContent(_ content: String, delimiter: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == content else { return false }
        guard !content.contains("\n"), !content.contains(delimiter) else { return false }
        return content.contains { $0.isAlphaNumeric }
    }

    private static func collapseBlankLines(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applySubstitutions(
        _ text: String,
        substitutions: [String: String],
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) -> String {
        guard !substitutions.isEmpty else { return text }
        var result = text

        for (find, replace) in substitutions {
            guard !find.isEmpty else { continue }
            var didReplace = false
            var lastReplacement = ""
            var searchStart = result.startIndex

            while searchStart < result.endIndex,
                  let range = result.range(
                    of: find,
                    options: [.caseInsensitive],
                    range: searchStart..<result.endIndex
                  ) {
                let matched = String(result[range])
                let replacement = substitutionReplacement(
                    find: find,
                    replace: replace,
                    matched: matched
                )
                result.replaceSubrange(range, with: replacement)
                didReplace = true
                lastReplacement = replacement
                searchStart = result.index(range.lowerBound, offsetBy: replacement.count)
            }

            if didReplace {
                diagnostics.append(ProsePreprocessDiagnostic(
                    kind: .substitution,
                    original: find,
                    replacement: lastReplacement
                ))
            }
        }

        return result
    }

    private static func substitutionReplacement(
        find: String,
        replace: String,
        matched: String
    ) -> String {
        if replace.count > 2 && replace.hasPrefix("/") && replace.hasSuffix("/") {
            return "[\(matched.isEmpty ? find : matched)](\(replace))"
        }
        return replace
    }
}

private extension Character {
    var isAlphaNumeric: Bool {
        unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }
}
