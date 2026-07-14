// ABOUTME: Unified document-to-chapters converter dispatching by file extension.
// ABOUTME: Supports PDF, docx, odt, md, html, txt, epub, and mobi.

import Foundation

/// Converts documents of various formats into chapter lists.
///
/// Dispatches by file extension (case-insensitive) to format-specific converters.
/// External tools (pdftotext, pandoc, ebook-convert) are validated before use.
public struct DocumentConverter {

    /// Convert a document file to chapters.
    ///
    /// - Parameter path: path to the input file
    /// - Returns: array of chapters with titles and text
    /// - Throws: if the format is unsupported, the file is invalid, or a required tool is missing
    public static func convert(_ path: String) throws -> [Chapter] {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        switch ext {
        case "epub":
            return try EpubParser.parse(path).chapters
        case "mobi":
            return try convertMobi(path)
        case "pdf":
            return try convertPDF(path)
        case "docx", "odt":
            return try convertWithPandoc(path)
        case "md", "markdown":
            return try convertMarkdown(path)
        case "html", "htm":
            return try convertHTML(path)
        case "txt", "text":
            return try convertText(path)
        default:
            throw DocumentError.unsupportedFormat(ext)
        }
    }

    // MARK: - PDF

    private static func convertPDF(_ path: String) throws -> [Chapter] {
#if os(macOS)
        let pdftotext = try requireTool(
            "pdftotext",
            hint: "Install via: brew install poppler"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pdftotext)
        process.arguments = ["-layout", path, "-"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DocumentError.conversionFailed(path, reason: "pdftotext exited with status \(process.terminationStatus)")
        }

        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw DocumentError.noExtractableText(path, hint: "The PDF may be scanned images. Consider using OCR.")
        }

        return splitByHeadings(trimmed, source: path)
#else
        throw DocumentError.unsupportedPlatform(feature: "PDF conversion")
#endif
    }

    // MARK: - Pandoc (docx, odt)

    private static func convertWithPandoc(_ path: String) throws -> [Chapter] {
#if os(macOS)
        let pandoc = try requireTool(
            "pandoc",
            hint: "Install via: brew install pandoc"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pandoc)
        process.arguments = ["-t", "markdown", "--wrap=none", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DocumentError.conversionFailed(path, reason: "pandoc exited with status \(process.terminationStatus)")
        }

        let markdown = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return splitMarkdownByH1(markdown, source: path)
#else
        throw DocumentError.unsupportedPlatform(feature: "Pandoc document conversion")
#endif
    }

    // MARK: - Markdown

    private static func convertMarkdown(_ path: String) throws -> [Chapter] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard var text = String(data: data, encoding: .utf8) else {
            throw DocumentError.conversionFailed(path, reason: "File is not valid UTF-8")
        }

        // Strip YAML frontmatter
        text = stripYAMLFrontmatter(text)

        return splitMarkdownByH1(text, source: path)
    }

    // MARK: - HTML

    private static func convertHTML(_ path: String) throws -> [Chapter] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let html = String(data: data, encoding: .utf8) else {
            throw DocumentError.conversionFailed(path, reason: "File is not valid UTF-8")
        }

        return splitHTMLByH1(html, source: path)
    }

    // MARK: - Plain text

    private static func convertText(_ path: String) throws -> [Chapter] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else {
            throw DocumentError.conversionFailed(path, reason: "File is not valid UTF-8")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DocumentError.conversionFailed(path, reason: "File is empty")
        }

        return splitByHeadings(trimmed, source: path)
    }

    // MARK: - Mobi

    private static func convertMobi(_ path: String) throws -> [Chapter] {
#if os(macOS)
        let ebookConvert = try requireTool(
            "ebook-convert",
            hint: "Install Calibre from https://calibre-ebook.com"
        )

        let tmpEpub = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_mobi_\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: tmpEpub) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ebookConvert)
        process.arguments = [path, tmpEpub.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DocumentError.conversionFailed(path, reason: "ebook-convert exited with status \(process.terminationStatus)")
        }

        return try EpubParser.parse(tmpEpub.path).chapters
#else
        throw DocumentError.unsupportedPlatform(feature: "Mobi conversion")
