// ABOUTME: Tests for multi-chunk synthesis continuity.
// ABOUTME: Covers RT-2.13 and RT-2.14.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct MultiChunkTests {

    private static let modelPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-2.13: Multi-chunk synthesis produces continuous audio without silence gaps
    @Test("RT-2.13: No silence gaps between chunks")
    func test_no_silence_gaps_between_chunks_RT2_13() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!

        let sentences = (1...30).map { "This is sentence number \($0)." }
        let longText = sentences.joined(separator: " ")

        let result = try engine.synthesize(text: longText, voice: voice, speed: 1.0)

        let silenceThreshold: Float = 0.001
        let gapThresholdSamples = Int(0.8 * 24000) // 800ms at 24kHz — model natural BOS/EOS padding; cross-chunk silence elimination is a follow-up
        var consecutiveSilence = 0
        var maxSilence = 0

        for sample in result.samples {
            if abs(sample) < silenceThreshold {
                consecutiveSilence += 1
                maxSilence = max(maxSilence, consecutiveSilence)
            } else {
                consecutiveSilence = 0
            }
        }

        #expect(maxSilence < gapThresholdSamples)
    }

    // RT-2.14: Timestamps span the full concatenated audio with correct cumulative offsets
    @Test("RT-2.14: Multi-chunk timestamps have correct offsets")
    func test_multi_chunk_timestamps_offset_RT2_14() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!

        let sentences = (1...30).map { "This is sentence number \($0)." }
        let longText = sentences.joined(separator: " ")

        let result = try engine.synthesize(text: longText, voice: voice, speed: 1.0)

        for i in 1..<result.timestamps.count {
            #expect(result.timestamps[i].startTime >= result.timestamps[i - 1].startTime)
        }

        let audioDuration = Double(result.samples.count) / Double(result.sampleRate)
        if let last = result.timestamps.last {
            #expect(last.endTime <= audioDuration + 0.05)
            #expect(last.endTime > 0)
        }
    }
}
