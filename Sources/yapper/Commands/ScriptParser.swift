// ABOUTME: Parses play/screenplay scripts into structured dialogue and stage directions.
// ABOUTME: Supports markdown and org-mode formats with character detection and scene boundaries.

import Foundation
import YapperKit

/// A single entry in a parsed script — dialogue, stage direction, or transition.
struct ScriptEntry {
    enum EntryType {
        case dialogue(character: String)
        case stageDirection
        case transition
    }
    let type: EntryType
    let text: String
}

/// A scene in a parsed script, containing a title and a sequence of entries.
struct ScriptScene {
    let title: String
    var entries: [ScriptEntry]
}

/// The fully parsed script structure.
struct ScriptDocument {
    var title: String?
    var subtitle: String?
    var author: String?
    var characters: [String]
    var characterDescriptions: [(name: String, description: String)]
    var outline: String?
    var preamble: [String]
    var scenes: [ScriptScene]
    var footnotes: [String: String]
}

/// Detects whether a file contains script patterns and parses accordingly.
struct ScriptParser {

    /// Attempt to parse a file as a script. Returns nil if no script patterns found.
    static func parse(filePath: String, config: ScriptConfig?) throws -> ScriptDocument? {
        let knownChars: Set<String>
        if let keys = config?.characterVoices?.keys {
            knownChars = Set(keys.map { $0.uppercased() })
        } else {
            knownChars = []
        }
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        switch ext {
        case "org":
            return parseOrg(content: content, config: config, knownCharacters: knownChars)
        case "md", "markdown":
            return parseMd(content: content, config: config, knownCharacters: knownChars)
        case "fountain", "spmd":
            return parseFountain(content: content, config: config, knownCharacters: knownChars)
        default:
            return nil
        }
    }

    // MARK: - Markdown parser

