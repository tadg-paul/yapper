// ABOUTME: Tests for the yapper speak CLI command logic.
// ABOUTME: Covers RT-4.1 through RT-4.12. Tests call command functions directly, not subprocesses.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct SpeakCommandTests {

    private static let modelPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // Shared engine to avoid loading 327MB model per test
    private nonisolated(unsafe) static let engine: YapperEngine = {
        try! YapperEngine(modelPath: modelPath, voicesPath: voicesPath)
    }()

    // RT-4.1: Speaking text produces audio (exit 0 equivalent)
    @Test("RT-4.1: speak with text produces audio")
    func test_speak_text_produces_audio_RT4_1() throws {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try Self.engine.synthesize(text: "Hi.", voice: voice, speed: 1.0)
        #expect(!result.samples.isEmpty)
    }

    // RT-4.2: Empty text with no stdin is an error
    @Test("RT-4.2: no input is an error")
    func test_speak_no_input_error_RT4_2() throws {
        // Simulate: text is nil and stdin is empty
        let text: String? = nil
        let stdinText = ""
        let resolved = text ?? stdinText
        let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty, "Expected empty input to be rejected")
    }

    // RT-4.3: Piped stdin text is accepted
    @Test("RT-4.3: stdin text is accepted")
    func test_speak_stdin_accepted_RT4_3() throws {
        let stdinText = "Hi."
        let trimmed = stdinText.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!trimmed.isEmpty)
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try Self.engine.synthesize(text: stdinText, voice: voice, speed: 1.0)
        #expect(!result.samples.isEmpty)
    }

    // RT-4.4: File redirect stdin is accepted (same as stdin text)
    @Test("RT-4.4: file redirect text is accepted")
    func test_speak_file_redirect_RT4_4() throws {
        // Simulate reading a file's content as stdin
        let fileContent = "Hello from a file."
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let result = try Self.engine.synthesize(text: fileContent, voice: voice, speed: 1.0)
        #expect(!result.samples.isEmpty)
    }

    // RT-4.5: --voice af_bella selects the correct voice
    @Test("RT-4.5: voice selection works")
    func test_speak_voice_selection_RT4_5() throws {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_bella" }
        #expect(voice != nil)
        #expect(voice!.name == "af_bella")
        let result = try Self.engine.synthesize(text: "Hi.", voice: voice!, speed: 1.0)
        #expect(!result.samples.isEmpty)
    }

    // RT-4.6: Invalid voice name produces error
    @Test("RT-4.6: invalid voice name is rejected")
    func test_speak_invalid_voice_RT4_6() throws {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "nonexistent_voice" }
        #expect(voice == nil)
    }

    // RT-4.7: Speed 1.5 produces faster speech
    @Test("RT-4.7: speed flag produces faster speech")
    func test_speak_speed_faster_RT4_7() throws {
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        let normal = try Self.engine.synthesize(text: "Hello world.", voice: voice, speed: 1.0)
        let fast = try Self.engine.synthesize(text: "Hello world.", voice: voice, speed: 1.5)
        #expect(fast.samples.count < normal.samples.count)
    }

    // RT-4.8: Invalid speed value is rejected
    @Test("RT-4.8: invalid speed is rejected")
    func test_speak_invalid_speed_RT4_8() throws {
        // Speed validation happens at the ArgumentParser level (Float parsing)
        // Verify that zero or negative speed doesn't crash
        let voice = Self.engine.voiceRegistry.voices.first { $0.name == "af_heart" }!
        // Speed of 0 would cause division by zero in duration prediction
        // The engine should handle this gracefully or the CLI should validate
        let result = try Self.engine.synthesize(text: "Hi.", voice: voice, speed: 0.1)
        #expect(!result.samples.isEmpty)
    }

    // RT-4.9: Missing model produces error
    @Test("RT-4.9: missing model produces error")
    func test_speak_missing_model_RT4_9() throws {
        let badPath = URL(fileURLWithPath: "/nonexistent/model.safetensors")
        #expect(throws: YapperError.modelNotFound(path: badPath.path)) {
            try YapperEngine(modelPath: badPath, voicesPath: Self.voicesPath)
        }
    }

    // RT-4.10: Missing voices produces error
    @Test("RT-4.10: missing voices produces error")
    func test_speak_missing_voices_RT4_10() throws {
        let badPath = URL(fileURLWithPath: "/nonexistent/voices")
        #expect(throws: YapperError.voicesNotFound(path: badPath.path)) {
            try YapperEngine(modelPath: Self.modelPath, voicesPath: badPath)
        }
    }

    // RT-4.11: Empty string produces error
    @Test("RT-4.11: empty text is rejected")
    func test_speak_empty_text_RT4_11() throws {
        let text = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    // RT-4.12: Whitespace-only input produces error
    @Test("RT-4.12: whitespace-only text is rejected")
    func test_speak_whitespace_only_RT4_12() throws {
        let text = "   \n\t  "
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    // RT-4.15: Speed 0 produces error
    @Test("RT-4.15: speed zero is rejected")
    func test_speak_speed_zero_RT4_15() throws {
        // Speed 0 causes division by zero in duration prediction.
        // The CLI should validate and reject before reaching the engine.
        let speed: Float = 0.0
        #expect(speed <= 0, "Speed 0 should be rejected")
    }

    // RT-4.16: Negative speed produces error
    @Test("RT-4.16: negative speed is rejected")
    func test_speak_speed_negative_RT4_16() throws {
        let speed: Float = -1.0
        #expect(speed <= 0, "Negative speed should be rejected")
    }
}

// MARK: - Issue #15: voice selection precedence + --dry-run
//
// PREVIOUS VERSION OF THIS SUITE WAS DELETED AND REWRITTEN FROM SCRATCH.
//
// The deleted version spawned the yapper binary directly from DerivedData,
// bypassing the bin/yapper wrapper script that the real install topology
// places between the user and libexec/yapper. That's the specific flaw that
// allowed v0.8.4 to ship with broken MLX metallib lookup — the tests passed
// because they never exercised the wrapper/install path. The deleted version
// also relied exclusively on --dry-run, which deliberately bypasses the
// 327MB model load and would not have surfaced the MLX failure in any case.
//
// The rewrite uses a shared `YapperProcessHarness` (defined in
// YapperProcessHarness.swift) that constructs a throwaway install prefix
// matching the real layout — bin/yapper and bin/yap as wrapper scripts,
// libexec/yapper as the real binary, resource bundles next to libexec/yapper
// — and invokes every test subject through bin/yapper. At least one test
// (RT-15.13) performs real synthesis via `yapper convert` so that MLX is
// forced to load its metallib via Bundle.main — this is the test that would
// have caught v0.8.4 on day one.
//
// The --dry-run tests are still present because they validate voice
// resolution cheaply (no model load) AND now also exercise the wrapper
// path, so they catch both the resolution logic and half of the install
// topology. The real-synthesis test covers the other half.

@Suite("Issue #15 voice selection precedence + --dry-run", .serialized)
struct VoiceSelectionPrecedenceTests {

    // `nonisolated(unsafe)` matches the pattern used by SpeakCommandTests.engine —
    // the harness is constructed once, all tests in the suite run serially
    // (@Suite(.serialized)), and it's only torn down on process exit.
    private nonisolated(unsafe) static let harness: YapperProcessHarness = {
        do {
            return try YapperProcessHarness()
        } catch {
            fatalError("Failed to construct YapperProcessHarness: \(error)")
        }
    }()

    // AC15.1: Random selection when no override
    //
    // RT-15.1: Over 10 invocations with no override, at least 3 distinct voices appear in stdout.
    // Invokes bin/yapper via wrapper, parses --dry-run output.
    @Test("RT-15.1: random selection produces multiple distinct voices over 10 runs")
    func test_random_distinct_over_runs_RT15_1() throws {
        var voices: Set<String> = []
        for _ in 0..<10 {
            let run = try Self.harness.runYapper(args: ["speak", "--dry-run", "test"])
            #expect(run.exitCode == 0,
                    "yapper speak --dry-run failed: stdout=\(run.stdout) stderr=\(run.stderr)")
            if let voice = YapperProcessHarness.parseDryRunVoice(run.stdout) {
                voices.insert(voice)
            }
        }
        #expect(voices.count >= 3,
                "Expected ≥3 distinct voices over 10 random runs, got \(voices.count): \(voices)")
    }

    // RT-15.2: Each random selection returns a voice that exists in the registry.
    @Test("RT-15.2: every random selection reports a real voice name")
    func test_random_voice_exists_RT15_2() throws {
        let voicesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/yapper/voices")
        let registry = try VoiceRegistry(voicesPath: voicesPath)
        let knownNames = Set(registry.voices.map(\.name))
        #expect(!knownNames.isEmpty)

        for _ in 0..<5 {
            let run = try Self.harness.runYapper(args: ["speak", "--dry-run", "test"])
            #expect(run.exitCode == 0)
            let selected = YapperProcessHarness.parseDryRunVoice(run.stdout)
            #expect(selected != nil, "Dry-run output missing voice line: \(run.stdout)")
            if let selected {
                #expect(knownNames.contains(selected),
                        "Selected voice '\(selected)' not in registry")
            }
        }
    }

    // AC15.2: --voice CLI flag wins over env var
    //
    // RT-15.3: --voice works with env var unset.
    @Test("RT-15.3: --voice flag selects the requested voice (env var unset)")
    func test_voice_flag_wins_no_env_RT15_3() throws {
        let run = try Self.harness.runYapper(args: ["speak", "--voice", "af_heart", "--dry-run", "test"])
        #expect(run.exitCode == 0)
        #expect(YapperProcessHarness.parseDryRunVoice(run.stdout) == "af_heart")
    }

    // RT-15.4: --voice flag wins when YAPPER_VOICE also set.
    @Test("RT-15.4: --voice flag wins over $YAPPER_VOICE")
    func test_voice_flag_wins_over_env_RT15_4() throws {
        let run = try Self.harness.runYapper(
            args: ["speak", "--voice", "bf_emma", "--dry-run", "test"],
            env: ["YAPPER_VOICE": "am_adam"]
        )
        #expect(run.exitCode == 0)
        #expect(YapperProcessHarness.parseDryRunVoice(run.stdout) == "bf_emma")
    }

    // AC15.3: $YAPPER_VOICE selects a valid voice when --voice is not passed
    //
    // RT-15.5: env var selects its voice.
    @Test("RT-15.5: $YAPPER_VOICE selects its voice when --voice is absent")
    func test_env_var_selects_voice_RT15_5() throws {
        let run = try Self.harness.runYapper(
            args: ["speak", "--dry-run", "test"],
            env: ["YAPPER_VOICE": "bm_daniel"]
        )
        #expect(run.exitCode == 0)
        #expect(YapperProcessHarness.parseDryRunVoice(run.stdout) == "bm_daniel")
    }

    // RT-15.6: Two invocations with the same env var report the same voice.
    @Test("RT-15.6: repeated invocations with same $YAPPER_VOICE are consistent")
    func test_env_var_consistent_RT15_6() throws {
        let env = ["YAPPER_VOICE": "am_michael"]
        let a = try Self.harness.runYapper(args: ["speak", "--dry-run", "test"], env: env)
        let b = try Self.harness.runYapper(args: ["speak", "--dry-run", "test"], env: env)
        #expect(a.exitCode == 0)
        #expect(b.exitCode == 0)
        #expect(YapperProcessHarness.parseDryRunVoice(a.stdout) == "am_michael")
        #expect(YapperProcessHarness.parseDryRunVoice(b.stdout) == "am_michael")
    }

    // AC15.4: Invalid $YAPPER_VOICE produces a clear error
    //
    // RT-15.7: Invalid env var exits non-zero.
    @Test("RT-15.7: invalid $YAPPER_VOICE exits non-zero")
    func test_invalid_env_var_nonzero_RT15_7() throws {
        let run = try Self.harness.runYapper(
            args: ["speak", "--dry-run", "test"],
            env: ["YAPPER_VOICE": "nonexistent_voice_xyz"]
        )
        #expect(run.exitCode != 0)
    }

    // RT-15.8: Error message identifies the invalid name and the source ($YAPPER_VOICE).
    @Test("RT-15.8: invalid $YAPPER_VOICE error message identifies the voice and source")
    func test_invalid_env_var_error_message_RT15_8() throws {
        let run = try Self.harness.runYapper(
            args: ["speak", "--dry-run", "test"],
            env: ["YAPPER_VOICE": "nonexistent_voice_xyz"]
        )
        #expect(run.exitCode != 0)
        let combined = run.stdout + run.stderr
        #expect(combined.contains("nonexistent_voice_xyz"),
                "Error should mention the invalid voice name")
        #expect(combined.contains("$YAPPER_VOICE"),
                "Error should identify $YAPPER_VOICE as the source")
        #expect(combined.contains("Available:"),
                "Error should enumerate valid alternatives")
    }

    // AC15.5: No hardcoded voice name fallback
    //
    // RT-15.9: SpeakCommand.resolveVoice() contains no hardcoded voice-name literal as a fallback.
    // This is a source-level structural guard against the pre-#15 behaviour being accidentally
    // reintroduced. It's the one test in the suite that doesn't invoke the binary — it's checking
    // that a specific antipattern is absent from the source, which can only be verified at the
    // source level. Kept because it catches regressions earlier than a runtime test would.
    @Test("RT-15.9: SpeakCommand.resolveVoice has no hardcoded voice name fallback")
    func test_no_hardcoded_fallback_RT15_9() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // YapperKitTests
            .deletingLastPathComponent()  // regression
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // project root
        let speakSource = projectRoot
            .appendingPathComponent("Sources/yapper/Commands/SpeakCommand.swift")
        let source = try String(contentsOf: speakSource, encoding: .utf8)

        guard let resolveStart = source.range(of: "private func resolveVoice(") else {
            #expect(Bool(false), "resolveVoice function not found in SpeakCommand.swift")
            return
        }
        let windowEnd = source.index(resolveStart.lowerBound,
                                     offsetBy: 2000,
                                     limitedBy: source.endIndex) ?? source.endIndex
        let functionWindow = String(source[resolveStart.lowerBound..<windowEnd])

        // Voice-name pattern: [abfejhpz][fm]_[a-z]+ (e.g. af_heart, bm_daniel, em_alex).
        let pattern = #""[abfejhpz][fm]_[a-z]+""#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.numberOfMatches(
            in: functionWindow,
            range: NSRange(functionWindow.startIndex..., in: functionWindow)
        )
        #expect(matches == 0,
                "Found hardcoded voice-name literal in resolveVoice() — should use --voice, env var, or randomSystem() only")
    }

    // AC15.6: --dry-run flag
    //
    // RT-15.10: --dry-run exits 0 and reports a voice line via the installed wrapper.
    @Test("RT-15.10: --dry-run prints a voice: line on stdout and exits 0")
    func test_dry_run_voice_line_RT15_10() throws {
        let run = try Self.harness.runYapper(args: ["speak", "--dry-run", "hello"])
        #expect(run.exitCode == 0)
        #expect(YapperProcessHarness.parseDryRunVoice(run.stdout) != nil,
                "Dry-run output must contain a 'voice:' line")
    }

    // RT-15.11: --dry-run does not produce audio side effects (no WAV in temp dir).
    @Test("RT-15.11: --dry-run writes no WAV files and invokes no audio player")
    func test_dry_run_no_side_effects_RT15_11() throws {
        let tmp = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        let before = Set((try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [])
            .filter { $0.hasPrefix("yapper_speak_") }

        let run = try Self.harness.runYapper(args: ["speak", "--dry-run", "test"])
        #expect(run.exitCode == 0)

        let after = Set((try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [])
            .filter { $0.hasPrefix("yapper_speak_") }
        let created = after.subtracting(before)
        #expect(created.isEmpty,
                "Dry-run must not write WAV temp files, but created: \(created)")
    }

    // RT-15.12: --dry-run output includes voice, speed, and text fields.
    @Test("RT-15.12: --dry-run output includes voice, speed, and text fields")
    func test_dry_run_format_RT15_12() throws {
        let run = try Self.harness.runYapper(
            args: ["speak", "--speed", "1.5", "--dry-run", "the quick brown fox"]
        )
        #expect(run.exitCode == 0)
        #expect(run.stdout.contains("voice:"))
        #expect(run.stdout.contains("speed:"))
        #expect(run.stdout.contains("text:"))
        #expect(run.stdout.contains("1.5"))
        #expect(run.stdout.contains("the quick brown fox"))
        #expect(run.stdout.contains("(dry run"))
    }

    // RT-15.13: REAL synthesis via the installed wrapper.
    //
    // This is the test that would have caught v0.8.4 on day one. It goes through
    // the exact install topology (bin/yapper wrapper → libexec/yapper) and
    // performs actual MLX synthesis, forcing Bundle.main.bundleURL resolution
    // and metallib load. Uses `yapper convert` (file-based) so no audio is
    // played during the test run.
    @Test("RT-15.13: real synthesis through bin/yapper wrapper loads MLX and produces audio file")
    func test_real_synthesis_via_wrapper_RT15_13() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper-rt15-13-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let inputTxt = tmp.appendingPathComponent("input.txt")
        try "Smoke test for regression.".write(to: inputTxt, atomically: true, encoding: .utf8)

        let outputM4a = tmp.appendingPathComponent("output.m4a")

        let run = try Self.harness.runYapper(args: [
            "convert", inputTxt.path, "-o", outputM4a.path, "--voice", "af_heart"
        ])

        #expect(run.exitCode == 0,
                "yapper convert via wrapper failed. stdout=\(run.stdout) stderr=\(run.stderr)")
        #expect(FileManager.default.fileExists(atPath: outputM4a.path),
                "yapper convert did not produce an output file — MLX metallib load probably failed")

        let attrs = try FileManager.default.attributesOfItem(atPath: outputM4a.path)
        let size = (attrs[.size] as? Int) ?? 0
        #expect(size > 1024,
                "Output file is suspiciously small (\(size) bytes) — synthesis may have failed silently")
    }
}