#endif
    }

    // MARK: - Heading splitting

    /// Split text by heading heuristics: ALL CAPS lines or "Chapter N" patterns.
    /// Falls back to single chapter if no headings detected.
    private static func splitByHeadings(_ text: String, source: String) -> [Chapter] {
        let lines = text.components(separatedBy: .newlines)
        var chapters: [Chapter] = []
        var currentTitle: String?
        var currentLines: [String] = []

        let chapterPattern = try? NSRegularExpression(pattern: "^(Chapter|CHAPTER)\\s+\\d+", options: [])

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHeading = isAllCapsHeading(trimmed) || isChapterHeading(trimmed, pattern: chapterPattern)

            if isHeading && !trimmed.isEmpty {
                // Save previous chapter
                if let title = currentTitle {
                    let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        chapters.append(Chapter(title: title, text: body))
                    }
                }
                currentTitle = trimmed
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        // Save last chapter
        if let title = currentTitle {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                chapters.append(Chapter(title: title, text: body))
            }
        }

        // Fallback: single chapter
        if chapters.isEmpty {
            let basename = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            chapters.append(Chapter(title: basename, text: text))
        }

        return chapters
    }

    private static func isAllCapsHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.count <= 80 else { return false }
        let letters = trimmed.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { $0.isUppercase }
    }

    private static func isChapterHeading(_ line: String, pattern: NSRegularExpression?) -> Bool {
        guard let pattern else { return false }
        let range = NSRange(line.startIndex..., in: line)
        return pattern.firstMatch(in: line, range: range) != nil
    }

    // MARK: - Markdown splitting

    private static func splitMarkdownByH1(_ markdown: String, source: String) -> [Chapter] {
        let lines = markdown.components(separatedBy: .newlines)
        var chapters: [Chapter] = []
        var currentTitle: String?
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("# ") && !line.hasPrefix("##") {
                // H1 heading — new chapter
                if let title = currentTitle {
                    let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        chapters.append(Chapter(title: title, text: body))
                    }
                }
                currentTitle = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }

        if let title = currentTitle {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                chapters.append(Chapter(title: title, text: body))
            }
        }

        if chapters.isEmpty {
            let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let basename = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
                chapters.append(Chapter(title: basename, text: text))
            }
        }

        return chapters
    }

    // MARK: - HTML splitting

    private static func splitHTMLByH1(_ html: String, source: String) -> [Chapter] {
        // Split on <h1> tags
        let h1Pattern = "<h1[^>]*>(.*?)</h1>"
        guard let regex = try? NSRegularExpression(pattern: h1Pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            let text = stripHTMLTags(html)
            let basename = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            return [Chapter(title: basename, text: text)]
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        if matches.isEmpty {
            let text = stripHTMLTags(html).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return [] }
            let basename = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            return [Chapter(title: basename, text: text)]
        }

        var chapters: [Chapter] = []
        for (i, match) in matches.enumerated() {
            let titleRange = Range(match.range(at: 1), in: html)!
            let title = stripHTMLTags(String(html[titleRange])).trimmingCharacters(in: .whitespacesAndNewlines)

            let bodyStart = html.index(html.startIndex, offsetBy: match.range.upperBound)
            let bodyEnd = (i + 1 < matches.count)
                ? html.index(html.startIndex, offsetBy: matches[i + 1].range.lowerBound)
                : html.endIndex
            let bodyHTML = String(html[bodyStart..<bodyEnd])
            let bodyText = stripHTMLTags(bodyHTML).trimmingCharacters(in: .whitespacesAndNewlines)

            if !title.isEmpty && !bodyText.isEmpty {
                chapters.append(Chapter(title: title, text: bodyText))
            }
        }

        return chapters
    }

    private static func stripHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    // MARK: - YAML frontmatter

    private static func stripYAMLFrontmatter(_ text: String) -> String {
        if text.hasPrefix("---") {
            let lines = text.components(separatedBy: .newlines)
            var endIndex = 0
            for (i, line) in lines.enumerated() where i > 0 {
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    endIndex = i + 1
                    break
                }
            }
            if endIndex > 0 {
                return lines[endIndex...].joined(separator: "\n")
            }
        }
        return text
    }

    // MARK: - Tool discovery

    private static func requireTool(_ name: String, hint: String) throws -> String {
        let searchPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/Applications/calibre.app/Contents/MacOS/\(name)"
        ]

        if let found = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }

        throw DocumentError.missingTool(name: name, hint: hint)
    }
}

// MARK: - Errors

/// Errors from document conversion.
public enum DocumentError: Error, CustomStringConvertible {
    case unsupportedFormat(String)
    case missingTool(name: String, hint: String)
    case conversionFailed(String, reason: String)
    case noExtractableText(String, hint: String)
    case unsupportedPlatform(feature: String)

    public var description: String {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext)"
        case .missingTool(let name, let hint):
            return "\(name) not found. \(hint)"
        case .conversionFailed(let path, let reason):
            return "Failed to convert \(path): \(reason)"
        case .noExtractableText(let path, let hint):
            return "No extractable text in \(path). \(hint)"
        case .unsupportedPlatform(let feature):
            return "\(feature) requires a macOS command adapter supplied by the host application."
        }
    }
}
