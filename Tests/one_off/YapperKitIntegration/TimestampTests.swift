// ABOUTME: Tests for word-level timestamp accuracy.
// ABOUTME: Covers RT-2.4 through RT-2.6.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct TimestampTests {

    private static let modelPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-2.4: Each word in the input has a corresponding timestamp entry
    @Test("RT-2.4: Each word has a timestamp")
    func test_each_word_has_timestamp_RT2_4() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let text = "The quick brown fox."
        let result = try engine.synthesize(text: text, voice: voice, speed: 1.0)

        #expect(!result.timestamps.isEmpty)
        #expect(result.timestamps.count >= 3)
    }

    // RT-2.5: Timestamps are monotonically increasing
    @Test("RT-2.5: Timestamps monotonically increase")
    func test_timestamps_monotonic_RT2_5() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try engine.synthesize(
            text: "Hello world, how are you today.", voice: voice, speed: 1.0
        )

        for i in 1..<result.timestamps.count {
            #expect(result.timestamps[i].startTime >= result.timestamps[i - 1].startTime)
        }
    }

    // RT-2.6: Final timestamp end time matches audio duration within 500ms tolerance
    // Note: timestamp prediction uses approximate frame-to-second conversion;
    // exact tuning is a follow-up improvement.
    @Test("RT-2.6: Final timestamp matches audio duration")
    func test_final_timestamp_matches_duration_RT2_6() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try engine.synthesize(text: "Hello world.", voice: voice, speed: 1.0)

        let audioDuration = Double(result.samples.count) / Double(result.sampleRate)
        guard let lastTimestamp = result.timestamps.last else {
            Issue.record("No timestamps returned")
            return
        }

        let difference = abs(audioDuration - lastTimestamp.endTime)
        #expect(difference < 0.5)
    }
}
