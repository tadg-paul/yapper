// ABOUTME: Assembles synthesised chapter audio into M4B audiobooks with chapter markers.
// ABOUTME: Handles AAC encoding, concatenation, ffmetadata, and cover art embedding.

import Foundation

/// Assembles individual chapter audio files into an M4B audiobook with chapter markers.
public struct AudiobookAssembler {

    /// Assemble chapters into an M4B file.
    ///
    /// - Parameters:
    ///   - chapterFiles: ordered array of (title, path to AAC file, duration in seconds)
    ///   - output: output M4B file path
    ///   - metadata: title, author, cover art path
    /// - Throws: if ffmpeg fails or files are missing
    public static func assembleM4B(
        chapters: [(title: String, aacPath: String, duration: Double)],
        output: String,
        title: String?,
        author: String?,
        coverArtPath: String?
    ) throws {
#if os(macOS)
        let ffmpeg = try findFFmpeg()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_m4b_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Step 1: Create concat file
        let concatFile = tmpDir.appendingPathComponent("concat.txt")
        let concatContent = chapters.map { "file '\($0.aacPath)'" }.joined(separator: "\n")
        try concatContent.write(to: concatFile, atomically: true, encoding: .utf8)

        // Step 2: Concatenate
        let combinedPath = tmpDir.appendingPathComponent("combined.aac").path
        try runFFmpeg(ffmpeg, args: [
            "-y", "-f", "concat", "-safe", "0",
            "-i", concatFile.path,
            "-c", "copy",
            combinedPath
        ])

        // Step 3: Create ffmetadata
        let metadataFile = tmpDir.appendingPathComponent("metadata.txt")
        var meta = ";FFMETADATA1\n"
        if let title {
            meta += "title=\(title)\n"
            meta += "album=\(title)\n"
        }
        if let author {
            meta += "artist=\(author)\n"
            meta += "album_artist=\(author)\n"
        }
        meta += "\n"

        var startMs = 0
        for chapter in chapters {
            let endMs = startMs + Int(chapter.duration * 1000)
            meta += "[CHAPTER]\nTIMEBASE=1/1000\nSTART=\(startMs)\nEND=\(endMs)\ntitle=\(chapter.title)\n\n"
            startMs = endMs
        }
        try meta.write(to: metadataFile, atomically: true, encoding: .utf8)

        // Step 4: Mux with chapters and metadata
        var muxArgs = ["-y", "-i", combinedPath, "-i", metadataFile.path]

        // Add cover art if available
        if let coverPath = coverArtPath,
           FileManager.default.fileExists(atPath: coverPath) {
            muxArgs += ["-i", coverPath, "-map", "0:a", "-map", "2:v"]
            muxArgs += ["-disposition:v:0", "attached_pic"]
        }

        muxArgs += ["-map_metadata", "1", "-c", "copy", output]

        try runFFmpeg(ffmpeg, args: muxArgs)
#else
        throw AudiobookError.unsupportedPlatform
#endif
    }

    /// Encode raw PCM samples to AAC via ffmpeg.
    ///
    /// - Parameters:
    ///   - samples: PCM float32 samples at sampleRate Hz
    ///   - sampleRate: sample rate
    ///   - output: output AAC file path
    public static func encodeAAC(
        wavPath: String,
        output: String
    ) throws {
#if os(macOS)
        let ffmpeg = try findFFmpeg()
        try runFFmpeg(ffmpeg, args: [
            "-y", "-i", wavPath,
            "-c:a", "aac", "-b:a", "64k",
            output
        ])
#else
        throw AudiobookError.unsupportedPlatform
#endif
    }

    /// Extract track number from filename.
    ///
    /// Matches the first contiguous digit sequence in the filename.
    /// e.g. "chapter-03-intro.txt" -> 3, "12_story.txt" -> 12
    public static func extractTrackNumber(from filename: String) -> Int? {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let pattern = "([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)),
              let range = Range(match.range(at: 1), in: base) else {
            return nil
        }
        return Int(base[range])
    }

    // MARK: - Helpers

    private static func findFFmpeg() throws -> String {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        guard let found = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw AudiobookError.missingFFmpeg
        }
        return found
    }

    private static func runFFmpeg(_ path: String, args: [String]) throws {
#if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        // All three stdio handles must be detached from the terminal. Without
        // standardInput = /dev/null, ffmpeg inherits the parent's stdin, which
        // can trigger SIGTTIN (stopped) if the terminal's process group has moved
        // on — this caused a deadlock where yapper waited for ffmpeg to exit and
        // ffmpeg was stopped waiting for terminal access it would never get.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AudiobookError.ffmpegFailed(status: process.terminationStatus)
        }
#else
        throw AudiobookError.unsupportedPlatform
#endif
    }
}

/// Errors from audiobook assembly.
public enum AudiobookError: Error, CustomStringConvertible {
    case missingFFmpeg
    case ffmpegFailed(status: Int32)
    case unsupportedPlatform

    public var description: String {
        switch self {
        case .missingFFmpeg:
            return "ffmpeg not found. Install via: brew install ffmpeg"
        case .ffmpegFailed(let status):
            return "ffmpeg exited with status \(status)"
        case .unsupportedPlatform:
            return "Audiobook assembly requires a macOS audio adapter supplied by the host application."
        }
    }
}
