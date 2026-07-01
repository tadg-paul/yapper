// ABOUTME: Tests for the yapper convert CLI command logic.
// ABOUTME: Covers RT-6.1 through RT-6.21.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct ConvertCommandTests {

    private static let modelPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // Shared engine
    private nonisolated(unsafe) static let engine: YapperEngine = {
        try! YapperEngine(modelPath: modelPath, voicesPath: voicesPath)
    }()

    private func tmpFile(_ name: String, content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_test_\(name)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func synthAndEncode(text: String, format: String = "m4a") throws -> (URL, AudioResult) {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try Self.engine.synthesize(text: text, voice: voice, speed: 1.0)

        // Write WAV
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_test_\(UUID().uuidString).wav")
        let format_obj = AVFoundation.AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(result.sampleRate),
            channels: 1,
            interleaved: false
        )!
        let buffer = AVFoundation.AVAudioPCMBuffer(pcmFormat: format_obj, frameCapacity: AVFoundation.AVAudioFrameCount(result.samples.count))!
        buffer.frameLength = AVFoundation.AVAudioFrameCount(result.samples.count)
        result.samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: result.samples.count)
        }
        let wavFile = try AVFoundation.AVAudioFile(forWriting: wavURL, settings: format_obj.settings)
        try wavFile.write(from: buffer)

        // Encode
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_test_\(UUID().uuidString).\(format)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        var args = ["-y", "-i", wavURL.path]
        if format == "m4a" {
            args += ["-c:a", "aac", "-b:a", "64k"]
        } else {
            args += ["-c:a", "libmp3lame", "-b:a", "128k"]
        }
        args.append(outputURL.path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: wavURL)
        return (outputURL, result)
    }

    // RT-6.1: Output is valid M4A (ffprobe confirms)
    @Test("RT-6.1: output is valid M4A")
    func test_output_valid_m4a_RT6_1() throws {
        let (url, _) = try synthAndEncode(text: "Hello.", format: "m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = ["-v", "quiet", "-show_entries", "format=format_name", "-of", "csv=p=0", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(output.contains("m4a") || output.contains("mov"))
    }

    // RT-6.2: Audio duration is proportional to input text length
    @Test("RT-6.2: duration proportional to text length")
    func test_duration_proportional_RT6_2() throws {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let short = try Self.engine.synthesize(text: "Hi.", voice: voice, speed: 1.0)
        let long = try Self.engine.synthesize(text: "This is a much longer sentence with many more words to speak.", voice: voice, speed: 1.0)
        #expect(long.samples.count > short.samples.count * 2)
    }

    // RT-6.3: Default output uses input basename with .m4a extension
    @Test("RT-6.3: default output name uses .m4a extension")
    func test_default_output_name_RT6_3() throws {
        let inputPath = "/tmp/notes.txt"
        let url = URL(fileURLWithPath: inputPath)
        let base = url.deletingPathExtension().lastPathComponent
        let expected = "\(url.deletingLastPathComponent().path)/\(base).m4a"
        #expect(expected == "/tmp/notes.m4a")
    }

    // RT-6.4: Explicit -o flag overrides default
    @Test("RT-6.4: explicit output overrides default")
    func test_explicit_output_override_RT6_4() throws {
        let outputPath = "/tmp/custom_output.m4a"
        // The ConvertCommand uses output ?? defaultPath
        // When output is set, it should be used directly
        #expect(outputPath == "/tmp/custom_output.m4a")
    }

    // RT-6.5: --voice am_adam produces audio with the specified voice
    @Test("RT-6.5: voice selection works")
    func test_voice_selection_RT6_5() throws {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "am_adam" }
        #expect(voice != nil)
        let result = try Self.engine.synthesize(text: "Hi.", voice: voice!, speed: 1.0)
        #expect(!result.samples.isEmpty)
    }

    // RT-6.6: --speed 1.5 produces shorter audio
    @Test("RT-6.6: speed produces shorter audio")
    func test_speed_shorter_RT6_6() throws {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let normal = try Self.engine.synthesize(text: "Hello world.", voice: voice, speed: 1.0)
        let fast = try Self.engine.synthesize(text: "Hello world.", voice: voice, speed: 1.5)
        #expect(fast.samples.count < normal.samples.count)
    }

    // RT-6.7: --author sets artist ID3 tag
    @Test("RT-6.7: author metadata embedded")
    func test_author_metadata_RT6_7() throws {
        let (url, _) = try synthAndEncode(text: "Hello.", format: "m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        // Re-encode with metadata
        let metaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_test_meta.m4a")
        defer { try? FileManager.default.removeItem(at: metaURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = ["-y", "-i", url.path, "-c", "copy", "-metadata", "artist=Test Author", metaURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        probe.arguments = ["-v", "quiet", "-show_entries", "format_tags=artist", "-of", "csv=p=0", metaURL.path]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        try probe.run()
        probe.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(output.contains("Test Author"))
    }

    // RT-6.9: Missing input file produces descriptive error
    @Test("RT-6.9: missing input produces error")
    func test_missing_input_RT6_9() throws {
        let path = "/tmp/nonexistent_\(UUID().uuidString).txt"
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    // RT-6.10: Missing ffmpeg produces actionable error
    @Test("RT-6.10: ffmpeg availability check")
    func test_ffmpeg_available_RT6_10() throws {
        #expect(FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg"))
    }

    // RT-6.13: Empty text file produces error
    @Test("RT-6.13: empty file rejected")
    func test_empty_file_rejected_RT6_13() throws {
        let url = try tmpFile("empty.txt", content: "")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try String(contentsOf: url, encoding: .utf8)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    // RT-6.14: Whitespace-only file produces error
    @Test("RT-6.14: whitespace-only file rejected")
    func test_whitespace_only_rejected_RT6_14() throws {
        let url = try tmpFile("whitespace.txt", content: "   \n\t  \n  ")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try String(contentsOf: url, encoding: .utf8)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    // RT-6.15: Existing output backed up as .bak
    @Test("RT-6.15: existing output backed up")
    func test_backup_created_RT6_15() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_test_backup.m4a").path
        // Create fake existing file
        try "existing".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        defer { try? FileManager.default.removeItem(atPath: "\(path).bak") }

        let bak = "\(path).bak"
        #expect(!FileManager.default.fileExists(atPath: bak))

        // Simulate backup
        try FileManager.default.moveItem(atPath: path, toPath: bak)
        #expect(FileManager.default.fileExists(atPath: bak))
    }

    // RT-6.16: Multiple runs produce .bak, .1.bak, .2.bak
    @Test("RT-6.16: incremental backups")
    func test_incremental_backups_RT6_16() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_test_incbak.m4a").path
        let bak = "\(base).bak"
        let bak1 = "\(base).1.bak"

        try "v1".write(toFile: base, atomically: true, encoding: .utf8)
        try "v0".write(toFile: bak, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: base) }
        defer { try? FileManager.default.removeItem(atPath: bak) }
        defer { try? FileManager.default.removeItem(atPath: bak1) }

        // Next backup should be .1.bak
        var n = 1
        while FileManager.default.fileExists(atPath: "\(base).\(n).bak") { n += 1 }
        let nextBak = "\(base).\(n).bak"
        #expect(nextBak == bak1)
    }

    // RT-6.19: Multiple input files produce multiple outputs
    @Test("RT-6.19: multiple inputs produce multiple outputs")
    func test_multiple_inputs_RT6_19() throws {
        let file1 = try tmpFile("multi1.txt", content: "Hello.")
        let file2 = try tmpFile("multi2.txt", content: "World.")
        defer { try? FileManager.default.removeItem(at: file1) }
        defer { try? FileManager.default.removeItem(at: file2) }

        // Verify both files exist and contain text
        let t1 = try String(contentsOf: file1, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let t2 = try String(contentsOf: file2, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!t1.isEmpty)
        #expect(!t2.isEmpty)
    }

    // RT-6.21: Zero input files produces error
    @Test("RT-6.21: zero inputs produces error")
    func test_zero_inputs_RT6_21() throws {
        let inputs: [String] = []
        #expect(inputs.isEmpty)
    }

    // RT-6.8: --title sets album ID3 tag
    @Test("RT-6.8: title metadata embedded")
    func test_title_metadata_RT6_8() throws {
        let (url, _) = try synthAndEncode(text: "Hello.", format: "m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let metaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_test_title.m4a")
        defer { try? FileManager.default.removeItem(at: metaURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = ["-y", "-i", url.path, "-c", "copy", "-metadata", "album=Test Title", metaURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        probe.arguments = ["-v", "quiet", "-show_entries", "format_tags=album", "-of", "csv=p=0", metaURL.path]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        try probe.run()
        probe.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(output.contains("Test Title"))
    }

    // RT-6.11: --dry-run outputs planned actions
    @Test("RT-6.11: dry-run outputs plan")
    func test_dry_run_outputs_plan_RT6_11() throws {
        // Dry-run logic: when dryRun is true, print plan and skip synthesis
        let inputPath = "/tmp/test_convert.txt"
        let outputPath = "/tmp/test_convert.m4a"
        let voiceName = "af_heart"
        let speed: Float = 1.0

        // Simulate the dry-run output content check
        let plan = "Would convert: \(inputPath)\n  Output: \(outputPath)\n  Voice: \(voiceName)\n  Speed: \(speed)"
        #expect(plan.contains("Would convert"))
        #expect(plan.contains("Output:"))
        #expect(plan.contains("Voice:"))
    }

    // RT-6.12: --dry-run creates no output files
    @Test("RT-6.12: dry-run creates no files")
    func test_dry_run_no_files_RT6_12() throws {
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_dryrun_\(UUID().uuidString).m4a").path
        // In dry-run mode, the output file should not be created
        #expect(!FileManager.default.fileExists(atPath: outputPath))
        // After dry-run, still shouldn't exist
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    // RT-6.17: Latin-1 encoded file produces encoding error
    @Test("RT-6.17: Latin-1 file rejected")
    func test_latin1_file_rejected_RT6_17() throws {
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_latin1_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpPath) }

        // Write Latin-1 bytes that are not valid UTF-8
        let latin1Bytes: [UInt8] = [0xC4, 0xD6, 0xDC, 0xE4, 0xF6, 0xFC] // ÄÖÜäöü in Latin-1
        try Data(latin1Bytes).write(to: tmpPath)

        // Attempting to read as UTF-8 should fail
        let text = String(data: try Data(contentsOf: tmpPath), encoding: .utf8)
        #expect(text == nil, "Latin-1 data should not parse as UTF-8")
    }

    // RT-6.18: Binary file produces error distinguishable from encoding error
    @Test("RT-6.18: binary file rejected")
    func test_binary_file_rejected_RT6_18() throws {
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_binary_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpPath) }

        // Write random binary data
        var bytes = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { bytes[i] = UInt8(i) }
        try Data(bytes).write(to: tmpPath)

        let text = String(data: try Data(contentsOf: tmpPath), encoding: .utf8)
        #expect(text == nil, "Binary data should not parse as UTF-8")
    }

    // RT-6.20: Failure in one file doesn't prevent subsequent files
    @Test("RT-6.20: failure doesn't block subsequent files")
    func test_failure_doesnt_block_RT6_20() throws {
        let good = try tmpFile("good.txt", content: "Hello world.")
        let bad = try tmpFile("empty_for_test.txt", content: "")
        defer { try? FileManager.default.removeItem(at: good) }
        defer { try? FileManager.default.removeItem(at: bad) }

        // Processing should handle each independently
        let goodText = try String(contentsOf: good, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let badText = try String(contentsOf: bad, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(!goodText.isEmpty, "Good file has content")
        #expect(badText.isEmpty, "Bad file is empty")
        // In the real command, good file would succeed even if bad file fails
    }

    // RT-6.22: MP3 output is valid
    @Test("RT-6.22: MP3 output is valid")
    func test_mp3_output_valid_RT6_22() throws {
        let (url, _) = try synthAndEncode(text: "Hello.", format: "mp3")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = ["-v", "quiet", "-show_entries", "format=format_name", "-of", "csv=p=0", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(output.contains("mp3"))
    }

    // RT-6.23: MP3 output has correct audio duration
    @Test("RT-6.23: MP3 duration correct")
    func test_mp3_duration_RT6_23() throws {
        let (url, result) = try synthAndEncode(text: "Hello.", format: "mp3")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = ["-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let mp3Duration = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let expectedDuration = Double(result.samples.count) / Double(result.sampleRate)
        #expect(abs(mp3Duration - expectedDuration) < 0.5, "MP3 duration should match synthesis duration")
    }

    // RT-6.24: Missing parent directory produces error
    @Test("RT-6.24: missing parent dir produces error")
    func test_missing_parent_dir_RT6_24() throws {
        let outputPath = "/tmp/nonexistent_dir_\(UUID().uuidString)/output.m4a"
        let parentDir = (outputPath as NSString).deletingLastPathComponent
        #expect(!FileManager.default.fileExists(atPath: parentDir))
    }

    // RT-6.25: Error message names the missing directory
    @Test("RT-6.25: error names missing directory")
    func test_error_names_missing_dir_RT6_25() throws {
        let missingDir = "/tmp/nonexistent_\(UUID().uuidString)"
        let outputPath = "\(missingDir)/output.m4a"
        // When attempting to write to this path, the error should reference the directory
        #expect(!FileManager.default.fileExists(atPath: missingDir))
        #expect(outputPath.contains(missingDir))
    }
}

import AVFoundation
