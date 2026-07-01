// ABOUTME: Tests for speech speed control.
// ABOUTME: Covers RT-2.7 and RT-2.8.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct SpeedTests {

    private static let modelPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-2.7: Speed 2.0 produces shorter audio than speed 1.0 for identical text
    @Test("RT-2.7: Speed 2.0 produces shorter audio")
    func test_speed_2x_shorter_RT2_7() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let text = "Hello world, this is a test of speech speed."

        let normal = try engine.synthesize(text: text, voice: voice, speed: 1.0)
        let fast = try engine.synthesize(text: text, voice: voice, speed: 2.0)

        #expect(fast.samples.count < normal.samples.count)
    }

    // RT-2.8: Speed 0.5 produces longer audio than speed 1.0 for identical text
    @Test("RT-2.8: Speed 0.5 produces longer audio")
    func test_speed_half_longer_RT2_8() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let text = "Hello world, this is a test of speech speed."

        let normal = try engine.synthesize(text: text, voice: voice, speed: 1.0)
        let slow = try engine.synthesize(text: text, voice: voice, speed: 0.5)

        #expect(slow.samples.count > normal.samples.count)
    }
}
