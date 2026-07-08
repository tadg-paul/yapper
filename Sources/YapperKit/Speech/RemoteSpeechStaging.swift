// ABOUTME: Persists remote synthesis plans and completed chunk artefacts for paid-call resume.
// ABOUTME: Reuses matching staged chunks when transformed text and engine settings are unchanged.

import Foundation

public struct RemoteSpeechStageRecord: Codable, Equatable, Sendable {
    public let stableHash: String
    public let chapterIndex: Int
    public let chunkIndex: Int
    public let audioFile: String
    public let completedAt: Date

    public init(
        stableHash: String,
        chapterIndex: Int,
        chunkIndex: Int,
        audioFile: String,
        completedAt: Date
    ) {
        self.stableHash = stableHash
        self.chapterIndex = chapterIndex
        self.chunkIndex = chunkIndex
        self.audioFile = audioFile
        self.completedAt = completedAt
    }
}

public struct RemoteSpeechStageManifest: Codable, Equatable, Sendable {
    public var engineKind: SpeechEngineKind
    public var settingsSignature: String
    public var chunks: [PreparedSpeechChunk]
    public var completed: [RemoteSpeechStageRecord]

    public init(
        engineKind: SpeechEngineKind,
        settingsSignature: String,
        chunks: [PreparedSpeechChunk],
        completed: [RemoteSpeechStageRecord]
    ) {
        self.engineKind = engineKind
        self.settingsSignature = settingsSignature
        self.chunks = chunks
        self.completed = completed
    }
}

public struct RemoteSpeechStaging: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var manifestURL: URL {
        directory.appendingPathComponent("plan.json")
    }

    public func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func loadReusableManifest(
        for plan: SpeechConversionPlan,
        settingsSignature: String
    ) -> RemoteSpeechStageManifest? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(RemoteSpeechStageManifest.self, from: data),
              manifest.engineKind == plan.engineKind,
              manifest.settingsSignature == settingsSignature,
              manifest.chunks.map(\.stableHash) == plan.chunks.map(\.stableHash) else {
            return nil
        }
        return manifest
    }

    public func writeManifest(_ manifest: RemoteSpeechStageManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    public func existingFile(for record: RemoteSpeechStageRecord) -> URL? {
        let file = directory.appendingPathComponent(record.audioFile)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}
