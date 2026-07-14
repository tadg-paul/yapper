// ABOUTME: Native epub parser for extracting chapters and metadata.
// ABOUTME: Supports epub 2 (NCX TOC) and epub 3 (nav TOC) formats.

import Foundation

/// A chapter extracted from a document.
public struct Chapter {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

/// Metadata extracted from an epub.
public struct EpubMetadata {
    public let title: String?
    public let author: String?
    public let coverImagePath: String?
}

/// Result of parsing an epub file.
public struct EpubParseResult {
    public let chapters: [Chapter]
    public let metadata: EpubMetadata
}

/// Parses epub files to extract chapter structure, text content, and metadata.
public struct EpubParser {

    /// Parse an epub file at the given path.
    ///
    /// - Parameter path: path to the .epub file
    /// - Returns: parsed chapters and metadata
    /// - Throws: if the file is not a valid epub
    public static func parse(_ path: String) throws -> EpubParseResult {
        let url = URL(fileURLWithPath: path)

        // Validate file exists
        guard FileManager.default.fileExists(atPath: path) else {
            throw EpubError.fileNotFound(path)
        }

        // Validate it's a ZIP (epub is a ZIP archive)
        guard isZipFile(at: url) else {
            throw EpubError.notAnEpub(path, reason: "File is not a ZIP archive")
        }

        // Unzip to temp directory
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_epub_\(UUID().uuidString)")
        try unzipEpub(at: url, to: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Parse container.xml to find OPF path
        let containerPath = tmpDir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerPath.path) else {
            throw EpubError.invalidEpub(path, reason: "Missing META-INF/container.xml")
        }
        let opfRelPath = try parseContainer(containerPath)
        let opfDir = tmpDir.appendingPathComponent(opfRelPath).deletingLastPathComponent()
        let opfPath = tmpDir.appendingPathComponent(opfRelPath)

        guard FileManager.default.fileExists(atPath: opfPath.path) else {
            throw EpubError.invalidEpub(path, reason: "OPF file not found: \(opfRelPath)")
        }

        // Parse OPF
        let opfResult = try parseOPF(opfPath, baseDir: opfDir)

        // Parse TOC (try NCX first, then nav)
        var tocEntries: [(title: String, href: String)] = []
        if let ncxPath = opfResult.ncxPath {
            let fullNcxPath = opfDir.appendingPathComponent(ncxPath)
            if FileManager.default.fileExists(atPath: fullNcxPath.path) {
                tocEntries = try parseNCX(fullNcxPath)
            }
        }
        if tocEntries.isEmpty, let navPath = opfResult.navPath {
            let fullNavPath = opfDir.appendingPathComponent(navPath)
            if FileManager.default.fileExists(atPath: fullNavPath.path) {
                tocEntries = try parseNav(fullNavPath)
            }
        }

        // Build chapters
        var chapters: [Chapter] = []
        if tocEntries.isEmpty {
            // No TOC — single chapter from all spine items
            var allText = ""
            for href in opfResult.spineHrefs {
                let contentPath = opfDir.appendingPathComponent(href)
                if let text = try? extractText(from: contentPath) {
                    if !allText.isEmpty { allText += "\n\n" }
                    allText += text
                }
            }
            let trimmed = allText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chapters.append(Chapter(title: opfResult.metadata.title ?? "Untitled", text: trimmed))
            }
        } else {
            for entry in tocEntries {
                let href = entry.href.components(separatedBy: "#").first ?? entry.href
                let contentPath = opfDir.appendingPathComponent(href)
                if let text = try? extractText(from: contentPath) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        chapters.append(Chapter(title: entry.title, text: trimmed))
                    }
                }
            }
        }

        return EpubParseResult(chapters: chapters, metadata: opfResult.metadata)
    }

    // MARK: - ZIP handling

    private static func isZipFile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 4 else { return false }
        // ZIP magic number: PK\x03\x04
        return data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04
    }

    private static func unzipEpub(at source: URL, to destination: URL) throws {
#if os(macOS)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", source.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EpubError.notAnEpub(source.path, reason: "Failed to unzip")
        }
#else
        throw EpubError.notAnEpub(
            source.path,
            reason: "Epub extraction requires an archive adapter supplied by the host application"
        )
