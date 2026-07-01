// ABOUTME: Tests for core TTS synthesis — text to PCM audio.
// ABOUTME: Covers RT-2.1 through RT-2.3.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct SynthesisTests {

    private static let modelPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-2.1: Synthesising a short sentence produces a non-empty Float array
    @Test("RT-2.1: Synthesis produces non-empty audio")
    func test_synthesis_produces_audio_RT2_1() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try engine.synthesize(text: "Hello world.", voice: voice, speed: 1.0)
        #expect(!result.samples.isEmpty)
        #expect(result.samples.count > 1000)
    }

    // RT-2.2: Output sample rate is 24000
    @Test("RT-2.2: Output sample rate is 24000")
    func test_output_sample_rate_RT2_2() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try engine.synthesize(text: "Hello.", voice: voice, speed: 1.0)
        #expect(result.sampleRate == 24000)
    }

    // RT-2.3: Different voices produce different audio output
    @Test("RT-2.3: Different voices produce different audio")
    func test_different_voices_different_audio_RT2_3() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        let voice1 = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let voice2 = engine.voiceRegistry.voices.first { $0.name == "bm_daniel" }!
        let text = "Hello world."

        let result1 = try engine.synthesize(text: text, voice: voice1, speed: 1.0)
        let result2 = try engine.synthesize(text: text, voice: voice2, speed: 1.0)

        let differ = result1.samples.count != result2.samples.count ||
            zip(result1.samples, result2.samples).contains { $0 != $1 }
        #expect(differ)
    }
}
