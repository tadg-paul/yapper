// ABOUTME: CLI command for converting text files to audio (M4A/MP3/M4B).
// ABOUTME: Synthesises via YapperKit, encodes via ffmpeg. Supports audiobook mode.

import ArgumentParser
import AVFoundation
import Foundation
import YapperKit

struct ConvertCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert text files to audio or audiobooks."
    )

    @Argument(help: "Input file(s) to convert.")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output file path.")
    var output: String?

    @Option(name: .long, help: "Output format: m4a (default), m4b, mp3. Auto-selects m4b for multi-chapter input.")
    var format: String?

    @Option(name: .long, help: "Voice name for all chapters (e.g. af_heart).")
    var voice: String?

    @Option(name: .long, help: "Random voice filter (e.g. bf for British female). Default: random per chapter.")
    var randomVoice: String?

    @Option(name: .long, help: "Speech speed multiplier (default: 1.0).")
    var speed: Float = 1.0

    @Option(name: .long, help: "Author metadata for the output file.")
    var author: String?

    @Option(name: .long, help: "Title metadata for the output file.")
    var title: String?

    @Flag(name: .long, help: "Show what would be done without converting.")
    var dryRun: Bool = false

    @Flag(name: .long, help: "Force interactive prompts even when stdin is not a TTY.")
    var interactive: Bool = false

    @Flag(name: .long, help: "Skip interactive prompts regardless of TTY state.")
    var nonInteractive: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress progress output.")
    var quiet: Bool = false

    @Option(name: .long, help: "Path to script.yaml config file for script-reading mode.")
    var scriptConfig: String?

    @Flag(name: .long, help: "Force script mode using defaults (or global config). No script.yaml required.")
    var script: Bool = false

    @Option(name: .long, help: "Number of concurrent synthesis worker processes (default: 3). Use 1 for sequential.")
    var threads: Int?

    // Hidden worker flags for multi-process synthesis
    @Option(name: .long, help: .hidden)
    var workerText: String?

    @Option(name: .long, help: .hidden)
    var workerVoice: String?

    @Option(name: .long, help: .hidden)
    var workerOutput: String?

    func run() throws {
        // Worker mode: synthesise a single line and exit
        if let text = workerText, let voiceName = workerVoice, let outputPath = workerOutput {
            try runWorker(text: text, voiceName: voiceName, outputPath: outputPath)
            return
        }

        guard !inputs.isEmpty else {
            throw ValidationError("No input files specified.")
        }

        // Pre-flight: detect commands that would write then overwrite the same file
        if inputs.count > 1, let output {
            let outputExt = URL(fileURLWithPath: output).pathExtension.lowercased()
            let isAudiobook = (format?.lowercased() == "m4b") || outputExt == "m4b"
            if !isAudiobook {
                // Multiple inputs with a single non-M4B output path would overwrite itself
                throw ValidationError(
                    "Multiple input files with a single output path '\(output)' would overwrite "
                    + "the file on each iteration. Use -o with an .m4b extension to combine into "
                    + "an audiobook, or omit -o to produce one file per input."
                )
            }
        }

        // Script mode: detect config file, --script flag, or yapper.yaml with script keys
        let hasScriptConfig = script || scriptConfig != nil || {
            guard inputs.count == 1 else { return false }
            let dir = URL(fileURLWithPath: inputs[0]).deletingLastPathComponent().path
            if FileManager.default.fileExists(atPath: "\(dir)/script.yaml") { return true }
            // Also check yapper.yaml for script-specific keys
            if FileManager.default.fileExists(atPath: "\(dir)/yapper.yaml"),
               let config = try? ScriptConfig.load(from: "\(dir)/yapper.yaml"),
               config.characterVoices != nil || config.narratorVoice != nil
                   || config.render != nil || config.renderStageDirections != nil {
                return true
            }
            return false
        }()

        if hasScriptConfig {
            if let scriptDoc = try detectAndParseScript() {
                if !quiet {
                    let configSource: String
                    if script { configSource = "--script flag" }
                    else { configSource = scriptConfig ?? "script.yaml (auto-discovered)" }
                    fputs("Script mode: using \(configSource)\n", stderr)
                }
                if dryRun {
                    try printScriptDryRun(scriptDoc)
                } else {
                    let engine = try YapperEngine(
                        modelPath: defaultModelPath(),
                        voicesPath: defaultVoicesPath()
                    )
                    try runScriptMode(engine: engine, script: scriptDoc)
                }
                return
            } else {
                // Config present but no parseable script content — fatal error
                throw ValidationError(
                    "Script config found but input file contains no parseable script content: \(inputs[0])")
            }
        }

        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )

        // The OUTPUT FORMAT determines the file topology:
        //
        // M4B → package everything into one audiobook file with chapter markers.
        //       Works for single multi-chapter inputs (epub, PDF) and for
        //       multiple independent inputs (treated as chapters of one book).
        //
        // M4A/MP3 → one output file per chapter or per input file.
        //           An epub with 12 chapters produces 12 M4As. Three text files
        //           produce three M4As. Metadata is applied to each file.
        // The OUTPUT FORMAT determines the file topology:
        //
        // M4B → always package everything into one audiobook file.
        //       A single epub or multiple txt files become chapters.
        //
        // M4A/MP3 with a single multi-chapter input (epub, PDF) →
        //       one file per chapter, named by chapter title.
        //
        // M4A/MP3 with multiple independent input files →
        //       one file per input, named after the input file.
        //       Missing/invalid files are skipped with a warning (not aborted).
        if inputs.count == 1 {
            let chapters = try gatherChapters()
            let fmt = resolveFormat(multiChapter: chapters.count > 1)
            if fmt == "m4b" {
                try runAudiobookMode(engine: engine, chapters: chapters)
            } else if chapters.count > 1 {
                try runChapterPerFileMode(engine: engine, chapters: chapters, format: fmt)
            } else {
                try runSingleFileMode(engine: engine)
            }
        } else {
            // Multiple inputs: check if M4B output is intended
            let isM4B: Bool
            if let format {
                isM4B = format.lowercased() == "m4b"
            } else if let output, output.lowercased().hasSuffix(".m4b") {
                isM4B = true
            } else {
                isM4B = false
            }

            if isM4B {
                // Multiple inputs → package as audiobook with chapters
                let chapters = try gatherChapters()
                try runAudiobookMode(engine: engine, chapters: chapters)
            } else {
                // Multiple inputs + M4A/MP3 → one file per input, skip failures
                try runSingleFileMode(engine: engine)
            }
        }
    }

    // MARK: - Chapter gathering

    private func gatherChapters() throws -> [Chapter] {
        var allChapters: [Chapter] = []

        for input in inputs {
            guard FileManager.default.fileExists(atPath: input) else {
                throw ValidationError("Input file not found: \(input)")
            }

            let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
            if ["epub", "mobi", "pdf", "docx", "odt", "md", "html", "txt"].contains(ext) {
                let chapters = try DocumentConverter.convert(input)
                allChapters.append(contentsOf: chapters)
            } else {
                // Try as plain text
                let data = try Data(contentsOf: URL(fileURLWithPath: input))
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ValidationError("File is not valid UTF-8: \(input)")
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw ValidationError("File is empty: \(input)")
                }
                let name = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
                allChapters.append(Chapter(title: name, text: trimmed))
            }
        }

        return allChapters
    }

    // MARK: - Audiobook mode

    private func runAudiobookMode(engine: YapperEngine, chapters: [Chapter]) throws {
        let outputFormat = resolveFormat(multiChapter: true)
        let outputPath = resolveAudiobookOutputPath(format: outputFormat)

        // Load merged config for substitutions
        let inputDir = inputs.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let mergedConfig = ScriptConfig.loadMerged(explicitPath: scriptConfig, inputDir: inputDir)
        let substitutions = mergedConfig.speechSubstitution ?? [:]

        // Resolve metadata
        let (resolvedAuthor, resolvedTitle) = resolveMetadata(chapters: chapters)

        // Assign voices
        let voices = assignVoices(engine: engine, chapterCount: chapters.count)

        if dryRun {
            print("Audiobook conversion plan:")
            print("  Output: \(outputPath)")
            print("  Format: \(outputFormat)")
            print("  Chapters: \(chapters.count)")
            if let resolvedAuthor { print("  Author: \(resolvedAuthor)") }
            if let resolvedTitle { print("  Title: \(resolvedTitle)") }
            for (i, chapter) in chapters.enumerated() {
                print("  [\(i + 1)/\(chapters.count)] \(chapter.title) (\(voices[i].name))")
            }
            return
        }

        // Back up existing output
        if FileManager.default.fileExists(atPath: outputPath) {
            let backupPath = nextBackupPath(for: outputPath)
            try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            fputs("Backed up existing \(outputPath) to \(backupPath)\n", stderr)
        }

        fputs("Converting: \(inputs.joined(separator: ", ")) (\(chapters.count) chapters)\n", stderr)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_audiobook_\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var chapterInfo: [(title: String, aacPath: String, duration: Double)] = []

        for (i, chapter) in chapters.enumerated() {
            let voice = voices[i]
            fputs("  [\(i + 1)/\(chapters.count)] \(chapter.title) (\(voice.name)) ... ", stderr)

            let chapterText = ProsePreprocessor.preprocess(
                chapter.text,
                substitutions: substitutions
            ).text
            let result = try engine.synthesize(text: chapterText, voice: voice, speed: speed)
            let duration = Double(result.samples.count) / Double(result.sampleRate)

            // Write WAV
            let wavPath = tmpDir.appendingPathComponent("ch\(i + 1).wav")
            try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: wavPath)

            // Encode AAC
            let aacPath = tmpDir.appendingPathComponent("ch\(i + 1).aac").path
            try AudiobookAssembler.encodeAAC(wavPath: wavPath.path, output: aacPath)
            try? FileManager.default.removeItem(at: wavPath)

            chapterInfo.append((title: chapter.title, aacPath: aacPath, duration: duration))
            fputs("\(String(format: "%.1f", duration))s\n", stderr)
        }

        if outputFormat == "m4b" {
            // Assemble M4B with chapter markers
            try AudiobookAssembler.assembleM4B(
                chapters: chapterInfo,
                output: outputPath,
                title: resolvedTitle,
                author: resolvedAuthor,
                coverArtPath: nil // TODO: extract from epub
            )
        } else {
            // For MP3/M4A: concatenate and encode
            try assembleSingleFile(chapterInfo: chapterInfo, output: outputPath,
                                   format: outputFormat, author: resolvedAuthor, title: resolvedTitle)
        }

        let totalDuration = chapterInfo.reduce(0.0) { $0 + $1.duration }
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        fputs("Created \(outputPath) (\(minutes):\(String(format: "%02d", seconds)))\n", stderr)
    }

    // MARK: - Chapter-per-file mode (M4A/MP3 from multi-chapter input)

    /// Produces one output file per chapter. Used when a multi-chapter input
    /// (epub, PDF with headings, or multiple input files) is converted to M4A
    /// or MP3 — formats that don't support chapter markers.
    private func runChapterPerFileMode(engine: YapperEngine, chapters: [Chapter], format: String) throws {
        let voices = assignVoices(engine: engine, chapterCount: chapters.count)
        let (resolvedAuthor, resolvedTitle) = resolveMetadata(chapters: chapters)
        let inputDir = inputs.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let mergedConfig = ScriptConfig.loadMerged(explicitPath: scriptConfig, inputDir: inputDir)
        let substitutions = mergedConfig.speechSubstitution ?? [:]

        // Derive output directory from -o flag or first input's directory
        let outputDir: String
        if let output {
            // If -o points to a directory, use it; if it's a file path, use its directory
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: output, isDirectory: &isDir), isDir.boolValue {
                outputDir = output
            } else {
                outputDir = URL(fileURLWithPath: output).deletingLastPathComponent().path
            }
        } else {
            outputDir = URL(fileURLWithPath: inputs[0]).deletingLastPathComponent().path
        }

        if dryRun {
            print("Chapter-per-file conversion plan:")
            print("  Output directory: \(outputDir)")
            print("  Format: \(format)")
            print("  Chapters: \(chapters.count)")
            if let resolvedAuthor { print("  Author: \(resolvedAuthor)") }
            if let resolvedTitle { print("  Title: \(resolvedTitle)") }
            for (i, chapter) in chapters.enumerated() {
                let filename = chapterFilename(index: i, title: chapter.title, format: format)
                print("  [\(i + 1)/\(chapters.count)] \(filename) (\(voices[i].name))")
            }
            return
        }

        fputs("Converting: \(chapters.count) chapters to \(format)\n", stderr)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_chapters_\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        for (i, chapter) in chapters.enumerated() {
            let voice = voices[i]
            let filename = chapterFilename(index: i, title: chapter.title, format: format)
            let outputPath = "\(outputDir)/\(filename)"

            fputs("  [\(i + 1)/\(chapters.count)] \(filename) (\(voice.name)) ... ", stderr)

            let chapterText = ProsePreprocessor.preprocess(
                chapter.text,
                substitutions: substitutions
            ).text
            let result = try engine.synthesize(text: chapterText, voice: voice, speed: speed)
            let duration = Double(result.samples.count) / Double(result.sampleRate)

            // Write WAV
            let wavPath = tmpDir.appendingPathComponent("ch\(i + 1).wav")
            try writeWav(samples: result.samples, sampleRate: result.sampleRate, to: wavPath)

            // Encode to target format with metadata
            if FileManager.default.fileExists(atPath: outputPath) {
                let backupPath = nextBackupPath(for: outputPath)
                try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            }
            try encodeWithFFmpeg(
                input: wavPath.path,
                output: outputPath,
                format: format,
                author: resolvedAuthor,
                title: resolvedTitle,
                trackNumber: i + 1,
                trackTotal: chapters.count,
                trackTitle: chapter.title
            )
            try? FileManager.default.removeItem(at: wavPath)

            fputs("\(String(format: "%.1f", duration))s\n", stderr)
        }

        fputs("Created \(chapters.count) files in \(outputDir)\n", stderr)
    }

    /// Generate a filename for an individual chapter output file.
    private func chapterFilename(index: Int, title: String, format: String) -> String {
        let paddedIndex = String(format: "%02d", index + 1)
        // Sanitise the title for use as a filename
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if safe.isEmpty {
            return "chapter_\(paddedIndex).\(format)"
        }
        return "\(paddedIndex)_\(safe).\(format)"
    }

    // MARK: - Single file mode

    private func runSingleFileMode(engine: YapperEngine) throws {
        let fmt = resolveFormat(multiChapter: false)

        guard ["m4a", "mp3", "m4b"].contains(fmt) else {
            throw ValidationError("Unsupported format '\(fmt)'. Use m4a, mp3, or m4b.")
        }

        // Load merged config for substitutions
        let inputDir = inputs.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let mergedConfig = ScriptConfig.loadMerged(explicitPath: scriptConfig, inputDir: inputDir)
        let substitutions = mergedConfig.speechSubstitution ?? [:]

        let selectedVoice = try resolveVoice(engine: engine, voiceName: voice)

        // Resolve metadata (prompts interactively if TTY, pre-fills from epub)
        let chapters = inputs.map { Chapter(title: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent, text: "") }
        let (resolvedAuthor, resolvedTitle) = resolveMetadata(chapters: chapters)

        // Extract track numbers from filenames
        let trackNumbers = extractTrackNumbers(from: inputs)

        var successes: [String] = []
        var failures: [String] = []
        for (i, input) in inputs.enumerated() {
            if inputs.count > 1 {
                let voiceName = selectedVoice.name
                ProgressReporter.fileHeader("[\(i + 1)/\(inputs.count)] \(URL(fileURLWithPath: input).lastPathComponent) (\(voiceName))", quiet: quiet)
            }
            do {
                try convertSingleFile(
                    input: input,
                    engine: engine,
                    voice: selectedVoice,
                    format: fmt,
                    author: resolvedAuthor,
                    title: resolvedTitle,
                    trackNumber: trackNumbers[i],
                    trackTotal: inputs.count,
                    substitutions: substitutions
                )
                successes.append(input)
            } catch {
                fputs("Error converting \(input): \(error)\n", stderr)
                failures.append(input)
            }
        }

        // Batch summary
        if inputs.count > 1 && !quiet {
            if !successes.isEmpty {
                fputs("\(successes.count) of \(inputs.count) files converted successfully.\n", stderr)
            }
            if !failures.isEmpty {
                fputs("\(failures.count) of \(inputs.count) files failed:\n", stderr)
                for f in failures { fputs("  \(f)\n", stderr) }
            }
        }
        if !failures.isEmpty {
            throw ExitCode(1)
        }
    }

    private func convertSingleFile(
        input: String,
        engine: YapperEngine,
        voice: Voice,
        format: String,
        author: String? = nil,
        title: String? = nil,
        trackNumber: Int? = nil,
        trackTotal: Int? = nil,
        substitutions: [String: String] = [:]
    ) throws {
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("Input file not found: \(input)")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        guard let text = String(data: data, encoding: .utf8) else {
            throw ValidationError("File is not valid UTF-8: \(input). Convert to UTF-8 first.")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("File is empty or whitespace-only: \(input)")
        }

        let preprocessed = ProsePreprocessor.preprocess(trimmed, substitutions: substitutions)
        let cleaned = preprocessed.text

        let outputPath = resolveOutputPath(for: input, format: format)
        let trackTitle = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent

        if dryRun {
            print("Would convert: \(input)")
            print("  Output: \(outputPath)")
            print("  Format: \(format)")
            print("  Voice: \(voice.name)")
            print("  Speed: \(speed)")
            if let author { print("  Author: \(author)") }
            if let title { print("  Title: \(title)") }
            if let trackNumber {
                let trackStr = trackTotal != nil ? "\(trackNumber)/\(trackTotal!)" : "\(trackNumber)"
                print("  Track: \(trackStr)")
            }
            print("  Track title: \(trackTitle)")
            printPreprocessingDiagnostics(preprocessed)
            print("  Text: \(cleaned)")
            return
        }

        // Check output directory exists before spending time on synthesis
        let outputDir = URL(fileURLWithPath: outputPath).deletingLastPathComponent().path
        if !outputDir.isEmpty && outputDir != "." {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: outputDir, isDirectory: &isDir) || !isDir.boolValue {
                throw ValidationError("Output directory does not exist: \(outputDir)")
            }
        }

        if FileManager.default.fileExists(atPath: outputPath) {
            let backupPath = nextBackupPath(for: outputPath)
            try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            fputs("Backed up existing \(outputPath) to \(backupPath)\n", stderr)
        }

        // Pre-chunk for progress reporting
        let chunker = TextChunker()
        let textChunks = chunker.chunk(cleaned)
        let fileLabel = URL(fileURLWithPath: input).lastPathComponent
        ProgressReporter.fileHeader("Synthesising \(fileLabel)...", quiet: quiet)
        var reporter = ProgressReporter(totalChunks: textChunks.count, quiet: quiet)

        // Synthesise with per-chunk progress
        var allSamples: [Float] = []
        var chunkIdx = 0
        try engine.stream(text: cleaned, voice: voice, speed: speed) { chunk in
            let chunkText = chunkIdx < textChunks.count ? textChunks[chunkIdx].text : ""
            chunkIdx += 1
            reporter.update(chunkText: chunkText)
            allSamples.append(contentsOf: chunk.samples)
        }
        let sampleRate = 24000
        reporter.finish(summary: "")

        let tmpWav = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_convert_\(ProcessInfo.processInfo.processIdentifier).wav")
        try writeWav(samples: allSamples, sampleRate: sampleRate, to: tmpWav)
        defer { try? FileManager.default.removeItem(at: tmpWav) }

        try encodeWithFFmpeg(
            input: tmpWav.path,
            output: outputPath,
            format: format,
            author: author,
            title: title,
            trackNumber: trackNumber,
            trackTotal: trackTotal,
            trackTitle: trackTitle
        )

        let duration = Double(allSamples.count) / Double(sampleRate)
        if !quiet {
            fputs("Created \(outputPath) (\(String(format: "%.1f", duration))s)\n", stderr)
        }
    }

    // MARK: - Voice assignment

    private func assignVoices(engine: YapperEngine, chapterCount: Int) -> [Voice] {
        if let voiceName = voice {
            let v = engine.voiceRegistry.voices.first { $0.name == voiceName }
                ?? engine.voiceRegistry.voices[0]
            return Array(repeating: v, count: chapterCount)
        }

        // Random per chapter, seeded by first input filename
        let seed = inputs.first.map { $0.hashValue } ?? 0
        let filter: VoiceFilter?
        if let randomVoice {
            let accent = Accent(rawValue: String(randomVoice.prefix(1)))
            let gender = randomVoice.count > 1 ? Gender(rawValue: String(randomVoice.dropFirst().prefix(1))) : nil
            filter = VoiceFilter(accent: accent, gender: gender)
        } else {
            filter = nil
        }

        return (0..<chapterCount).map { i in
            engine.voiceRegistry.random(filter: filter, seed: UInt64(abs(seed &+ i))) ?? engine.voiceRegistry.voices[0]
        }
    }

    // MARK: - Metadata resolution

    private func resolveMetadata(
        chapters: [Chapter],
        scriptTitle: String? = nil,
        scriptAuthor: String? = nil
    ) -> (author: String?, title: String?) {
        // Precedence: CLI flags > script/config metadata > epub metadata
        var resolvedAuthor = author ?? scriptAuthor
        var resolvedTitle = title ?? scriptTitle

        // Try extracting from epub
        if resolvedAuthor == nil || resolvedTitle == nil {
            for input in inputs {
                let ext = URL(fileURLWithPath: input).pathExtension.lowercased()
                if ext == "epub", let result = try? EpubParser.parse(input) {
                    if resolvedTitle == nil { resolvedTitle = result.metadata.title }
                    if resolvedAuthor == nil { resolvedAuthor = result.metadata.author }
                    break
                }
            }
        }

        // Interactive prompts if TTY (unless --non-interactive)
        let isTTY = isatty(FileHandle.standardInput.fileDescriptor) != 0
        if !nonInteractive && (isTTY || interactive) {
            if let defaultTitle = resolvedTitle {
                fputs("Enter title [\(defaultTitle)]: ", stderr)
            } else {
                fputs("Enter title (optional): ", stderr)
            }
            if let input = readLine(), !input.isEmpty {
                resolvedTitle = input
            }

            if let defaultAuthor = resolvedAuthor {
                fputs("Enter author [\(defaultAuthor)]: ", stderr)
            } else {
                fputs("Enter author (optional): ", stderr)
            }
            if let input = readLine(), !input.isEmpty {
                resolvedAuthor = input
            }
        }

        return (resolvedAuthor, resolvedTitle)
    }

    // MARK: - Format resolution

    private func resolveFormat(multiChapter: Bool) -> String {
        if let format { return format.lowercased() }
        // Infer from output extension if specified
        if let output {
            let ext = URL(fileURLWithPath: output).pathExtension.lowercased()
            if ["m4a", "mp3", "m4b"].contains(ext) { return ext }
        }
        return multiChapter ? "m4b" : "m4a"
    }

    // MARK: - Helpers

    private func resolveOutputPath(for input: String, format: String) -> String {
        if let output { return output }
        let url = URL(fileURLWithPath: input)
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent().path
        return "\(dir)/\(base).\(format)"
    }

    private func resolveAudiobookOutputPath(format: String) -> String {
        if let output { return output }
        let firstInput = URL(fileURLWithPath: inputs[0])
        let base = firstInput.deletingPathExtension().lastPathComponent
        let dir = firstInput.deletingLastPathComponent().path
        return "\(dir)/\(base).\(format)"
    }

    private func nextBackupPath(for path: String) -> String {
        let bak = "\(path).bak"
        if !FileManager.default.fileExists(atPath: bak) { return bak }
        var n = 1
        while FileManager.default.fileExists(atPath: "\(path).\(n).bak") { n += 1 }
        return "\(path).\(n).bak"
    }

    private func resolveVoice(engine: YapperEngine, voiceName: String?) throws -> Voice {
        if let voiceName {
            guard let v = engine.voiceRegistry.voices.first(where: { $0.name == voiceName }) else {
                let available = engine.voiceRegistry.voices.prefix(5).map(\.name).joined(separator: ", ")
                throw ValidationError("Voice '\(voiceName)' not found. Available: \(available)...")
            }
            return v
        }
        return engine.voiceRegistry.voices.first { $0.name == "af_heart" }
            ?? engine.voiceRegistry.voices[0]
    }

    // MARK: - Prose preprocessing diagnostics

    private func printPreprocessingDiagnostics(_ result: ProsePreprocessResult) {
        guard !result.diagnostics.isEmpty || !result.sectionBreaks.isEmpty else { return }

        print("  Preprocessing:")
        if !result.sectionBreaks.isEmpty {
            let lines = result.sectionBreaks.map { "\($0.lineIndex):\($0.pause.rawValue)" }
                .joined(separator: ", ")
            print("    Section breaks: \(lines)")
        }
        let diagnosticsByKind = Dictionary(grouping: result.diagnostics, by: \.kind)
        for kind in ProsePreprocessDiagnosticKind.allCases {
            guard let diagnostics = diagnosticsByKind[kind], !diagnostics.isEmpty else { continue }
            let lines = diagnostics.compactMap(\.lineIndex).map(String.init).joined(separator: ", ")
            let suffix = lines.isEmpty ? "" : " on line(s) \(lines)"
            print("    \(kind.rawValue): \(diagnostics.count) change(s)\(suffix)")
        }
    }

    // MARK: - Track number extraction

    /// Extract track numbers from input filenames when they form a consecutive
    /// sequence (starting from 0 or 1, incrementing by 1, allowing zero-padding).
    /// Returns an array of track numbers (1-based for metadata), or positional
    /// fallback (1, 2, 3, ...) when no valid sequence is detected.
    private func extractTrackNumbers(from inputs: [String]) -> [Int] {
        let filenames = inputs.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }

        // Extract the first integer from each filename
        let regex = try? NSRegularExpression(pattern: #"(\d+)"#)
        let extracted: [Int?] = filenames.map { name in
            guard let regex,
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let range = Range(match.range(at: 1), in: name) else {
                return nil
            }
            return Int(name[range])
        }

        // Check if all filenames have integers
        let allHaveIntegers = extracted.allSatisfy { $0 != nil }
        guard allHaveIntegers, let numbers = extracted as? [Int] else {
            // Positional fallback
            return Array(1...inputs.count)
        }

        // Check if they form a consecutive sequence starting from 0 or 1
        let sorted = numbers.sorted()
        let startsCorrectly = sorted.first == 0 || sorted.first == 1
        let isConsecutive = zip(sorted, sorted.dropFirst()).allSatisfy { $1 - $0 == 1 }

        if startsCorrectly && isConsecutive {
            // Use the extracted numbers but shift 0-based sequences to 1-based
            // for metadata (track 0 is not meaningful in ID3/MP4 tags)
            if sorted.first == 0 {
                return numbers.map { $0 + 1 }
            }
            return numbers
        }

        // Non-consecutive or doesn't start from 0/1 → positional fallback
        return Array(1...inputs.count)
    }

    // MARK: - FFmpeg encoding

    private func encodeWithFFmpeg(input: String, output: String, format: String) throws {
        try encodeWithFFmpeg(input: input, output: output, format: format,
                            author: self.author, title: self.title,
                            trackNumber: nil, trackTotal: nil, trackTitle: nil)
    }

    private func encodeWithFFmpeg(
        input: String,
        output: String,
        format: String,
        author: String?,
        title: String?,
        trackNumber: Int?,
        trackTotal: Int?,
        trackTitle: String?
    ) throws {
        let ffmpegPath = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let ffmpeg = ffmpegPath else {
            throw ValidationError("ffmpeg not found. Install via: brew install ffmpeg")
        }

        var args = ["-y", "-i", input]
        if format == "mp3" {
            args += ["-c:a", "libmp3lame", "-b:a", "128k"]
        } else {
            args += ["-c:a", "aac", "-b:a", "64k"]
        }

        if let author {
            args += ["-metadata", "artist=\(author)", "-metadata", "album_artist=\(author)"]
        }
        if let title {
            args += ["-metadata", "album=\(title)"]
        }
        if let trackNumber {
            let trackStr = trackTotal != nil ? "\(trackNumber)/\(trackTotal!)" : "\(trackNumber)"
            args += ["-metadata", "track=\(trackStr)"]
        }
        if let trackTitle {
            args += ["-metadata", "title=\(trackTitle)"]
        }

        args.append(output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ValidationError("ffmpeg exited with status \(process.terminationStatus)")
        }
    }

    private func assembleSingleFile(
        chapterInfo: [(title: String, aacPath: String, duration: Double)],
        output: String,
        format: String,
        author: String?,
        title: String?
    ) throws {
        // Simple concatenation for MP3/M4A (no chapter markers)
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first { FileManager.default.fileExists(atPath: $0) }!

        let tmpConcat = FileManager.default.temporaryDirectory
            .appendingPathComponent("concat_\(UUID().uuidString).txt")
        let content = chapterInfo.map { "file '\($0.aacPath)'" }.joined(separator: "\n")
        try content.write(to: tmpConcat, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpConcat) }

        var args = ["-y", "-f", "concat", "-safe", "0", "-i", tmpConcat.path]

        if format == "mp3" {
            args += ["-c:a", "libmp3lame", "-b:a", "128k"]
        } else {
            args += ["-c", "copy"]
        }

        if let author { args += ["-metadata", "artist=\(author)"] }
        if let title { args += ["-metadata", "album=\(title)"] }
        args.append(output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - Script mode

    /// Detect and parse a script file. Returns nil for prose files.
    private func detectAndParseScript() throws -> ScriptDocument? {
        guard inputs.count == 1 else { return nil }
        let inputPath = inputs[0]

        // Load config from --script-config flag or auto-discover script.yaml
        var config: ScriptConfig?
        if let configPath = scriptConfig {
            config = try ScriptConfig.load(from: configPath)
        } else {
            let dir = URL(fileURLWithPath: inputPath).deletingLastPathComponent().path
            let autoPath = "\(dir)/script.yaml"
            if FileManager.default.fileExists(atPath: autoPath) {
                config = try ScriptConfig.load(from: autoPath)
            }
        }

        // If no config and no --script-config flag, only parse if file has script patterns
        return try ScriptParser.parse(filePath: inputPath, config: config)
    }

    /// Print dry-run output for script mode.
    private func printScriptDryRun(_ script: ScriptDocument) throws {
        let registry = try VoiceRegistry(voicesPath: defaultVoicesPath())
        let config = try loadScriptConfig()
        let (charVoices, narrator) = VoiceAssigner.assign(
            characters: script.characters,
            config: config,
            registry: registry,
            narratorVoiceName: config?.narratorVoice
        )

        let readStage = config?.resolvedRenderStageDirections ?? true
        let renderIntro = config?.resolvedRenderFrontmatter ?? true
        let renderFootnotes = config?.resolvedRenderFootnotes ?? true
        let dryRunSubs = config?.speechSubstitution ?? [:]
        let knownChars = Set(script.characters)

        // Resolve intro voice
        let introVoiceName: String
        if let spec = config?.introVoice {
            if spec.contains("_"), let v = registry.voices.first(where: { $0.name == spec }) {
                introVoiceName = v.name
            } else if let filter = VoiceAssigner.parseFilterPublic(spec),
                      let v = registry.list(filter: filter).first {
                introVoiceName = v.name
            } else {
                introVoiceName = narrator.name
            }
        } else {
            introVoiceName = narrator.name
        }

        print("Script mode: \(script.title ?? "Untitled")")
        if let subtitle = script.subtitle { print("  \(subtitle)") }
        if let author = script.author { print("  Author: \(author)") }
        print("")
        print("Cast:")
        for char in script.characters {
            let voiceName = charVoices[char]?.name ?? "unassigned"
            print("  \(char): \(voiceName)")
        }
        print("  Narrator (stage directions): \(narrator.name)")
        if renderIntro {
            print("  Introduction: \(introVoiceName)")
        }
        print("")

        // Preamble preview
        if renderIntro {
            print("Introduction:")
            if let title = script.title { print("    \(title)") }
            if let subtitle = script.subtitle { print("    \(subtitle)") }
            if let author = script.author { print("    by \(author)") }
            for desc in script.characterDescriptions {
                print("    \(desc.name): \(desc.description)")
            }
            if let outline = script.outline {
                let preview = outline.prefix(80)
                print("    \(preview)\(outline.count > 80 ? "..." : "")")
            }
            for line in script.preamble.prefix(3) {
                let preview = line.prefix(80)
                print("    \(preview)\(line.count > 80 ? "..." : "")")
            }
            print("")
        }

        print("Scenes: \(script.scenes.count)")
        for (i, scene) in script.scenes.enumerated() {
            print("  [\(i + 1)/\(script.scenes.count)] \(scene.title)")
            for entry in scene.entries.prefix(5) {
                switch entry.type {
                case .dialogue(let char):
                    let voiceName = charVoices[char]?.name ?? "?"
                    var displayText = entry.text
                    if renderFootnotes || !script.footnotes.isEmpty {
                        let (stripped, _) = ScriptParser.stripFootnoteReferences(displayText)
                        displayText = stripped
                    }
                    displayText = ScriptConfig.applySubstitutions(displayText, substitutions: dryRunSubs)
                    let preview = displayText.prefix(60)
                    print("    \(char) (\(voiceName)): \(preview)\(displayText.count > 60 ? "..." : "")")
                case .stageDirection:
                    if readStage {
                        var displayText = ScriptParser.titleCaseCharacterNames(
                            in: entry.text, knownCharacters: knownChars
                        )
                        if renderFootnotes || !script.footnotes.isEmpty {
                            let (stripped, _) = ScriptParser.stripFootnoteReferences(displayText)
                            displayText = stripped
                        }
                        displayText = ScriptConfig.applySubstitutions(displayText, substitutions: dryRunSubs)
                        let preview = displayText.prefix(60)
                        print("    [stage] (\(narrator.name)): \(preview)\(displayText.count > 60 ? "..." : "")")
                    }
                case .transition:
                    let renderTransitions = config?.resolvedRenderTransitions ?? true
                    if renderTransitions {
                        var displayText = entry.text
                        displayText = ScriptConfig.applySubstitutions(displayText, substitutions: dryRunSubs)
                        let preview = displayText.prefix(60)
                        print("    [transition] (\(narrator.name)): \(preview)\(displayText.count > 60 ? "..." : "")")
                    }
                }
            }
            if scene.entries.count > 5 {
                print("    ... and \(scene.entries.count - 5) more entries")
            }
        }

        // Footnotes summary (only when rendering is enabled)
        if renderFootnotes && !script.footnotes.isEmpty {
            print("")
            print("Footnotes: \(script.footnotes.count)")
            for (name, definition) in script.footnotes {
                let preview = definition.prefix(60)
                print("    [\(name)] \(preview)\(definition.count > 60 ? "..." : "")")
            }
        }

        print("")
        print("(dry run — no synthesis performed)")
    }

    /// Run script mode: synthesise each dialogue turn with the assigned voice.
    ///
    /// Uses multi-process concurrent synthesis by default (3 workers). Each
    /// worker synthesises a single line to a WAV file; the main process trims
    /// leading/trailing silence, inserts configurable gaps, and assembles the
    /// scene audio into an M4B.
    private func runScriptMode(engine: YapperEngine, script: ScriptDocument) throws {
        let config = try loadScriptConfig()
        let (charVoices, narrator) = VoiceAssigner.assign(
            characters: script.characters,
            config: config,
            registry: engine.voiceRegistry,
            narratorVoiceName: config?.narratorVoice
        )

        let readStage = config?.resolvedRenderStageDirections ?? true
        let knownChars = Set(script.characters)

        // Configurable gaps (seconds of silence after each entry type)
        let gapDialogue = config?.gapAfterDialogue ?? 0.3
        let gapStageDirection = config?.gapAfterStageDirection ?? 0.5
        let gapScene = config?.gapAfterScene ?? 1.0

        // Configurable per-type speed (multiplied with --speed CLI flag)
        let dialogueSpeed = (config?.dialogueSpeed ?? 1.0) * speed
        let stageDirectionSpeed = (config?.stageDirectionSpeed ?? 1.0) * speed

        // Thread count: CLI flag > YAML > default 3
        let threadCount = threads ?? config?.threads ?? 3

        let resolvedTitle = title ?? config?.title ?? script.title
        let resolvedAuthor = author ?? config?.author ?? script.author

        // Resolve metadata interactively if needed
        let finalTitle: String?
        let finalAuthor: String?
        if !nonInteractive {
            let chapters = script.scenes.map { Chapter(title: $0.title, text: "") }
            let (a, t) = resolveMetadata(
                chapters: chapters,
                scriptTitle: resolvedTitle,
                scriptAuthor: resolvedAuthor
            )
            finalAuthor = a ?? resolvedAuthor
            finalTitle = t ?? resolvedTitle
        } else {
            finalAuthor = resolvedAuthor
            finalTitle = resolvedTitle
        }

        let outputPath = output ?? {
            let url = URL(fileURLWithPath: inputs[0])
            let base = url.deletingPathExtension().lastPathComponent
            let dir = url.deletingLastPathComponent().path
            return "\(dir)/\(base).m4b"
        }()

        if FileManager.default.fileExists(atPath: outputPath) {
            let backupPath = nextBackupPath(for: outputPath)
            try FileManager.default.moveItem(atPath: outputPath, toPath: backupPath)
            if !quiet { fputs("Backed up existing \(outputPath) to \(backupPath)\n", stderr) }
        }

        let renderIntro = config?.resolvedRenderFrontmatter ?? true
        let renderFootnotes = config?.resolvedRenderFootnotes ?? true
        let substitutions = config?.speechSubstitution ?? [:]

        if !quiet {
            fputs("Script mode: \(script.title ?? "Untitled")\n", stderr)
            fputs("Cast: \(script.characters.map { "\($0)=\(charVoices[$0]?.name ?? "?")" }.joined(separator: ", "))\n", stderr)
            fputs("Narrator: \(narrator.name)\n", stderr)
            if threadCount > 1 {
                fputs("Threads: \(threadCount)\n", stderr)
            }
            if !substitutions.isEmpty {
                let preview = substitutions.prefix(5).map { "\($0.key)\u{2192}\($0.value)" }.joined(separator: ", ")
                let suffix = substitutions.count > 5 ? ", ..." : ""
                fputs("Substitutions: \(substitutions.count) (\(preview)\(suffix))\n", stderr)
            }
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_script_\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Resolve intro voice
        let introVoice: Voice
        if let spec = config?.introVoice {
            if spec.contains("_"), let v = engine.voiceRegistry.voices.first(where: { $0.name == spec }) {
                introVoice = v
            } else if let filter = VoiceAssigner.parseFilterPublic(spec),
                      let v = engine.voiceRegistry.list(filter: filter).first {
                introVoice = v
            } else {
                introVoice = narrator
            }
        } else {
            introVoice = narrator
        }

        var chapterInfo: [(title: String, aacPath: String, duration: Double)] = []

        // Synthesise preamble chapter (introduction)
        if renderIntro {
            var preambleText: [String] = []

            // Title, subtitle, and author announcement
            if let t = finalTitle { preambleText.append(t) }
            let resolvedSubtitle = config?.subtitle ?? script.subtitle
            if let s = resolvedSubtitle { preambleText.append(s) }
            if let a = finalAuthor { preambleText.append("by \(a)") }

            // Character descriptions
            for desc in script.characterDescriptions {
                preambleText.append("\(desc.name): \(desc.description)")
            }

            // Outline
            if let outline = script.outline {
                preambleText.append(outline)
            }

            // Other preamble content
            preambleText.append(contentsOf: script.preamble)

            if !preambleText.isEmpty {
                if !quiet { fputs("Synthesising introduction...\n", stderr) }
                let introText = applySubs(preambleText.joined(separator: "\n\n"))
                let result = try engine.synthesize(
                    text: introText, voice: introVoice, speed: speed
                )
                let introWavPath = tmpDir.appendingPathComponent("intro.wav")
                try writeWav(samples: result.samples, sampleRate: 24000, to: introWavPath)
                let introAacPath = tmpDir.appendingPathComponent("intro.aac").path
                try AudiobookAssembler.encodeAAC(wavPath: introWavPath.path, output: introAacPath)
                try? FileManager.default.removeItem(at: introWavPath)
                let introDuration = Double(result.samples.count) / 24000.0
                chapterInfo.append((
                    title: finalTitle ?? "Introduction",
                    aacPath: introAacPath,
                    duration: introDuration
                ))
                if !quiet {
                    fputs("  Introduction (\(String(format: "%.1f", introDuration))s)\n", stderr)
                }
            }
        }

        // Apply speech substitutions to text before synthesis
        func applySubs(_ text: String) -> String {
            guard !substitutions.isEmpty else { return text }
            var result = text
            for (find, replace) in substitutions {
                result = result.replacingOccurrences(of: find, with: replace)
            }
            return result
        }

        // Build work items for all scenes
        struct WorkItem {
            let sceneIdx: Int
            let entryIdx: Int
            let text: String
            let voiceName: String
            let entrySpeed: Float
            let gap: Double
            let label: String
        }

        for (sceneIdx, scene) in script.scenes.enumerated() {
            if !quiet {
                fputs("[\(sceneIdx + 1)/\(script.scenes.count)] \(scene.title)\n", stderr)
            }

            var workItems: [WorkItem] = []
            // Use a sub-index for footnote aside entries to avoid index collisions
            var nextSubIdx = scene.entries.count

            for (entryIdx, entry) in scene.entries.enumerated() {
                switch entry.type {
                case .dialogue(let char):
                    guard let v = charVoices[char] else { continue }
                    var text = entry.text

                    // Strip footnote references and optionally insert narrator asides
                    let (stripped, fnNames) = ScriptParser.stripFootnoteReferences(text)
                    text = applySubs(stripped)

                    workItems.append(WorkItem(
                        sceneIdx: sceneIdx, entryIdx: entryIdx,
                        text: text, voiceName: v.name,
                        entrySpeed: dialogueSpeed, gap: gapDialogue,
                        label: "\(char)"
                    ))

                    // Insert footnote definition as narrator aside after the dialogue line
                    if renderFootnotes {
                        for fnName in fnNames {
                            if let definition = script.footnotes[fnName] {
                                workItems.append(WorkItem(
                                    sceneIdx: sceneIdx, entryIdx: nextSubIdx,
                                    text: definition, voiceName: narrator.name,
                                    entrySpeed: stageDirectionSpeed, gap: gapStageDirection,
                                    label: "[footnote]"
                                ))
                                nextSubIdx += 1
                            }
                        }
                    }

                case .stageDirection:
                    guard readStage else { continue }
                    var titleCasedText = ScriptParser.titleCaseCharacterNames(
                        in: entry.text, knownCharacters: knownChars
                    )

                    // Strip footnote references from stage directions too
                    let (stripped, fnNames) = ScriptParser.stripFootnoteReferences(titleCasedText)
                    titleCasedText = applySubs(stripped)

                    workItems.append(WorkItem(
                        sceneIdx: sceneIdx, entryIdx: entryIdx,
                        text: titleCasedText, voiceName: narrator.name,
                        entrySpeed: stageDirectionSpeed, gap: gapStageDirection,
                        label: "[stage]"
                    ))

                    if renderFootnotes {
                        for fnName in fnNames {
                            if let definition = script.footnotes[fnName] {
                                workItems.append(WorkItem(
                                    sceneIdx: sceneIdx, entryIdx: nextSubIdx,
                                    text: definition, voiceName: narrator.name,
                                    entrySpeed: stageDirectionSpeed, gap: gapStageDirection,
                                    label: "[footnote]"
                                ))
                                nextSubIdx += 1
                            }
                        }
                    }

                case .transition:
                    let renderTransitions = config?.resolvedRenderTransitions ?? true
                    guard renderTransitions else { continue }
                    let transText = applySubs(entry.text)
                    workItems.append(WorkItem(
                        sceneIdx: sceneIdx, entryIdx: entryIdx,
                        text: transText, voiceName: narrator.name,
                        entrySpeed: stageDirectionSpeed, gap: gapStageDirection,
                        label: "[transition]"
                    ))
                }
            }

            guard !workItems.isEmpty else { continue }

            // Synthesise all entries (concurrent or sequential)
            let entryWavDir = tmpDir.appendingPathComponent("scene\(sceneIdx + 1)")
            try FileManager.default.createDirectory(at: entryWavDir, withIntermediateDirectories: true)

            let synthItems = workItems.map { item in
                (idx: item.entryIdx, text: item.text, voiceName: item.voiceName, speed: item.entrySpeed)
            }

            if threadCount > 1 {
                try synthesiseConcurrentProcesses(
                    texts: synthItems, wavDir: entryWavDir, threadCount: threadCount
                )
            } else {
                try synthesiseSequentialInProcess(
                    texts: synthItems, wavDir: entryWavDir, engine: engine
                )
            }

            // Assemble scene from trimmed entry WAVs with gaps
            var sceneSamples: [Float] = []
            for (i, item) in workItems.enumerated() {
                let wavPath = entryWavDir.appendingPathComponent("entry_\(String(format: "%03d", item.entryIdx)).wav").path
                let trimmed = AudioTrimmer.trim(wavPath: wavPath)
                if !sceneSamples.isEmpty {
                    let gapSamples = [Float](repeating: 0, count: Int(item.gap * 24000))
                    sceneSamples.append(contentsOf: gapSamples)
                }
                sceneSamples.append(contentsOf: trimmed)

                if !quiet && i % 5 == 0 {
                    fputs("\r  Assembling: \(i + 1)/\(workItems.count)", stderr)
                }
            }
            if !quiet { fputs("\r  Assembling: \(workItems.count)/\(workItems.count)\n", stderr) }

            // Add scene-end gap (except for last scene)
            if sceneIdx < script.scenes.count - 1 {
                let sceneGapSamples = [Float](repeating: 0, count: Int(gapScene * 24000))
                sceneSamples.append(contentsOf: sceneGapSamples)
            }

            guard !sceneSamples.isEmpty else { continue }

            let sceneWavPath = tmpDir.appendingPathComponent("scene\(sceneIdx + 1).wav")
            try writeWav(samples: sceneSamples, sampleRate: 24000, to: sceneWavPath)

            let aacPath = tmpDir.appendingPathComponent("scene\(sceneIdx + 1).aac").path
            try AudiobookAssembler.encodeAAC(wavPath: sceneWavPath.path, output: aacPath)
            try? FileManager.default.removeItem(at: sceneWavPath)

            let duration = Double(sceneSamples.count) / 24000.0
            chapterInfo.append((title: scene.title, aacPath: aacPath, duration: duration))

            if !quiet {
                fputs("  \(scene.title) (\(String(format: "%.1f", duration))s)\n", stderr)
            }
        }

        // Assemble M4B
        try AudiobookAssembler.assembleM4B(
            chapters: chapterInfo,
            output: outputPath,
            title: finalTitle,
            author: finalAuthor,
            coverArtPath: nil
        )

        let totalDuration = chapterInfo.reduce(0.0) { $0 + $1.duration }
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        if !quiet {
            fputs("Created \(outputPath) (\(minutes):\(String(format: "%02d", seconds)))\n", stderr)
        }
    }

    /// Synthesise work items sequentially in-process (--threads 1).
    private func synthesiseSequentialInProcess(
        texts: [(idx: Int, text: String, voiceName: String, speed: Float)],
        wavDir: URL,
        engine: YapperEngine
    ) throws {
        for item in texts {
            guard let voice = engine.voiceRegistry.voices.first(where: { $0.name == item.voiceName }) else {
                continue
            }
            let result = try engine.synthesize(text: item.text, voice: voice, speed: item.speed)
            let wavPath = wavDir.appendingPathComponent("entry_\(String(format: "%03d", item.idx)).wav")
            try writeWav(samples: result.samples, sampleRate: 24000, to: wavPath)
        }
    }

    /// Synthesise work items using multiple concurrent worker processes.
    private func synthesiseConcurrentProcesses(
        texts: [(idx: Int, text: String, voiceName: String, speed: Float)],
        wavDir: URL,
        threadCount: Int
    ) throws {
        let yapperPath = CommandLine.arguments[0]
        let semaphore = DispatchSemaphore(value: threadCount)
        let group = DispatchGroup()
        let lock = NSLock()
        var failures: [String] = []

        for item in texts {
            semaphore.wait()
            group.enter()

            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    semaphore.signal()
                    group.leave()
                }

                let wavPath = wavDir.appendingPathComponent(
                    "entry_\(String(format: "%03d", item.idx)).wav"
                ).path

                let process = Process()
                process.executableURL = URL(fileURLWithPath: yapperPath)
                process.arguments = [
                    "convert", "dummy",
                    "--worker-text", item.text,
                    "--worker-voice", item.voiceName,
                    "--worker-output", wavPath,
                    "--speed", String(item.speed)
                ]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        lock.lock()
                        failures.append("Entry \(item.idx): exit code \(process.terminationStatus)")
                        lock.unlock()
                    }
                } catch {
                    lock.lock()
                    failures.append("Entry \(item.idx): \(error)")
                    lock.unlock()
                }
            }
        }

        group.wait()

        if !failures.isEmpty {
            let failureList = failures.joined(separator: "\n  ")
            fputs("Worker failures:\n  \(failureList)\n", stderr)
            throw ValidationError("Script synthesis failed: \(failures.count) worker(s) failed")
        }
    }

    /// Worker mode: synthesise a single line and write to WAV.
    private func runWorker(text: String, voiceName: String, outputPath: String) throws {
        let engine = try YapperEngine(
            modelPath: defaultModelPath(),
            voicesPath: defaultVoicesPath()
        )
        guard let voice = engine.voiceRegistry.voices.first(where: { $0.name == voiceName }) else {
            throw ValidationError("Voice \(voiceName) not found")
        }
        let result = try engine.synthesize(text: text, voice: voice, speed: speed)
        try writeWav(samples: result.samples, sampleRate: 24000, to: URL(fileURLWithPath: outputPath))
    }

    /// Load script config from --script-config flag or auto-discover.
    private func loadScriptConfig() throws -> ScriptConfig? {
        let inputDir = inputs.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let merged = ScriptConfig.loadMerged(explicitPath: scriptConfig, inputDir: inputDir)
        // Return nil if no config was found at any level
        if merged.title == nil && merged.author == nil && merged.subtitle == nil
            && merged.characterVoices == nil && merged.narratorVoice == nil
            && merged.speechSubstitution == nil && merged.autoAssignVoices == nil
            && merged.render == nil && merged.renderStageDirections == nil
            && merged.renderIntro == nil && merged.renderFootnotes == nil
            && merged.introVoice == nil && merged.threads == nil
            && merged.dialogueSpeed == nil && merged.stageDirectionSpeed == nil
            && merged.gapAfterDialogue == nil && merged.gapAfterStageDirection == nil
            && merged.gapAfterScene == nil {
            return nil
        }
        return merged
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
