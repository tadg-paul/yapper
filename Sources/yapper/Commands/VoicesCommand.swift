// ABOUTME: CLI command to list available voices and preview them.
// ABOUTME: Displays voice metadata in a formatted table, or previews with speech.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct VoicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "voices",
        abstract: "List available voices or preview a voice."
    )

    @Option(name: .long, help: "Preview a voice. Accepts a voice name (bf_emma), filter shorthand (bf), or 'all'. Optional text follows as trailing arguments.")
    var preview: String?

    @Option(name: .long, help: "Speech engine: yapper (default), fal, openai.")
    var engine: String?

    @Option(name: .long, help: "Explicit Yapper configuration file.")
    var config: String?

    @Argument(help: "Text to speak. If omitted, uses the standard Stella passage. Use '-' to read from stdin.")
    var text: [String] = []

    @Flag(name: .customShort("1"), help: "List voice names only, one per line.")
    var onePerLine: Bool = false

    @Flag(name: .long, help: "Use the full Stella passage for preview (default uses a shorter excerpt).")
    var full: Bool = false

    func run() throws {
        let mergedConfig = try ScriptConfig.loadMerged(
            explicitPath: config,
            inputDir: FileManager.default.currentDirectoryPath
        )
        let selectedEngine = SpeechEngineID(engine ?? mergedConfig.selectedEngine ?? "yapper")
        guard [SpeechEngineID.yapper, .fal, .openAI].contains(selectedEngine) else {
            throw ValidationError(
                "Unsupported engine '\(selectedEngine)'. Available engines: yapper, fal, openai."
            )
        }
        if selectedEngine != .yapper {
            try runConfiguredProviderVoices(engineID: selectedEngine, config: mergedConfig)
            return
        }

        if let previewSpec = preview {
            let engine = try YapperEngine(
                modelPath: defaultModelPath(),
                voicesPath: defaultVoicesPath()
            )

            // Determine which voices to preview
            let voicesToPreview: [Voice]
            if previewSpec.lowercased() == "all" {
                voicesToPreview = engine.voiceRegistry.voices
            } else if let exact = engine.voiceRegistry.voices.first(where: { $0.name == previewSpec }) {
                voicesToPreview = [exact]
            } else if previewSpec.count <= 3, let filter = VoiceAssigner.parseFilterPublic(previewSpec) {
                let matched = engine.voiceRegistry.list(filter: filter)
                if matched.isEmpty {
                    throw ValidationError("No voices match filter '\(previewSpec)'.")
                }
                voicesToPreview = matched
            } else {
                let available = engine.voiceRegistry.voices.prefix(5).map(\.name).joined(separator: ", ")
                throw ValidationError("Voice '\(previewSpec)' not found. Available: \(available)...")
            }

            // Resolve the text to speak
            let spokenText = resolvePreviewText()

            for voice in voicesToPreview {
                try previewVoice(engine: engine, voice: voice, text: spokenText)
            }
        } else if onePerLine {
            let registry = try VoiceRegistry(voicesPath: defaultVoicesPath())
            for voice in registry.voices {
                print(voice.name)
            }
        } else {
            let registry = try VoiceRegistry(voicesPath: defaultVoicesPath())
            listVoices(registry: registry)
        }
    }

    private func runConfiguredProviderVoices(
        engineID: SpeechEngineID,
        config mergedConfig: ScriptConfig
    ) throws {
        let engineConfig = mergedConfig.engineConfig(engineID.rawValue)
        let scriptConfig = mergedConfig.scriptVoiceConfig(engineID.rawValue)
        var voices: [String] = []
        func append(_ voice: String?) {
            guard let voice, !voices.contains(voice) else { return }
            voices.append(voice)
        }
        append(engineConfig?.voice)
        for voice in scriptConfig?.pool ?? [] { append(voice) }
        append(scriptConfig?.narrator)
        append(scriptConfig?.intro)
        for voice in scriptConfig?.characters?.values.sorted() ?? [] { append(voice) }
        if voices.isEmpty {
            append(engineID == .fal ? "Rachel" : "alloy")
        }

        guard let preview else {
            if onePerLine {
                voices.forEach { print($0) }
            } else {
                print("Configured voices for \(engineID):")
                voices.forEach { print("  \($0)") }
                print("\n\(voices.count) configured voices available; provider catalogue discovery is unavailable.")
            }
            return
        }

        let selectedVoices: [String]
        if preview.lowercased() == "all" {
            selectedVoices = voices
        } else if voices.contains(preview) {
            selectedVoices = [preview]
        } else {
            throw ValidationError(
                "Voice '\(preview)' is not configured for engine '\(engineID)'. Configured: \(voices.joined(separator: ", "))."
            )
        }
        for voice in selectedVoices {
            try runProviderPreview(engineID: engineID, voice: voice)
        }
    }

    private func runProviderPreview(engineID: SpeechEngineID, voice: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        var arguments = ["speak", "--engine", engineID.rawValue, "--voice", voice]
        if let config {
            arguments.append(contentsOf: ["--config", config])
        }
        arguments.append(resolvePreviewText() ?? stellaText)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationError(
                "Voice preview for engine '\(engineID)' exited with status \(process.terminationStatus)."
            )
        }
    }

    /// Short excerpt of the Stella passage (default preview).
    private static let stellaShort = "Please call Stella. Ask her to bring these things with her from the store: Six spoons of fresh snow peas, five thick slabs of blue cheese, and maybe a snack for her brother Bob."

    /// Full Stella passage (--full flag).
    private static let stellaFull = "Please call Stella. Ask her to bring these things with her from the store: Six spoons of fresh snow peas, five thick slabs of blue cheese, and maybe a snack for her brother Bob. We also need a small plastic snake and a big toy frog for the kids. She can scoop these things into three red bags, and we will go meet her Wednesday at the train station."

    /// The Stella passage to use, based on --full flag.
    private var stellaText: String {
        full ? Self.stellaFull : Self.stellaShort
    }

    /// Resolve what text to speak for preview.
    private func resolvePreviewText() -> String? {
        if text.isEmpty {
            return nil  // Will use default (Stella passage with voice intro)
        }
        if text.count == 1 && text[0] == "-" {
            // Read from stdin
            var lines: [String] = []
            while let line = readLine() {
                lines.append(line)
            }
            return lines.joined(separator: "\n")
        }
        return text.joined(separator: " ")
    }

    /// Format voice name for pronunciation: "bf_emma" → "B.F. Emma"
    private func pronounceableName(_ voice: Voice) -> String {
        let parts = voice.name.split(separator: "_")
        guard parts.count == 2 else { return voice.name }
        let prefix = parts[0].uppercased().map { String($0) }.joined(separator: ".")
        let name = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        return "\(prefix). \(name)"
    }

    private func listVoices(registry: VoiceRegistry) {
        let voices = registry.voices

        if voices.isEmpty {
            fputs("No voices found in \(defaultVoicesPath().path)\n", stderr)
            fputs("Download voices from https://huggingface.co/mlx-community/Kokoro-82M-bf16\n", stderr)
            return
        }

        // Header
        print("Name".padding(toLength: 14, withPad: " ", startingAt: 0)
            + "Accent".padding(toLength: 10, withPad: " ", startingAt: 0)
            + "Gender")
        print(String(repeating: "-", count: 34))

        for voice in voices {
            let accentLabel = voice.accent == .american ? "American" : "British"
            let genderLabel = voice.gender == .female ? "Female" : "Male"
            print(voice.name.padding(toLength: 14, withPad: " ", startingAt: 0)
                + accentLabel.padding(toLength: 10, withPad: " ", startingAt: 0)
                + genderLabel)
        }

        print("\n\(voices.count) voices available.")
    }

    private func previewVoice(engine: YapperEngine, voice: Voice, text customText: String?) throws {
        let pName = pronounceableName(voice)

        let spokenText: String
        if let custom = customText {
            spokenText = "\(pName) here: \(custom)"
        } else {
            spokenText = "\(pName) here: \(stellaText)"
        }

        fputs("\(voice.name) speaking: \(customText ?? stellaText)\n", stderr)

        let result = try engine.synthesize(text: spokenText, voice: voice, speed: 1.0)

        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_preview_\(ProcessInfo.processInfo.processIdentifier).wav")
        try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: tmpPath)
        defer { try? FileManager.default.removeItem(at: tmpPath) }

        signal(SIGINT) { _ in _exit(130) }

        let afplay = Process()
        afplay.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        afplay.arguments = [tmpPath.path]
        try afplay.run()
        afplay.waitUntilExit()
    }

    private func writeWav(samples: [Float], sampleRate: Int, to url: URL) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ValidationError("Failed to create audio buffer")
        }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
