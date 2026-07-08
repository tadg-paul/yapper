// ABOUTME: Builds provider-neutral synthesis plans from preprocessed prose.
// ABOUTME: Applies engine-specific chunk constraints without re-parsing source Markdown.

import CryptoKit
import Foundation
import NaturalLanguage

public struct SpeechSourceDocument: Codable, Equatable, Sendable {
    public let sourcePath: String
    public let chapterTitle: String
    public let text: String

    public init(sourcePath: String, chapterTitle: String, text: String) {
        self.sourcePath = sourcePath
        self.chapterTitle = chapterTitle
        self.text = text
    }
}

public struct ChunkingConstraints: Codable, Equatable, Sendable {
    public let engineKind: SpeechEngineKind
    public let policyName: String
    public let maxCharacters: Int?
    public let nativePolicy: TextChunkingPolicy?

    public init(
        engineKind: SpeechEngineKind,
        policyName: String,
        maxCharacters: Int?,
        nativePolicy: TextChunkingPolicy? = nil
    ) {
        self.engineKind = engineKind
        self.policyName = policyName
        self.maxCharacters = maxCharacters
        self.nativePolicy = nativePolicy
    }

    public static let nativeYapper = ChunkingConstraints(
        engineKind: .yapper,
        policyName: TextChunkingPolicy.naturalProse.rawValue,
        maxCharacters: nil,
        nativePolicy: .naturalProse
    )

    public static let fal = ChunkingConstraints(
        engineKind: .fal,
        policyName: "remote-sentence-2500",
        maxCharacters: 2500
    )

    public static let openAI = ChunkingConstraints(
        engineKind: .openAI,
        policyName: "remote-sentence-4096",
        maxCharacters: 4096
    )
}

public struct PreparedSpeechChunk: Codable, Equatable, Sendable {
    public let chapterIndex: Int
    public let chapterTitle: String
    public let sourcePath: String
    public let chunkIndex: Int
    public let text: String
    public let previousText: String?
    public let nextText: String?
    public let characterCount: Int
    public let boundaryBefore: String
    public let containsParagraphBreak: Bool
    public let stableHash: String
}

public struct SpeechChapterPlan: Codable, Equatable, Sendable {
    public let chapterIndex: Int
    public let title: String
    public let sourcePath: String
    public let transformedText: String
    public let diagnostics: [ProsePreprocessDiagnostic]
    public let chunks: [PreparedSpeechChunk]
}

public struct SpeechConversionPlan: Codable, Equatable, Sendable {
    public let engineKind: SpeechEngineKind
    public let constraints: ChunkingConstraints
    public let chapters: [SpeechChapterPlan]

    public var chunks: [PreparedSpeechChunk] {
        chapters.flatMap(\.chunks)
    }

    public var transformedCharacterCount: Int {
        chunks.reduce(0) { $0 + $1.characterCount }
    }
}

public enum SpeechPlanner {
    public static func makePlan(
        sources: [SpeechSourceDocument],
        engineKind: SpeechEngineKind,
        substitutions: [String: String] = [:],
        engineSettingsSignature: String = ""
    ) -> SpeechConversionPlan {
        let constraints = constraintsForEngine(engineKind)
        let chapterPlans = sources.enumerated().map { index, source in
            let preprocessed = ProsePreprocessor.preprocess(source.text, substitutions: substitutions)
            let chunkInputs = chunkText(preprocessed.text, constraints: constraints)
            let prepared = prepareChunks(
                chunkInputs,
                chapterIndex: index,
                chapterTitle: source.chapterTitle,
                sourcePath: source.sourcePath,
                engineKind: engineKind,
                settingsSignature: engineSettingsSignature
            )
            return SpeechChapterPlan(
                chapterIndex: index,
                title: source.chapterTitle,
                sourcePath: source.sourcePath,
                transformedText: preprocessed.text,
                diagnostics: preprocessed.diagnostics,
                chunks: prepared
            )
        }

        return SpeechConversionPlan(
            engineKind: engineKind,
            constraints: constraints,
            chapters: chapterPlans
        )
    }

    public static func constraintsForEngine(_ engineKind: SpeechEngineKind) -> ChunkingConstraints {
        switch engineKind {
        case .yapper:
            return .nativeYapper
        case .fal:
            return .fal
        case .openAI:
            return .openAI
        case .f5:
            return ChunkingConstraints(
                engineKind: .f5,
                policyName: "local-reference-context",
                maxCharacters: 1800
            )
        }
    }

