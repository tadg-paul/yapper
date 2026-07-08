// ABOUTME: Splits long text into chunks within the 510-token budget.
// ABOUTME: Uses NLTokenizer for sentence boundary detection.

import Foundation
import NaturalLanguage

public enum TextChunkingPolicy: String, Codable, Equatable, Sendable {
    case naturalProse = "natural-prose"
    case paragraphBounded = "paragraph-bounded"
}

public enum TextChunkBoundary: String, Equatable, Sendable {
    case none
    case paragraph
    case tokenBudget = "token-budget"
    case oversizedSentence = "oversized-sentence"
}

/// A chunk of text sized to fit within Kokoro's 510-token limit.
public struct TextChunk: Sendable {
    /// The text content of this chunk.
    public let text: String
    /// Estimated phoneme token count for this chunk.
    public let estimatedTokenCount: Int
    /// Why this chunk starts at a boundary.
    public let boundaryBefore: TextChunkBoundary
    /// Whether this chunk contains at least one source paragraph break.
    public let containsParagraphBreak: Bool

    public init(
        text: String,
        estimatedTokenCount: Int,
        boundaryBefore: TextChunkBoundary = .none,
        containsParagraphBreak: Bool = false
    ) {
        self.text = text
        self.estimatedTokenCount = estimatedTokenCount
        self.boundaryBefore = boundaryBefore
        self.containsParagraphBreak = containsParagraphBreak
    }
}

/// Splits text into chunks at sentence boundaries, each fitting within
/// the Kokoro model's 510 phoneme token limit.
public class TextChunker {
    /// Conservative estimate: ~3 phoneme tokens per character on average.
    /// This is intentionally conservative to avoid exceeding the limit.
    private let tokensPerChar: Double = 2.5
    private let maxTokens: Int = 510

    public init() {}

    /// Split text into chunks that fit within the 510-token budget.
    ///
    /// Natural prose treats paragraph breaks as soft pacing markers and packs
    /// sentences across them. Paragraph-bounded mode preserves the old hard
    /// paragraph boundary behaviour for script-like synthesis.
    ///
    /// - Parameter text: Input text of any length.
    /// - Parameter policy: Chunking policy for paragraph handling.
    /// - Returns: Array of TextChunks, each within the token limit.
    public func chunk(
        _ text: String,
        policy: TextChunkingPolicy = .naturalProse
    ) -> [TextChunk] {
        switch policy {
        case .naturalProse:
            return chunkNaturalProse(text)
        case .paragraphBounded:
            return chunkParagraphBounded(text)
        }
    }

    private struct SentenceUnit {
        let text: String
        let followsParagraphBreak: Bool
    }

    private func chunkNaturalProse(_ text: String) -> [TextChunk] {
        let sentences = sentenceUnits(from: text)
        guard !sentences.isEmpty else { return [] }

        var chunks: [TextChunk] = []
        var currentSentences: [String] = []
        var currentTokenEstimate = 0
        var currentBoundary: TextChunkBoundary = .none
        var currentContainsParagraphBreak = false

        func flushCurrent() {
            guard !currentSentences.isEmpty else { return }
            let chunkText = currentSentences.joined(separator: " ")
            chunks.append(TextChunk(
                text: chunkText,
                estimatedTokenCount: estimateTokens(chunkText),
                boundaryBefore: currentBoundary,
                containsParagraphBreak: currentContainsParagraphBreak
            ))
            currentSentences = []
            currentTokenEstimate = 0
            currentBoundary = .tokenBudget
            currentContainsParagraphBreak = false
        }

        for sentence in sentences {
            let sentenceTokens = estimateTokens(sentence.text)

            if sentenceTokens > maxTokens {
                flushCurrent()
                let boundary: TextChunkBoundary = chunks.isEmpty ? .none : .tokenBudget
                chunks.append(contentsOf: splitAtClauseBoundaries(
                    sentence.text,
                    firstBoundary: boundary,
                    containsParagraphBreak: sentence.followsParagraphBreak
                ))
                currentBoundary = .tokenBudget
                continue
            }

            if currentTokenEstimate + sentenceTokens > maxTokens && !currentSentences.isEmpty {
                flushCurrent()
            }

            if sentence.followsParagraphBreak && !currentSentences.isEmpty {
                currentContainsParagraphBreak = true
            }

            currentSentences.append(sentence.text)
            currentTokenEstimate += sentenceTokens
        }

        flushCurrent()
        return chunks
    }

