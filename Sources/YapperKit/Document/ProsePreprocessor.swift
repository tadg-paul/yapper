// ABOUTME: Normalizes prose markup into text that is safer for synthesis.
// ABOUTME: Records prose structure such as section breaks for diagnostics and assembly.

import Foundation

public enum ProsePauseKind: String, Codable, Sendable {
    case paragraph
    case section
}

public struct ProseSectionBreak: Codable, Equatable, Sendable {
    public let lineIndex: Int
    public let pause: ProsePauseKind

    public init(lineIndex: Int, pause: ProsePauseKind) {
        self.lineIndex = lineIndex
        self.pause = pause
    }
}

public enum ProsePreprocessDiagnosticKind: String, CaseIterable, Codable, Sendable {
    case cleanup
    case sectionBreak
    case emphasis
    case dialogueDash
    case substitution
    case substitutionSkipped
}

public struct ProsePreprocessDiagnostic: Codable, Equatable, Sendable {
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

public struct ProsePreprocessResult: Codable, Equatable, Sendable {
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
    private static let maximumSafeSymbolRunLength = 6

    public static func preprocess(
        _ text: String,
        substitutions: [String: String] = [:],
        supportsIPA: Bool = true
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
            supportsIPA: supportsIPA,
            diagnostics: &diagnostics
        )
        let hyphenNormalized = normalizeIntraWordHyphens(substituted)
        let speechNormalized = normalizeUnsafeSymbolRuns(
            hyphenNormalized,
            diagnostics: &diagnostics
        )

        return ProsePreprocessResult(
            text: speechNormalized,
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

    private static func normalizeIntraWordHyphens(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?<=[A-Za-z])-(?=[A-Za-z])"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func normalizeUnsafeSymbolRuns(
        _ text: String,
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) -> String {
        guard text.contains(where: \.isSpeakable) else {
            recordSymbolCleanup(original: text, replacement: "", diagnostics: &diagnostics)
            return ""
        }

        var result = ""
        var symbolRun = ""
        for character in text {
            if character.isSpeakable || character.isWhitespace {
                appendNormalizedSymbolRun(symbolRun, to: &result)
                symbolRun = ""
                result.append(character)
            } else {
                symbolRun.append(character)
            }
        }
        appendNormalizedSymbolRun(symbolRun, to: &result)

        guard result != text else { return text }
        let collapsed = result.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        recordSymbolCleanup(original: text, replacement: collapsed, diagnostics: &diagnostics)
        return collapsed
    }

    private static func normalizedSymbolRun(_ run: String) -> String {
        guard run.count > maximumSafeSymbolRunLength else { return run }
        if run.contains(".") { return "." }
        if run.contains("?") { return "?" }
        if run.contains("!") { return "!" }
        return ""
    }

    private static func appendNormalizedSymbolRun(_ run: String, to result: inout String) {
        let normalized = normalizedSymbolRun(run)
        guard !normalized.isEmpty else { return }
        if normalized == "." || normalized == "?" || normalized == "!" {
            while result.last == " " || result.last == "\t" {
                result.removeLast()
            }
        }
        result += normalized
    }

    private static func recordSymbolCleanup(
        original: String,
        replacement: String,
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) {
        guard original != replacement else { return }
        diagnostics.append(ProsePreprocessDiagnostic(
            kind: .cleanup,
            original: original,
            replacement: replacement
        ))
    }

    private static func applySubstitutions(
        _ text: String,
        substitutions: [String: String],
        supportsIPA: Bool,
        diagnostics: inout [ProsePreprocessDiagnostic]
    ) -> String {
        guard !substitutions.isEmpty else { return text }
        var result = text

        let orderedSubstitutions = substitutions.sorted {
            if $0.key.count == $1.key.count {
                return CaseInsensitiveConfigMap.identity($0.key)
                    < CaseInsensitiveConfigMap.identity($1.key)
            }
            return $0.key.count > $1.key.count
        }
        for (find, replace) in orderedSubstitutions {
            guard !find.isEmpty else { continue }
            var didReplace = false
            var didSkip = false
            var lastReplacement = replace
            let escaped = NSRegularExpression.escapedPattern(for: find)
            let pattern = "(?<![\\p{L}\\p{M}\\p{N}\\p{Pc}])\(escaped)(?![\\p{L}\\p{M}\\p{N}\\p{Pc}])"
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .useUnicodeWordBoundaries]
            ) else {
                continue
            }
            let matches = regex.matches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let matched = String(result[range])
                guard let replacement = substitutionReplacement(
                    replace: replace,
                    matched: matched,
                    supportsIPA: supportsIPA
                ) else {
                    didSkip = true
                    continue
                }
                result.replaceSubrange(range, with: replacement)
                didReplace = true
                lastReplacement = replacement
            }

            if didReplace {
                diagnostics.append(ProsePreprocessDiagnostic(
                    kind: .substitution,
                    original: find,
                    replacement: lastReplacement
                ))
            }
            if didSkip {
                diagnostics.append(ProsePreprocessDiagnostic(
                    kind: .substitutionSkipped,
                    original: find,
                    replacement: "unsupported IPA; source text preserved"
                ))
            }
        }

        return result
    }

    private static func substitutionReplacement(
        replace: String,
        matched: String,
        supportsIPA: Bool
    ) -> String? {
        guard let ipa = parseIPAReplacement(replace) else { return replace }
        if supportsIPA {
            return "[\(matched)](/\(ipa.phonemes)/)"
        }
        return ipa.phonetic
    }

    private static func parseIPAReplacement(
        _ replacement: String
    ) -> (phonemes: String, phonetic: String?)? {
        guard replacement.hasPrefix("/"), replacement.count > 2 else { return nil }
        let contentStart = replacement.index(after: replacement.startIndex)

        if replacement.hasSuffix("/") {
            let contentEnd = replacement.index(before: replacement.endIndex)
            return (String(replacement[contentStart..<contentEnd]), nil)
        }

        guard replacement.hasSuffix(")"),
              let separator = replacement.range(of: "/(", options: .backwards),
              separator.lowerBound > contentStart else {
            return nil
        }
        let phoneticEnd = replacement.index(before: replacement.endIndex)
        let phonetic = String(replacement[separator.upperBound..<phoneticEnd])
        return (
            String(replacement[contentStart..<separator.lowerBound]),
            phonetic.isEmpty ? nil : phonetic
        )
    }
}

private extension Character {
    var isSpeakable: Bool {
        unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    var isAlphaNumeric: Bool {
        unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }
}