#endif
    }

    // MARK: - container.xml

    private static func parseContainer(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let parser = SimpleXMLParser(data: data)
        parser.parse()
        guard let opfPath = parser.rootfilePath else {
            throw EpubError.invalidEpub(url.path, reason: "No rootfile in container.xml")
        }
        return opfPath
    }

    // MARK: - OPF parsing

    struct OPFResult {
        let metadata: EpubMetadata
        let spineHrefs: [String]
        let ncxPath: String?
        let navPath: String?
    }

    private static func parseOPF(_ url: URL, baseDir: URL) throws -> OPFResult {
        let data = try Data(contentsOf: url)
        let parser = OPFParser(data: data)
        parser.parse()

        let metadata = EpubMetadata(
            title: parser.title,
            author: parser.author,
            coverImagePath: parser.coverHref
        )

        // Map spine itemrefs to manifest hrefs
        var spineHrefs: [String] = []
        for idref in parser.spineIdrefs {
            if let href = parser.manifestItems[idref] {
                spineHrefs.append(href)
            }
        }

        return OPFResult(
            metadata: metadata,
            spineHrefs: spineHrefs,
            ncxPath: parser.ncxHref,
            navPath: parser.navHref
        )
    }

    // MARK: - NCX parsing (epub 2)

    private static func parseNCX(_ url: URL) throws -> [(title: String, href: String)] {
        let data = try Data(contentsOf: url)
        let parser = NCXParser(data: data)
        parser.parse()
        return parser.entries
    }

    // MARK: - Nav parsing (epub 3)

    private static func parseNav(_ url: URL) throws -> [(title: String, href: String)] {
        let data = try Data(contentsOf: url)
        let parser = NavParser(data: data)
        parser.parse()
        return parser.entries
    }

    // MARK: - Text extraction

    private static func extractText(from url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard var html = String(data: data, encoding: .utf8) else { return nil }

        // Strip HTML tags
        html = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        html = decodeHTMLEntities(html)

        // Normalise whitespace
        html = html.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#8216;", "\u{2018}"), // left single quote
            ("&#8217;", "\u{2019}"), // right single quote
            ("&#8220;", "\u{201C}"), // left double quote
            ("&#8221;", "\u{201D}"), // right double quote
            ("&#8211;", "\u{2013}"), // en dash
            ("&#8212;", "\u{2014}"), // em dash
            ("&nbsp;", " "),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Numeric entities: &#NNN; or &#xHHH;
        let numericPattern = "&#(x?)([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                let isHex = Range(match.range(at: 1), in: result).map { !result[$0].isEmpty } ?? false
                if let numRange = Range(match.range(at: 2), in: result),
                   let fullRange = Range(match.range, in: result) {
                    let numStr = String(result[numRange])
                    let codePoint = isHex
                        ? UInt32(numStr, radix: 16)
                        : UInt32(numStr, radix: 10)
                    if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                        result.replaceSubrange(fullRange, with: String(Character(scalar)))
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Errors

enum EpubError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case notAnEpub(String, reason: String)
    case invalidEpub(String, reason: String)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .notAnEpub(let path, let reason):
            return "Not a valid epub: \(path) (\(reason))"
        case .invalidEpub(let path, let reason):
            return "Invalid epub: \(path) (\(reason))"
        }
    }
}

// MARK: - XML Parsers

/// Parses container.xml to extract the OPF rootfile path.
private class SimpleXMLParser: NSObject, XMLParserDelegate {
    let xmlParser: XMLParser
    var rootfilePath: String?

    init(data: Data) {
        xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() { xmlParser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile" || elementName.hasSuffix(":rootfile") {
            rootfilePath = attributeDict["full-path"]
        }
    }
}

/// Parses the OPF file for metadata, manifest, and spine.
private class OPFParser: NSObject, XMLParserDelegate {
    let xmlParser: XMLParser
    var title: String?
    var author: String?
    var coverHref: String?
    var manifestItems: [String: String] = [:]  // id -> href
    var spineIdrefs: [String] = []
    var ncxHref: String?
    var navHref: String?

    private var currentElement = ""
    private var currentText = ""
    private var coverId: String?
    private var itemMediaTypes: [String: String] = [:]  // id -> media-type
    private var itemProperties: [String: String] = [:]  // id -> properties

    init(data: Data) {
        xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()

        // Resolve cover image href
        if let coverId, let href = manifestItems[coverId] {
            coverHref = href
        }

        // Find NCX by media-type
        for (id, mediaType) in itemMediaTypes {
            if mediaType == "application/x-dtbncx+xml" {
                ncxHref = manifestItems[id]
            }
        }

        // Find nav by properties
        for (id, props) in itemProperties {
            if props.contains("nav") {
                navHref = manifestItems[id]
            }
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        currentElement = local
        currentText = ""

        switch local {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifestItems[id] = href
                if let mediaType = attributeDict["media-type"] {
                    itemMediaTypes[id] = mediaType
                }
                if let props = attributeDict["properties"] {
                    itemProperties[id] = props
                }
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spineIdrefs.append(idref)
            }
        case "meta":
            if attributeDict["name"] == "cover" {
                coverId = attributeDict["content"]
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch local {
        case "title":
            if title == nil && !trimmed.isEmpty { title = trimmed }
        case "creator":
            if author == nil && !trimmed.isEmpty { author = trimmed }
        default:
            break
        }
    }
}

/// Parses NCX (epub 2) table of contents.
private class NCXParser: NSObject, XMLParserDelegate {
    let xmlParser: XMLParser
    var entries: [(title: String, href: String)] = []

    private var inNavPoint = false
    private var inText = false
    private var currentTitle = ""
    private var currentHref = ""

    init(data: Data) {
        xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() { xmlParser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "navPoint":
            inNavPoint = true
            currentTitle = ""
            currentHref = ""
        case "text":
            if inNavPoint { inText = true }
        case "content":
            if inNavPoint, let src = attributeDict["src"] {
                currentHref = src
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { currentTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "text":
            inText = false
        case "navPoint":
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && !currentHref.isEmpty {
                entries.append((title: title, href: currentHref))
            }
            inNavPoint = false
        default:
            break
        }
    }
}

/// Parses nav document (epub 3) table of contents.
private class NavParser: NSObject, XMLParserDelegate {
    let xmlParser: XMLParser
    var entries: [(title: String, href: String)] = []

    private var inNav = false
    private var inLink = false
    private var currentTitle = ""
    private var currentHref = ""
    private var depth = 0

    init(data: Data) {
        xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() { xmlParser.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "nav":
            if attributeDict["epub:type"] == "toc" ||
               attributeDict["type"] == "toc" ||
               (attributeDict.isEmpty && !inNav) {
                inNav = true
            }
        case "a":
            if inNav, let href = attributeDict["href"] {
                inLink = true
                currentHref = href
                currentTitle = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inLink { currentTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "a":
            if inLink {
                let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty && !currentHref.isEmpty {
                    entries.append((title: title, href: currentHref))
                }
                inLink = false
            }
        case "nav":
            inNav = false
        default:
            break
        }
    }
}