    private func sentenceUnits(from text: String) -> [SentenceUnit] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.enumerated().flatMap { paragraphIndex, paragraph in
            splitSentences(paragraph).enumerated().map { sentenceIndex, sentence in
                SentenceUnit(
                    text: sentence,
                    followsParagraphBreak: paragraphIndex > 0 && sentenceIndex == 0
                )
            }
        }
    }

    private func chunkParagraphBounded(_ text: String) -> [TextChunk] {
        // Split into paragraphs first (blank lines), then chunk within each
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return [] }

        // If there's only one paragraph (no blank lines), fall through to
        // sentence-level chunking directly
        if paragraphs.count == 1 {
            return chunkParagraph(paragraphs[0], firstBoundary: .none)
        }

        // Multiple paragraphs: chunk each one independently
        var allChunks: [TextChunk] = []
        for (index, paragraph) in paragraphs.enumerated() {
            allChunks.append(contentsOf: chunkParagraph(
                paragraph,
                firstBoundary: index == 0 ? .none : .paragraph
            ))
        }
        return allChunks
    }

    /// Chunk a single paragraph (no blank lines) at sentence boundaries.
    private func chunkParagraph(
        _ text: String,
        firstBoundary: TextChunkBoundary
    ) -> [TextChunk] {
        let sentences = splitSentences(text)

        guard !sentences.isEmpty else {
            return []
        }

        var chunks: [TextChunk] = []
        var currentSentences: [String] = []
        var currentTokenEstimate = 0
        var currentBoundary = firstBoundary

        for sentence in sentences {
            let sentenceTokens = estimateTokens(sentence)

            // If a single sentence exceeds the limit, split at clause boundaries
            if sentenceTokens > maxTokens {
                // Flush current accumulator first
                if !currentSentences.isEmpty {
                    let chunkText = currentSentences.joined(separator: " ")
                    chunks.append(TextChunk(
                        text: chunkText,
                        estimatedTokenCount: estimateTokens(chunkText),
                        boundaryBefore: currentBoundary
                    ))
                    currentSentences = []
                    currentTokenEstimate = 0
                    currentBoundary = .tokenBudget
                }
                // Split the oversized sentence at clause boundaries
                let subChunks = splitAtClauseBoundaries(
                    sentence,
                    firstBoundary: chunks.isEmpty ? currentBoundary : .tokenBudget
                )
                chunks.append(contentsOf: subChunks)
                currentBoundary = .tokenBudget
                continue
            }

            // Would adding this sentence exceed the limit?
            if currentTokenEstimate + sentenceTokens > maxTokens && !currentSentences.isEmpty {
                let chunkText = currentSentences.joined(separator: " ")
                chunks.append(TextChunk(
                    text: chunkText,
                    estimatedTokenCount: estimateTokens(chunkText),
                    boundaryBefore: currentBoundary
                ))
                currentSentences = []
                currentTokenEstimate = 0
                currentBoundary = .tokenBudget
            }

            currentSentences.append(sentence)
            currentTokenEstimate += sentenceTokens
        }

        // Flush remaining
        if !currentSentences.isEmpty {
            let chunkText = currentSentences.joined(separator: " ")
            chunks.append(TextChunk(
                text: chunkText,
                estimatedTokenCount: estimateTokens(chunkText),
                boundaryBefore: currentBoundary
            ))
        }

        return chunks
    }

    /// Split text into sentences using NLTokenizer.
    private func splitSentences(_ text: String) -> [String] {
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
        return sentences
    }

    /// Split an oversized sentence at clause boundaries (commas, semicolons).
    private func splitAtClauseBoundaries(
        _ sentence: String,
        firstBoundary: TextChunkBoundary,
        containsParagraphBreak: Bool = false
    ) -> [TextChunk] {
        let delimiters = CharacterSet(charactersIn: ",;:")
        let parts = sentence.components(separatedBy: delimiters)

        var chunks: [TextChunk] = []
        var current: [String] = []
        var currentTokens = 0
        var currentBoundary = firstBoundary

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let partTokens = estimateTokens(trimmed)

            if currentTokens + partTokens > maxTokens && !current.isEmpty {
                let text = current.joined(separator: ", ")
                chunks.append(TextChunk(
                    text: text,
                    estimatedTokenCount: estimateTokens(text),
                    boundaryBefore: currentBoundary,
                    containsParagraphBreak: containsParagraphBreak
                ))
                current = []
                currentTokens = 0
                currentBoundary = .oversizedSentence
            }
            current.append(trimmed)
            currentTokens += partTokens
        }

        if !current.isEmpty {
            let text = current.joined(separator: ", ")
            chunks.append(TextChunk(
                text: text,
                estimatedTokenCount: estimateTokens(text),
                boundaryBefore: currentBoundary,
                containsParagraphBreak: containsParagraphBreak
            ))
        }

        return chunks
    }

    /// Estimate phoneme token count from text length.
    private func estimateTokens(_ text: String) -> Int {
        Int(Double(text.count) * tokensPerChar)
    }
}
