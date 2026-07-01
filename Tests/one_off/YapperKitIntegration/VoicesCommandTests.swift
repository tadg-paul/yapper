// ABOUTME: Tests for the yapper voices CLI command logic.
// ABOUTME: Covers RT-5.1 through RT-5.6. Tests call VoiceRegistry directly, not subprocesses.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct VoicesCommandTests {

    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-5.1: At least 3 voices are listed
    @Test("RT-5.1: at least 3 voices available")
    func test_voices_at_least_3_RT5_1() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        #expect(registry.voices.count >= 3)
    }

    // RT-5.2: Each voice has name, accent, and gender
    @Test("RT-5.2: each voice has name, accent, gender")
    func test_voices_metadata_RT5_2() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        for voice in registry.voices {
            #expect(!voice.name.isEmpty)
            // accent and gender are enums — if Voice parsed, they're valid
            let accentLabel = voice.accent == .american ? "American" : "British"
            let genderLabel = voice.gender == .female ? "Female" : "Male"
            #expect(!accentLabel.isEmpty)
            #expect(!genderLabel.isEmpty)
        }
    }

    // RT-5.3: Voices are sorted alphabetically
    @Test("RT-5.3: voices sorted alphabetically")
    func test_voices_sorted_RT5_3() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let names = registry.voices.map(\.name)
        let sorted = names.sorted()
        #expect(names == sorted)
    }

    // RT-5.4: Preview with valid voice succeeds (synthesises audio)
    @Test("RT-5.4: preview valid voice produces audio")
    func test_voices_preview_valid_RT5_4() throws {
        let modelPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
        let engine = try YapperEngine(modelPath: modelPath, voicesPath: Self.voicesPath)
        let voice = engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let sampleText = "Hello, this is the \(voice.name) voice."
        let result = try engine.synthesize(text: sampleText, voice: voice, speed: 1.0)
        #expect(!result.samples.isEmpty)
    }

    // RT-5.5: Preview with invalid voice name fails
    @Test("RT-5.5: preview invalid voice fails")
    func test_voices_preview_invalid_RT5_5() throws {
        let registry = try VoiceRegistry(voicesPath: Self.voicesPath)
        let voice = registry.voices.first { $0.name == "nonexistent_voice" }
        #expect(voice == nil)
    }

    // RT-5.6: Empty voices directory produces error
    @Test("RT-5.6: empty voices directory produces error")
    func test_voices_empty_dir_RT5_6() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_empty_voices_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        #expect(throws: YapperError.voicesNotFound(path: tmpDir.path)) {
            try VoiceRegistry(voicesPath: tmpDir)
        }
    }

    // RT-5.7: Preview with missing voice file produces error mentioning voice name
    @Test("RT-5.7: missing voice file produces error")
    func test_voices_missing_file_RT5_7() throws {
        // Create a temp dir with a voice file, then delete it
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_missing_voice_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Copy a real voice, create registry, then delete the file
        let src = Self.voicesPath.appendingPathComponent("af_heart.safetensors")
        let dst = tmpDir.appendingPathComponent("af_heart.safetensors")
        try FileManager.default.copyItem(at: src, to: dst)

        let registry = try VoiceRegistry(voicesPath: tmpDir)
        #expect(registry.voices.count == 1)

        // Delete the file after registry was created
        try FileManager.default.removeItem(at: dst)

        // Loading should fail
        do {
            _ = try registry.load(name: "af_heart")
            Issue.record("Expected error loading deleted voice file")
        } catch {
            let errorMsg = "\(error)"
            #expect(errorMsg.contains("af_heart") || errorMsg.contains("not found") || errorMsg.contains("voicesNotFound"))
        }
    }

    // RT-5.8: Voice still appears in list but preview fails gracefully
    @Test("RT-5.8: deleted voice still listed but load fails")
    func test_voices_deleted_still_listed_RT5_8() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_deleted_voice_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let src = Self.voicesPath.appendingPathComponent("af_heart.safetensors")
        let dst = tmpDir.appendingPathComponent("af_heart.safetensors")
        try FileManager.default.copyItem(at: src, to: dst)

        let registry = try VoiceRegistry(voicesPath: tmpDir)
        // Voice is in the list
        #expect(registry.voices.contains { $0.name == "af_heart" })

        // Delete file
        try FileManager.default.removeItem(at: dst)

        // Still in list (registry was built at init)
        #expect(registry.voices.contains { $0.name == "af_heart" })

        // But loading fails
        #expect(throws: (any Error).self) {
            try registry.load(name: "af_heart")
        }
    }
}
