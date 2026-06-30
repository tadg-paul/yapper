// ABOUTME: CLI command for live TTS playback through system speakers.
// ABOUTME: Reads text from argument or stdin, synthesises and plays audio via per-chunk streaming.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

// Global state for SIGINT handling in the streaming playback path.
// Must be global because C signal handlers cannot capture Swift context.
private nonisolated(unsafe) var speakInterrupted = false
private nonisolated(unsafe) var speakCurrentAfplay: Process?
private nonisolated(unsafe) var speakPid: Int32 = 0

struct SpeakCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "speak",
        abstract: "Speak text aloud through system speakers."
    )

    @Argument(help: "Text to speak. If omitted, reads from stdin.")
    var text: String?

    @Option(name: .long, help: "Voice name (e.g. af_heart, bm_daniel). Default: af_heart.")
    var voice: String?

    @Flag(name: .long, help: "Use a random voice instead of the default.")
    var randomVoice: Bool = false

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Flag(name: .long, help: "Print resolved voice, speed, and text without performing synthesis.")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress progress output.")
    var quiet: Bool = false

    func run() throws {
        let rawText = try resolveInputText()

        // Load config cascade for substitutions
        let mergedConfig = ScriptConfig.loadMerged()
        let substitutions = mergedConfig.speechSubstitution ?? [:]
        let inputText = ProsePreprocessor.preprocess(
            rawText,
            substitutions: substitutions
        ).text

        // Dry-run path: load only the voice registry (cheap, no 327MB model weights),
        // resolve the voice, print the resolved parameters, and exit without synthesising.
        if dryRun {
            let registry = try VoiceRegistry(voicesPath: defaultVoicesPath())
            let resolved = try resolveVoice(registry: registry)
            print("voice:  \(resolved.name)")
            print("speed:  \(speed)")
            print("text:   \(inputText)")
            print("(dry run — no synthesis performed)")
            return
        }

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        let selectedVoice = try resolveVoice(registry: engine.voiceRegistry)

        // Look-ahead synthesis: synthesise chunk N+1 while chunk N plays.
        // Eliminates the audible gaps between chunks that occurred when synthesis
        // and playback were sequential.
        speakPid = ProcessInfo.processInfo.processIdentifier
        speakInterrupted = false
        speakCurrentAfplay = nil
        let tmpDir = FileManager.default.temporaryDirectory

        // Pre-chunk for progress reporter and look-ahead coordination
        let chunker = TextChunker()
        let chunks = chunker.chunk(inputText)
        var reporter = ProgressReporter(totalChunks: chunks.count, quiet: quiet)

        signal(SIGINT) { _ in
            speakInterrupted = true
            speakCurrentAfplay?.interrupt()
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(atPath: NSTemporaryDirectory()) {
                for file in files where file.hasPrefix("yapper_speak_\(speakPid)") {
                    try? fm.removeItem(atPath: NSTemporaryDirectory() + file)
                }
            }
            _exit(130)
        }

        // For single-chunk input, no look-ahead needed — synthesise and play directly
        if chunks.count <= 1 {
            try engine.stream(text: inputText, voice: selectedVoice, speed: speed) { chunk in
                guard !speakInterrupted else { return }
                reporter.update(chunkText: chunks.first?.text ?? "")
                let tmpPath = tmpDir.appendingPathComponent("yapper_speak_\(speakPid)_1.wav")
                do {
                    try writeWav(samples: chunk.samples, sampleRate: 24000, to: tmpPath)
                    let afplay = Process()
                    afplay.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    afplay.arguments = [tmpPath.path]
                    afplay.standardInput = FileHandle.nullDevice
                    speakCurrentAfplay = afplay
                    try afplay.run()
                    afplay.waitUntilExit()
                    speakCurrentAfplay = nil
                    try? FileManager.default.removeItem(at: tmpPath)
                } catch {
                    try? FileManager.default.removeItem(at: tmpPath)
                }
            }
        } else {
            // Look-ahead synthesis with a pre-fill buffer.
            // Synthesise the first N chunks before starting playback, building a
            // buffer that absorbs synthesis time variability. Then continue
            // synthesising ahead while playback runs. Playback never catches up
            // to synthesis unless a single chunk takes longer than the entire
            // buffer's audio duration.
            let bufferSize = min(3, chunks.count)
            nonisolated(unsafe) var synthesisError: Error? = nil
            nonisolated(unsafe) var chunkIndex = 0
            nonisolated(unsafe) var reporterCopy = reporter

            // Thread-safe FIFO queue of ready WAV paths
            let queueLock = NSLock()
            nonisolated(unsafe) var wavQueue: [URL] = []
            let itemAvailable = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var producerDone = false

            let synthQueue = DispatchQueue(label: "yapper.speak.synthesis")
            nonisolated(unsafe) let engineRef = engine
            let voiceRef = selectedVoice
            let speedVal = speed
            let inputRef = inputText
            let chunksRef = chunks

            // Show first chunk text before synthesis starts
            if !chunks.isEmpty {
                reporterCopy.update(chunkText: chunksRef[0].text)
            }

            synthQueue.async {
                do {
                    try engineRef.stream(text: inputRef, voice: voiceRef, speed: speedVal) { chunk in
                        guard !speakInterrupted else { return }

                        chunkIndex += 1
                        let wavPath = tmpDir.appendingPathComponent(
                            "yapper_speak_\(speakPid)_\(chunkIndex).wav")
                        do {
                            try self.writeWav(samples: chunk.samples, sampleRate: 24000, to: wavPath)
                            queueLock.lock()
                            wavQueue.append(wavPath)
                            queueLock.unlock()
                            itemAvailable.signal()

                            // Show the NEXT chunk's text (about to be synthesised)
                            if chunkIndex < chunksRef.count {
                                reporterCopy.update(chunkText: chunksRef[chunkIndex].text)
                            }
                        } catch {
                            synthesisError = error
                            itemAvailable.signal()
                        }
                    }
                } catch {
                    synthesisError = error
                }

                producerDone = true
                itemAvailable.signal()
            }

            // Main thread: wait for buffer to fill, then start playback
            var buffered = 0
            while buffered < bufferSize && !speakInterrupted {
                itemAvailable.wait()
                queueLock.lock()
                let ready = wavQueue.count
                queueLock.unlock()
                if ready > buffered {
                    buffered = ready
                }
                if producerDone || synthesisError != nil { break }
            }

            // Play from the queue — producer continues filling it
            while !speakInterrupted {
                // Try to get the next WAV from the queue
                queueLock.lock()
                let wavPath = wavQueue.isEmpty ? nil : wavQueue.removeFirst()
                queueLock.unlock()

                guard let wavPath else {
                    // Queue empty — wait for producer or end-of-stream
                    if producerDone { break }
                    itemAvailable.wait()
                    if producerDone {
                        // Drain remaining items
                        queueLock.lock()
                        let remaining = wavQueue
                        wavQueue.removeAll()
                        queueLock.unlock()
                        for wav in remaining {
                            guard !speakInterrupted else { break }
                            do {
                                let afplay = Process()
                                afplay.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                                afplay.arguments = [wav.path]
                                afplay.standardInput = FileHandle.nullDevice
                                speakCurrentAfplay = afplay
                                try afplay.run()
                                afplay.waitUntilExit()
                                speakCurrentAfplay = nil
                                try? FileManager.default.removeItem(at: wav)
                            } catch {
                                try? FileManager.default.removeItem(at: wav)
                            }
                        }
                        break
                    }
                    continue
                }

                do {
                    let afplay = Process()
                    afplay.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    afplay.arguments = [wavPath.path]
                    afplay.standardInput = FileHandle.nullDevice
                    speakCurrentAfplay = afplay
                    try afplay.run()
                    afplay.waitUntilExit()
                    speakCurrentAfplay = nil
                    try? FileManager.default.removeItem(at: wavPath)
                } catch {
                    try? FileManager.default.removeItem(at: wavPath)
                    break
                }
            }

            if let error = synthesisError {
                throw error
            }
        }

        reporter.finish(summary: "")

        // Final cleanup — remove any lingering temp files for this PID
        let pid = speakPid
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path) {
            for file in files where file.hasPrefix("yapper_speak_\(pid)") {
                try? FileManager.default.removeItem(at: tmpDir.appendingPathComponent(file))
            }
        }
    }

    private func resolveInputText() throws -> String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        // Read from stdin if no argument and stdin is piped
        if isatty(FileHandle.standardInput.fileDescriptor) == 0 {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let stdinText = String(data: data, encoding: .utf8),
                  !stdinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("No text provided. Stdin was empty or not valid UTF-8.")
            }
            return stdinText
        }

        throw ValidationError(
            "No text provided. Usage: yapper speak \"text\" or echo \"text\" | yapper speak"
        )
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

    /// Resolve the voice to use for this invocation.
    ///
    /// Precedence (highest first):
    ///   1. `--voice <name>` CLI flag
    ///   2. `$YAPPER_VOICE` environment variable
    ///   3. Random selection from the registry (non-deterministic per call)
    ///
    /// Invalid names from either --voice or $YAPPER_VOICE produce a clear error
    /// identifying the source — no silent fallback to random or any hardcoded voice.
    private func resolveVoice(registry: VoiceRegistry) throws -> Voice {
        // 1. --voice CLI flag wins unconditionally
        if let voiceName = voice {
            return try lookupVoice(voiceName, in: registry, source: "--voice flag")
        }
        // 2. $YAPPER_VOICE env var — whitespace-only treated as unset
        if let raw = ProcessInfo.processInfo.environment["YAPPER_VOICE"] {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return try lookupVoice(trimmed, in: registry, source: "$YAPPER_VOICE")
            }
        }
        // 3. --random-voice flag: pick a random voice
        if randomVoice {
            guard let chosen = registry.randomSystem() else {
                throw ValidationError(
                    "No voices found in the registry at \(registry.voicesPath.path)."
                )
            }
            return chosen
        }
        // 4. Default: af_heart (highest fidelity)
        if let heart = registry.voices.first(where: { $0.name == "af_heart" }) {
            return heart
        }
        guard let chosen = registry.voices.first else {
            throw ValidationError(
                "No voices found in the registry at \(registry.voicesPath.path)."
            )
        }
        return chosen
    }

    private func lookupVoice(_ name: String, in registry: VoiceRegistry, source: String) throws -> Voice {
        guard let v = registry.voices.first(where: { $0.name == name }) else {
            let available = registry.voices.prefix(5).map(\.name).joined(separator: ", ")
            throw ValidationError(
                "Voice '\(name)' not found (from \(source)). Available: \(available)..."
            )
        }
        return v
    }
}