    private struct ChunkInput {
        let text: String
        let boundaryBefore: String
        let containsParagraphBreak: Bool
    }

    private static func chunkText(_ text: String, constraints: ChunkingConstraints) -> [ChunkInput] {
        if let nativePolicy = constraints.nativePolicy {
            return TextChunker().chunk(text, policy: nativePolicy).map {
                ChunkInput(
                    text: $0.text,
                    boundaryBefore: $0.boundaryBefore.rawValue,
                    containsParagraphBreak: $0.containsParagraphBreak
                )
            }
        }

        guard let maxCharacters = constraints.maxCharacters else {
            return [ChunkInput(text: text, boundaryBefore: "none", containsParagraphBreak: text.contains("\n\n"))]
        }
        return chunkByCharacters(text, maxCharacters: maxCharacters)
    }

    private static func chunkByCharacters(_ text: String, maxCharacters: Int) -> [ChunkInput] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [ChunkInput] = []
        var current = ""
        var currentContainsParagraphBreak = false

        func flush(boundaryForNext: inout String) {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            chunks.append(ChunkInput(
                text: trimmed,
                boundaryBefore: chunks.isEmpty ? "none" : boundaryForNext,
                containsParagraphBreak: currentContainsParagraphBreak
            ))
            current = ""
            currentContainsParagraphBreak = false
            boundaryForNext = "character-limit"
        }

        var nextBoundary = "none"
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let sentences = splitSentences(paragraph)
            for sentence in sentences {
                if sentence.count > maxCharacters {
                    flush(boundaryForNext: &nextBoundary)
                    for part in splitOversizedText(sentence, maxCharacters: maxCharacters) {
                        chunks.append(ChunkInput(
                            text: part,
                            boundaryBefore: chunks.isEmpty ? "none" : "character-limit",
                            containsParagraphBreak: false
                        ))
                    }
                    continue
                }

                let separator = current.isEmpty ? "" : " "
                if current.count + separator.count + sentence.count > maxCharacters {
                    flush(boundaryForNext: &nextBoundary)
                }
                if paragraphIndex > 0 && !current.isEmpty {
                    currentContainsParagraphBreak = true
                }
                current += (current.isEmpty ? "" : " ") + sentence
            }
        }
        flush(boundaryForNext: &nextBoundary)
        return chunks
    }

    private static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private static func splitOversizedText(_ text: String, maxCharacters: Int) -> [String] {
        var parts: [String] = []
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while remaining.count > maxCharacters {
            let splitIndex = remaining.index(remaining.startIndex, offsetBy: maxCharacters)
            let prefix = remaining[..<splitIndex]
            let candidate = prefix.lastIndex(where: { $0.isWhitespace }).map { remaining[..<$0] } ?? prefix
            let part = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty {
                parts.append(part)
            }
            remaining = String(remaining[candidate.endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !remaining.isEmpty {
            parts.append(remaining)
        }
        return parts
    }

    private static func prepareChunks(
        _ inputs: [ChunkInput],
        chapterIndex: Int,
        chapterTitle: String,
        sourcePath: String,
        engineKind: SpeechEngineKind,
        settingsSignature: String
    ) -> [PreparedSpeechChunk] {
        inputs.enumerated().map { chunkIndex, chunk in
            let previous = chunkIndex > 0 ? inputs[chunkIndex - 1].text : nil
            let next = chunkIndex + 1 < inputs.count ? inputs[chunkIndex + 1].text : nil
            let hash = stableHash([
                engineKind.rawValue,
                settingsSignature,
                sourcePath,
                String(chapterIndex),
                String(chunkIndex),
                chunk.text
            ].joined(separator: "\u{1f}"))
            return PreparedSpeechChunk(
                chapterIndex: chapterIndex,
                chapterTitle: chapterTitle,
                sourcePath: sourcePath,
                chunkIndex: chunkIndex,
                text: chunk.text,
                previousText: previous,
                nextText: next,
                characterCount: chunk.text.count,
                boundaryBefore: chunk.boundaryBefore,
                containsParagraphBreak: chunk.containsParagraphBreak,
                stableHash: hash
            )
        }
    }

    private static func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