    /// Parse markdown-format script.
    /// `**CHARACTER:**` at line start = dialogue.
    /// `*italic text*` at line start = stage direction.
    /// `### Scene Title` = scene boundary.
    private static func parseMd(content: String, config: ScriptConfig?, knownCharacters: Set<String>) -> ScriptDocument? {
        let lines = content.components(separatedBy: "\n")

        // Check for script patterns in first 100 lines.
        // Match **ANYTHING:** where the content starts with an ALL-CAPS word.
        // Handles: **BOB:**, **BOB softly:**, **BOB (softly):**, **BOB, firmly:**
        let sample = lines.prefix(100).joined(separator: "\n")
        let dialoguePattern = try? NSRegularExpression(pattern: #"^\*\*[A-Z\u00C0-\u024F][^*]*:?\*\*"#, options: .anchorsMatchLines)
        let sampleRange = NSRange(sample.startIndex..., in: sample)
        let matchCount = dialoguePattern?.numberOfMatches(in: sample, range: sampleRange) ?? 0
        if matchCount < 2 {
            return nil // Not a script
        }

        var title: String?
        let subtitle: String? = nil
        var author: String?
        var scenes: [ScriptScene] = []
        var currentScene = ScriptScene(title: "Untitled", entries: [])
        var currentCharacter: String?
        var dialogueLines: [String] = []
        var characters = Set<String>()
        var sceneStarted = false
        var preambleLines: [String] = []
        var footnotes: [String: String] = [:]
        var inPreambleArea = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract metadata
            if trimmed.hasPrefix("# ") && title == nil {
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("*by ") && trimmed.hasSuffix("*") && author == nil {
                author = String(trimmed.dropFirst(4).dropLast(1)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Markdown footnote definitions: [^name]: definition
            if trimmed.hasPrefix("[^") {
                if let closeBracket = trimmed.firstIndex(of: "]"),
                   trimmed[trimmed.index(after: closeBracket)...].hasPrefix(":") {
                    let name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<closeBracket])
                    let definition = String(trimmed[trimmed.index(closeBracket, offsetBy: 2)...])
                        .trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty && !definition.isEmpty {
                        footnotes[name] = definition
                    }
                }
                continue
            }

            // Scene boundary: ### heading
            if trimmed.hasPrefix("### ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                if sceneStarted {
                    scenes.append(currentScene)
                }
                let sceneTitle = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentScene = ScriptScene(title: sceneTitle, entries: [])
                sceneStarted = true
                inPreambleArea = false
                continue
            }

            // Skip ## headings (act markers)
            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                inPreambleArea = false
                continue
            }

            // Preamble text: before first scene, not metadata, not empty
            if inPreambleArea && !trimmed.isEmpty {
                // Skip italic lines in preamble (they're not stage directions yet)
                if !(trimmed.hasPrefix("*") && trimmed.hasSuffix("*")) {
                    preambleLines.append(trimmed)
                }
                continue
            }

            // Stage direction: *italic text* (single asterisks, full line)
            if trimmed.hasPrefix("*") && !trimmed.hasPrefix("**") && trimmed.hasSuffix("*") && trimmed.count > 2 {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let stageText = String(trimmed.dropFirst(1).dropLast(1)).trimmingCharacters(in: .whitespaces)
                if !stageText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .stageDirection, text: stageText))
                }
                continue
            }

            // Transition: blockquote (> ) in script mode
            if trimmed.hasPrefix("> ") && !inPreambleArea {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let transText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !transText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .transition, text: transText))
                }
                continue
            }

            // Dialogue attribution: **CHARACTER:** or **CHARACTER (notes):**
            if trimmed.hasPrefix("**") {
                if let endBold = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) {
                    flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                    var charRaw = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<endBold.lowerBound])
                    if charRaw.hasSuffix(":") { charRaw = String(charRaw.dropLast()) }
                    let charName = extractCharacterName(charRaw, knownCharacters: knownCharacters)
                    if !charName.isEmpty {
                        currentCharacter = charName
                    }
                    continue
                }
            }

            // Dialogue text (continuation of current character)
            if currentCharacter != nil && !trimmed.isEmpty {
                dialogueLines.append(trimmed)
            }
        }

        // Flush remaining
        flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
        if sceneStarted {
            scenes.append(currentScene)
        }

        if scenes.isEmpty && !currentScene.entries.isEmpty {
            scenes.append(currentScene)
        }

        guard !scenes.isEmpty else { return nil }

        return ScriptDocument(
            title: config?.title ?? title,
            subtitle: config?.subtitle ?? subtitle,
            author: config?.author ?? author,
            characters: Array(characters).sorted(),
            characterDescriptions: [],
            outline: nil,
            preamble: preambleLines,
            scenes: scenes,
            footnotes: footnotes
        )
    }

    // MARK: - Org-mode parser

    /// Parse org-mode-format script.
    /// `***` (L3 heading) = stage direction.
    /// `****` (L4 heading) = dialogue attribution.
    /// Body text below L4 = dialogue.
    private static func parseOrg(content: String, config: ScriptConfig?, knownCharacters: Set<String>) -> ScriptDocument? {
        let lines = content.components(separatedBy: "\n")

        var title: String?
        var subtitle: String?
        var author: String?
        var scenes: [ScriptScene] = []
        var currentScene = ScriptScene(title: "Untitled", entries: [])
        var currentCharacter: String?
        var dialogueLines: [String] = []
        var characters = Set<String>()
        var sceneStarted = false

        // Preamble content
        var charDescriptions: [(name: String, description: String)] = []
        var outline: String?
        var preambleLines: [String] = []
        var footnotes: [String: String] = [:]

        // Track which L1 heading we're under (for preamble extraction)
        var currentL1Heading: String?
        var inPreambleArea = true  // Before first scene

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract org metadata
            if trimmed.hasPrefix("#+TITLE:") && title == nil {
                title = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("#+SUBTITLE:") && subtitle == nil {
                subtitle = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("#+AUTHOR:") && author == nil {
                author = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                continue
            }
            // Skip other org directives
            if trimmed.hasPrefix("#+") { continue }

            // Footnote definitions: [fn:name] definition text
            if trimmed.hasPrefix("[fn:") {
                if let closeBracket = trimmed.firstIndex(of: "]") {
                    let name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<closeBracket])
                    let definition = String(trimmed[trimmed.index(after: closeBracket)...])
                        .trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty && !definition.isEmpty {
                        footnotes[name] = definition
                    }
                }
                continue
            }

            // Scene boundary: ** heading (L2)
            if trimmed.hasPrefix("** ") && !trimmed.hasPrefix("*** ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                if sceneStarted {
                    scenes.append(currentScene)
                }
                let sceneTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentScene = ScriptScene(title: sceneTitle, entries: [])
                sceneStarted = true
                inPreambleArea = false
                continue
            }

            // Transition: ***** heading (L5)
            if trimmed.hasPrefix("***** ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let transText = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !transText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .transition, text: transText))
                }
                continue
            }

            // Dialogue attribution: **** CHARACTER or **** CHARACTER (notes)
            if trimmed.hasPrefix("**** ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let charRaw = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let charName = extractCharacterName(charRaw, knownCharacters: knownCharacters)
                if !charName.isEmpty {
                    currentCharacter = charName
                }
                continue
            }

            // Stage direction: *** heading (L3)
            if trimmed.hasPrefix("*** ") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                let stageText = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if !stageText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .stageDirection, text: stageText))
                }
                continue
            }

            // L1 heading: track for preamble section detection
            if trimmed.hasPrefix("* ") {
                let heading = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentL1Heading = heading.lowercased()
                continue
            }

            // In preamble area: extract character descriptions and outline
            if inPreambleArea {
                // Parse org table rows for character descriptions
                if trimmed.hasPrefix("|") && !trimmed.hasPrefix("|---") {
                    let cells = trimmed.split(separator: "|").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    if cells.count >= 2 {
                        let name = cells[0]
                        let desc = cells[1]
                        if !name.isEmpty && !desc.isEmpty {
                            charDescriptions.append((name: name, description: desc))
                        }
                    }
                    continue
                }
                // Table separator rows
                if trimmed.hasPrefix("|---") { continue }

                // Outline section body text
                if currentL1Heading == "outline" && !trimmed.isEmpty {
                    outline = trimmed
                    continue
                }

                // Other preamble text (not in a table, not empty)
                if !trimmed.isEmpty && currentL1Heading != nil {
                    preambleLines.append(trimmed)
                }
                continue
            }

            // Skip table rows and empty lines outside dialogue
            if trimmed.hasPrefix("|") || trimmed.isEmpty {
                if currentCharacter == nil { continue }
            }

            // Dialogue text (continuation of current character)
            if currentCharacter != nil && !trimmed.isEmpty {
                dialogueLines.append(trimmed)
            }
        }

        // Flush remaining
        flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
        if sceneStarted {
            scenes.append(currentScene)
        }

        if scenes.isEmpty && !currentScene.entries.isEmpty {
            scenes.append(currentScene)
        }

        guard !scenes.isEmpty else { return nil }

        return ScriptDocument(
            title: config?.title ?? title,
            subtitle: config?.subtitle ?? subtitle,
            author: config?.author ?? author,
            characters: Array(characters).sorted(),
            characterDescriptions: charDescriptions,
            outline: outline,
            preamble: preambleLines,
            scenes: scenes,
            footnotes: footnotes
        )
    }

    // MARK: - Character name extraction

    // MARK: - Fountain parser

    /// Parse Fountain screenplay format.
    /// Scene headings: INT./EXT./EST./I/E or forced with leading period.
    /// Character: ALL-CAPS line preceded by blank line.
    /// Dialogue: text following character line.
    /// Action: everything else (becomes stage direction).
    private static func parseFountain(content: String, config: ScriptConfig?, knownCharacters: Set<String>) -> ScriptDocument? {
        // Strip boneyard (/* ... */) first
        var cleaned = content
        if let boneyardRegex = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = boneyardRegex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Strip notes ([[ ... ]])
        if let noteRegex = try? NSRegularExpression(pattern: #"\[\[.*?\]\]"#, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = noteRegex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Strip emphasis markers (*italic*, **bold**, ***bold-italic***, _underline_)
        cleaned = stripEmphasis(cleaned)

        let lines = cleaned.components(separatedBy: "\n")

        var title: String?
        var subtitle: String?
        var author: String?
        var preambleLines: [String] = []
        var scenes: [ScriptScene] = []
        var currentScene = ScriptScene(title: "Untitled", entries: [])
        var currentCharacter: String?
        var dialogueLines: [String] = []
        var characters = Set<String>()
        var sceneStarted = false
        var inTitlePage = true
        var inDialogue = false

        // Scene heading pattern: INT, EXT, EST, INT./EXT, INT/EXT, I/E
        let sceneHeadingPrefixes = ["INT.", "EXT.", "EST.", "INT./EXT.", "INT/EXT.", "I/E.",
                                     "INT ", "EXT ", "EST ", "INT./EXT ", "INT/EXT ", "I/E "]

        func isSceneHeading(_ line: String) -> Bool {
            let upper = line.uppercased()
            // Forced scene heading: leading period
            if line.hasPrefix(".") && line.count > 1 && !line.hasPrefix("..") {
                return true
            }
            for prefix in sceneHeadingPrefixes {
                if upper.hasPrefix(prefix) { return true }
            }
            return false
        }

        func isCharacterLine(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            // Forced character: leading @
            if trimmed.hasPrefix("@") { return true }
            // Must contain at least one letter
            guard trimmed.contains(where: { $0.isLetter }) else { return false }
            // Strip parenthetical extension for the check
            var nameOnly = trimmed
            if let parenStart = nameOnly.firstIndex(of: "(") {
                nameOnly = String(nameOnly[..<parenStart]).trimmingCharacters(in: .whitespaces)
            }
            // All letters must be uppercase (allows numbers, punctuation)
            let letters = nameOnly.filter { $0.isLetter }
            return !letters.isEmpty && letters.allSatisfy { $0.isUppercase }
        }

        func isTransition(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Forced transition: leading >
            if trimmed.hasPrefix(">") && !trimmed.hasSuffix("<") { return true }
            // Standard: all uppercase ending in TO:
            let upper = trimmed.uppercased()
            return trimmed == upper && trimmed.hasSuffix("TO:")
        }

        func isParenthetical(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        }

        func isForcedAction(_ line: String) -> Bool {
            return line.hasPrefix("!")
        }

        func isCenteredText(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix(">") && trimmed.hasSuffix("<")
        }

        func cleanSceneTitle(_ line: String) -> String {
            var title = line
            // Strip forced heading prefix
            if title.hasPrefix(".") { title = String(title.dropFirst()) }
            // Strip scene numbers (#number#)
            if let regex = try? NSRegularExpression(pattern: #"\s*#[^#]+#\s*$"#) {
                let range = NSRange(title.startIndex..., in: title)
                title = regex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
            }
            return title.trimmingCharacters(in: .whitespaces)
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Title page: key-value pairs at file start, before first blank line
            if inTitlePage {
                if trimmed.isEmpty {
                    inTitlePage = false
                    i += 1
                    continue
                }
                // Key: Value format
                if let colonIdx = trimmed.firstIndex(of: ":"), colonIdx != trimmed.startIndex {
                    let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                    let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                    // Check for multi-line values (indented continuation lines)
                    var fullValue = value
                    while i + 1 < lines.count {
                        let nextLine = lines[i + 1]
                        if nextLine.hasPrefix("   ") || nextLine.hasPrefix("\t") {
                            let continued = nextLine.trimmingCharacters(in: .whitespaces)
                            if fullValue.isEmpty {
                                fullValue = continued
                            } else {
                                fullValue += " " + continued
                            }
                            i += 1
                        } else {
                            break
                        }
                    }

                    switch key {
                    case "title":
                        title = fullValue
                    case "subtitle":
                        subtitle = fullValue
                    case "author":
                        author = fullValue
                    default:
                        if !fullValue.isEmpty {
                            preambleLines.append("\(key.capitalized): \(fullValue)")
                        }
                    }
                }
                i += 1
                continue
            }

            // Skip empty lines (they're paragraph delimiters)
            if trimmed.isEmpty {
                // Flush dialogue if we were in dialogue mode
                if inDialogue {
                    flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                    inDialogue = false
                }
                i += 1
                continue
            }

            // Page break (===)
            if trimmed.hasPrefix("===") && trimmed.allSatisfy({ $0 == "=" || $0 == " " }) {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                inDialogue = false
                i += 1
                continue
            }

            // Synopses (= text) — collect for outline
            if trimmed.hasPrefix("= ") {
                let synopsis = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !synopsis.isEmpty { preambleLines.append(synopsis) }
                i += 1
                continue
            }

            // Sections (# headers) — structural markers
            if trimmed.hasPrefix("#") && !trimmed.hasPrefix("##") {
                i += 1
                continue
            }
            if trimmed.hasPrefix("##") {
                i += 1
                continue
            }

            // Lyrics (~text) — render as stage direction
            if trimmed.hasPrefix("~") {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                inDialogue = false
                let lyricText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !lyricText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .stageDirection, text: lyricText))
                }
                i += 1
                continue
            }

            // Centered text (>text<) — stage direction
            if isCenteredText(trimmed) {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                inDialogue = false
                var centered = trimmed
                if centered.hasPrefix(">") { centered = String(centered.dropFirst()) }
                if centered.hasSuffix("<") { centered = String(centered.dropLast()) }
                centered = centered.trimmingCharacters(in: .whitespaces)
                if !centered.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .stageDirection, text: centered))
                }
                i += 1
                continue
            }

            // Scene heading
            if isSceneHeading(trimmed) {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                inDialogue = false
                if sceneStarted {
                    scenes.append(currentScene)
                }
                let sceneTitle = cleanSceneTitle(trimmed)
                currentScene = ScriptScene(title: sceneTitle, entries: [])
                sceneStarted = true
                i += 1
                continue
            }

            // In dialogue mode: continuation or parenthetical
            if inDialogue && currentCharacter != nil {
                if isParenthetical(trimmed) {
                    // Skip parentheticals
                    i += 1
                    continue
                }
                // Dialogue continuation
                dialogueLines.append(trimmed)
                i += 1
                continue
            }

            // Forced action (!text)
            if isForcedAction(trimmed) {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                inDialogue = false
                let actionText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !actionText.isEmpty {
                    currentScene.entries.append(ScriptEntry(type: .stageDirection, text: actionText))
                }
                i += 1
                continue
            }

            // Transition (CUT TO: etc.)
            if isTransition(trimmed) {
                flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
                inDialogue = false
                var transText = trimmed
                if transText.hasPrefix(">") { transText = String(transText.dropFirst()).trimmingCharacters(in: .whitespaces) }
                currentScene.entries.append(ScriptEntry(type: .transition, text: transText))
                i += 1
                continue
            }

            // Character line: ALL CAPS, check if next non-blank line is dialogue
            if isCharacterLine(trimmed) {
                // Peek ahead: next non-blank line should be dialogue or parenthetical
                var nextContentIdx = i + 1
                while nextContentIdx < lines.count && lines[nextContentIdx].trimmingCharacters(in: .whitespaces).isEmpty {
                    nextContentIdx += 1
                }

                // If next line exists and isn't blank, this is likely a character
                // (Fountain spec: character must not be followed by blank line)
                if nextContentIdx == i + 1 && nextContentIdx < lines.count {
                    flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)

                    var charRaw = trimmed
                    // Strip forced character prefix
                    if charRaw.hasPrefix("@") { charRaw = String(charRaw.dropFirst()) }
                    // Strip dual dialogue caret
                    if charRaw.hasSuffix("^") { charRaw = String(charRaw.dropLast()).trimmingCharacters(in: .whitespaces) }

                    let charName = extractCharacterName(charRaw, knownCharacters: knownCharacters)
                    if !charName.isEmpty {
                        currentCharacter = charName
                        inDialogue = true
                    }
                    i += 1
                    continue
                }
            }

            // Default: action (stage direction)
            flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
            inDialogue = false
            if !trimmed.isEmpty {
                currentScene.entries.append(ScriptEntry(type: .stageDirection, text: trimmed))
            }
            i += 1
        }

        // Flush remaining
        flushDialogue(&currentCharacter, &dialogueLines, &currentScene, &characters)
        if sceneStarted {
            scenes.append(currentScene)
        }
        if scenes.isEmpty && !currentScene.entries.isEmpty {
            scenes.append(currentScene)
        }

        guard !scenes.isEmpty else { return nil }

        return ScriptDocument(
            title: config?.title ?? title,
            subtitle: config?.subtitle ?? subtitle,
            author: config?.author ?? author,
            characters: Array(characters).sorted(),
            characterDescriptions: [],
            outline: preambleLines.isEmpty ? nil : preambleLines.joined(separator: " "),
            preamble: [],
            scenes: scenes,
            footnotes: [:]
        )
    }

    // MARK: - Emphasis stripping

    /// Strip emphasis markers from text: *italic*, **bold**, ***bold-italic***, _underline_.
    static func stripEmphasis(_ text: String) -> String {
        var result = text
        // Order matters: strip *** before ** before *
        let patterns: [(String, String)] = [
            (#"\*\*\*(.+?)\*\*\*"#, "$1"),   // ***bold-italic***
            (#"\*\*(.+?)\*\*"#, "$1"),         // **bold**
            (#"\*(.+?)\*"#, "$1"),             // *italic*
            (#"_(.+?)_"#, "$1"),               // _underline_
        ]
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
            }
        }
        return result
    }

    // MARK: - Character name extraction

    /// Extract the character name from an attribution line, stripping acting
    /// directions. ALL-CAPS words are character name, first non-caps word
    /// starts the direction which is discarded.
    ///
    /// Examples:
    ///   `KEVIN` → KEVIN
    ///   `KEVIN softly` → KEVIN
    ///   `KEVIN, softly` → KEVIN
    ///   `KEVIN (softly)` → KEVIN
    ///   `KEVIN, (softly)` → KEVIN
    ///   `KEVIN Softly` → KEVIN
    ///   `GDA CONLON` → GDA CONLON (multi-word, all caps)
    ///   `CÁIT gives him a look.` → CÁIT
    ///   `KEVIN offstage, sounding closer` → KEVIN
    private static func extractCharacterName(
        _ raw: String,
        knownCharacters: Set<String>
    ) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)

        // Strip parenthesised content
        if let parenStart = text.firstIndex(of: "(") {
            text = String(text[..<parenStart]).trimmingCharacters(in: .whitespaces)
        }

        // Strip trailing comma and everything after
        if let commaIdx = text.firstIndex(of: ",") {
            text = String(text[..<commaIdx]).trimmingCharacters(in: .whitespaces)
        }

        // Take only leading ALL-CAPS words. A word is ALL-CAPS if every letter
        // in it is uppercase (handles accented characters like CÁIT).
        // Stop at the first word that contains any lowercase letter.
        let words = text.components(separatedBy: .whitespaces)
        var nameWords: [String] = []
        for word in words {
            guard !word.isEmpty else { continue }
            let letters = word.filter { $0.isLetter }
            if letters.isEmpty {
                // Punctuation-only token — skip
                continue
            }
            let allUpper = letters.allSatisfy { $0.isUppercase }
            if allUpper {
                nameWords.append(word)
            } else {
                break
            }
        }

        let name = nameWords.joined(separator: " ")
        return name.isEmpty ? text : name
    }

    // MARK: - Helpers

    private static func flushDialogue(
        _ character: inout String?,
        _ lines: inout [String],
        _ scene: inout ScriptScene,
        _ characters: inout Set<String>
    ) {
        guard let char = character, !lines.isEmpty else {
            character = nil
            lines.removeAll()
            return
        }
        characters.insert(char)
        let text = lines.joined(separator: " ")
        scene.entries.append(ScriptEntry(type: .dialogue(character: char), text: text))
        character = nil
        lines.removeAll()
    }

    // MARK: - Stage direction character name Title Case

    /// Replace ALL-CAPS character names in stage direction text with Title Case.
    ///
    /// Example: "KEVIN enters the room" → "Kevin enters the room"
    ///          "GDA CONLON enters behind KEVIN" → "Gda Conlon enters behind Kevin"
    static func titleCaseCharacterNames(
        in text: String,
        knownCharacters: Set<String>
    ) -> String {
        var result = text
        // Sort by length descending so multi-word names are matched first
        let sorted = knownCharacters.sorted { $0.count > $1.count }
        for name in sorted {
            let titleCased = name.split(separator: " ").map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }.joined(separator: " ")

            // Replace whole-word occurrences using word boundary regex
            let escaped = NSRegularExpression.escapedPattern(for: name)
            if let regex = try? NSRegularExpression(
                pattern: "\\b\(escaped)\\b",
                options: []
            ) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: titleCased
                )
            }
        }
        return result
    }

    // MARK: - Footnote processing

    /// Strip footnote references from text and return the referenced names.
    ///
    /// Handles both org-mode `[fn:name]` and markdown `[^name]` patterns.
    /// Returns the cleaned text and an ordered list of footnote names found.
    static func stripFootnoteReferences(_ text: String) -> (text: String, footnoteNames: [String]) {
        var result = text
        var names: [String] = []

        // Org-mode: [fn:name]
        let orgPattern = try? NSRegularExpression(pattern: #"\[fn:([^\]]+)\]"#)
        if let regex = orgPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)
            for match in matches.reversed() {
                if match.numberOfRanges >= 2,
                   let nameRange = Range(match.range(at: 1), in: result) {
                    names.insert(String(result[nameRange]), at: 0)
                }
                if let fullRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullRange, with: "")
                }
            }
        }

        // Markdown: [^name]
        let mdPattern = try? NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#)
        if let regex = mdPattern {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)
            for match in matches.reversed() {
                if match.numberOfRanges >= 2,
                   let nameRange = Range(match.range(at: 1), in: result) {
                    names.insert(String(result[nameRange]), at: 0)
                }
                if let fullRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullRange, with: "")
                }
            }
        }

        return (result.trimmingCharacters(in: .whitespaces), names)
    }
}
