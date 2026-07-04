// ABOUTME: Tests for TextChunker sentence-boundary splitting.
// ABOUTME: Covers RT-2.9 through RT-2.12.

import Testing
import Foundation
@testable import YapperKit

// RT-2.9: Text within 510 tokens is returned as a single chunk
@Test("RT-2.9: Short text returns single chunk")
func test_short_text_single_chunk_RT2_9() throws {
    let chunker = TextChunker()
    let chunks = chunker.chunk("Hello, this is a short sentence.")
    #expect(chunks.count == 1)
    #expect(chunks[0].text == "Hello, this is a short sentence.")
}

// RT-2.10: Text exceeding 510 tokens is split into multiple chunks
@Test("RT-2.10: Long text splits into multiple chunks")
func test_long_text_multiple_chunks_RT2_10() throws {
    let chunker = TextChunker()
    // Generate text with many sentences to exceed 510 phoneme tokens
    let sentences = (1...50).map { "This is sentence number \($0) with enough words to accumulate tokens." }
    let longText = sentences.joined(separator: " ")
    let chunks = chunker.chunk(longText)
    #expect(chunks.count > 1)
    // Reconstructed text should match original
    let reconstructed = chunks.map(\.text).joined(separator: " ")
    #expect(reconstructed == longText)
}

// RT-2.11: Every chunk is at or below the 510-token limit
@Test("RT-2.11: All chunks within token limit")
func test_chunks_within_token_limit_RT2_11() throws {
    let chunker = TextChunker()
    let sentences = (1...50).map { "This is sentence number \($0) with enough words to accumulate tokens." }
    let longText = sentences.joined(separator: " ")
    let chunks = chunker.chunk(longText)
    for chunk in chunks {
        #expect(chunk.estimatedTokenCount <= 510)
    }
}

// RT-2.12: Chunks split only at sentence boundaries
@Test("RT-2.12: Chunks split at sentence boundaries")
func test_chunks_split_at_sentence_boundaries_RT2_12() throws {
    let chunker = TextChunker()
    let text = "First sentence. Second sentence. Third sentence. Fourth sentence."
    let chunks = chunker.chunk(text)
    // Each chunk should end with a complete sentence (period + space or end of text)
    for chunk in chunks {
        let trimmed = chunk.text.trimmingCharacters(in: .whitespaces)
        #expect(trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?"))
    }
}

@Test("RT-40.1: natural prose packs short paragraphs")
func test_natural_prose_packs_short_paragraphs_RT40_1() throws {
    let chunker = TextChunker()
    let text = """
    The room went quiet.

    "I heard it too," Mara said.

    The kettle clicked off.
    """

    let chunks = chunker.chunk(text, policy: .naturalProse)

    #expect(chunks.count == 1)
    #expect(chunks[0].containsParagraphBreak)
}

@Test("RT-40.2: natural prose still splits at token budget")
func test_natural_prose_still_splits_at_token_budget_RT40_2() throws {
    let chunker = TextChunker()
    let paragraphs = (1...30).map {
        "Paragraph \($0) has enough words to push the combined prose beyond the conservative token budget."
    }
    let text = paragraphs.joined(separator: "\n\n")

    let chunks = chunker.chunk(text, policy: .naturalProse)

    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { $0.estimatedTokenCount <= 510 })
    #expect(chunks.contains { $0.boundaryBefore == .tokenBudget })
}

@Test("RT-40.3: paragraph-bounded policy preserves paragraph segmentation")
func test_paragraph_bounded_policy_preserves_paragraph_segmentation_RT40_3() throws {
    let chunker = TextChunker()
    let text = """
    First script entry.

    Second script entry.

    Third script entry.
    """

    let chunks = chunker.chunk(text, policy: .paragraphBounded)

    #expect(chunks.map(\.text) == [
        "First script entry.",
        "Second script entry.",
        "Third script entry."
    ])
    #expect(chunks.map(\.boundaryBefore) == [.none, .paragraph, .paragraph])
}

@Test("RT-40.5: natural prose avoids one chunk per dialogue paragraph")
func test_natural_prose_avoids_one_chunk_per_dialogue_paragraph_RT40_5() throws {
    let chunker = TextChunker()
    let text = """
    "No," she said.

    "Not like that."

    He waited.

    "Then how?"
    """

    let naturalChunks = chunker.chunk(text, policy: .naturalProse)
    let boundedChunks = chunker.chunk(text, policy: .paragraphBounded)

    #expect(naturalChunks.count < boundedChunks.count)
    #expect(naturalChunks.count == 1)
    #expect(boundedChunks.count == 4)
}

@Test("RT-40.6: natural prose records paragraph pacing inside packed chunks")
func test_natural_prose_records_paragraph_pacing_inside_packed_chunks_RT40_6() throws {
    let chunker = TextChunker()
    let text = "First paragraph.\n\nSecond paragraph."

    let chunks = chunker.chunk(text, policy: .naturalProse)

    #expect(chunks.count == 1)
    #expect(chunks[0].containsParagraphBreak)
    #expect(chunks[0].text == "First paragraph. Second paragraph.")
}
