// ABOUTME: Adapts Yapper, FAL, and OpenAI synthesis to the public speech-engine boundary.
// ABOUTME: Keeps provider planning, signatures, execution policy, and audio shape engine-owned.

import Foundation

public final class YapperSpeechEngine: SpeechEngine, @unchecked Sendable {
    public let id = SpeechEngineID.yapper
    public let capabilities = SpeechEngineCapabilities.yapper
    public let executionPolicy: SpeechExecutionPolicy

    private let engine: YapperEngine

    public init(engine: YapperEngine, concurrency: Int = 1) {
        self.engine = engine
        self.executionPolicy = SpeechExecutionPolicy(
            mode: concurrency > 1 ? .workerProcesses : .persistentSerial,
            maximumConcurrency: max(1, concurrency)
        )
    }

    public convenience init(modelPath: URL, voicesPath: URL, concurrency: Int = 1) throws {
        try self.init(
            engine: YapperEngine(modelPath: modelPath, voicesPath: voicesPath),
            concurrency: concurrency
        )
    }

    public func plan(_ utterance: SpeechUtterance) throws -> [PreparedSpeechChunk] {
        try BuiltInSpeechPlanning.plan(utterance, engineKind: .yapper, signature: "native-v1")
    }

    public func synthesisSignature(for chunk: PreparedSpeechChunk) throws -> SpeechSynthesisSignature {
        SpeechSynthesisSignature("yapper|native-v1|\(chunk.voiceID?.rawValue ?? "")")
    }

    public func synthesize(_ chunk: PreparedSpeechChunk) async throws -> SpeechSynthesisAsset {
        guard let voiceID = chunk.voiceID,
              let voice = engine.voiceRegistry.voices.first(where: { $0.name == voiceID.rawValue }) else {
            throw YapperError.synthesisError(
                message: "Voice '\(chunk.voiceID?.rawValue ?? "missing")' is unavailable for engine 'yapper'."
            )
        }
        let speed = try BuiltInSpeechPlanning.speed(from: chunk)
        return .pcm(try engine.synthesize(text: chunk.text, voice: voice, speed: Float(speed)))
    }
}

public struct FALSpeechEngine: SpeechEngine {
    public let id = SpeechEngineID.fal
    public let capabilities = SpeechEngineCapabilities.fal
    public let executionPolicy: SpeechExecutionPolicy

    private let settings: FALSpeechSettings
    private let credential: ResolvedSpeechCredential
    private let stagingDirectory: URL
    private let httpClient: SpeechHTTPClient

    public init(
        settings: FALSpeechSettings,
        credential: ResolvedSpeechCredential,
        stagingDirectory: URL,
        concurrency: Int = 3,
        httpClient: SpeechHTTPClient = URLSessionSpeechHTTPClient()
    ) {
        self.settings = settings
        self.credential = credential
        self.stagingDirectory = stagingDirectory
        self.httpClient = httpClient
        self.executionPolicy = SpeechExecutionPolicy(
            mode: .boundedConcurrent,
            maximumConcurrency: max(1, concurrency)
        )
    }

    public func plan(_ utterance: SpeechUtterance) throws -> [PreparedSpeechChunk] {
        try BuiltInSpeechPlanning.plan(utterance, engineKind: .fal, signature: settings.signature)
    }

    public func synthesisSignature(for chunk: PreparedSpeechChunk) throws -> SpeechSynthesisSignature {
        SpeechSynthesisSignature("fal|\(settings.signature)|\(chunk.voiceID?.rawValue ?? "")")
    }

    public func synthesize(_ chunk: PreparedSpeechChunk) async throws -> SpeechSynthesisAsset {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        var chunkSettings = settings
        chunkSettings.voice = chunk.voiceID?.rawValue ?? settings.voice
        chunkSettings.speed *= try BuiltInSpeechPlanning.speed(from: chunk)
        let client = FALSpeechClient(
            settings: chunkSettings,
            credential: credential,
            httpClient: httpClient
        )
        let file = try await client.synthesize(chunk, stagingDirectory: stagingDirectory)
        return .encodedAudio(
            file: file,
            format: chunkSettings.outputFormat,
            duration: nil,
            metadata: ["engine": id.rawValue, "voice": chunkSettings.voice]
        )
    }
}

public struct OpenAISpeechEngine: SpeechEngine {
    public let id = SpeechEngineID.openAI
    public let capabilities = SpeechEngineCapabilities.openAI
    public let executionPolicy: SpeechExecutionPolicy

    private let settings: OpenAISpeechSettings
    private let credential: ResolvedSpeechCredential
    private let stagingDirectory: URL
    private let httpClient: SpeechHTTPClient

    public init(
        settings: OpenAISpeechSettings,
        credential: ResolvedSpeechCredential,
        stagingDirectory: URL,
        concurrency: Int = 3,
        httpClient: SpeechHTTPClient = URLSessionSpeechHTTPClient()
    ) {
        self.settings = settings
        self.credential = credential
        self.stagingDirectory = stagingDirectory
        self.httpClient = httpClient
        self.executionPolicy = SpeechExecutionPolicy(
            mode: .boundedConcurrent,
            maximumConcurrency: max(1, concurrency)
        )
    }

    public func plan(_ utterance: SpeechUtterance) throws -> [PreparedSpeechChunk] {
        try BuiltInSpeechPlanning.plan(utterance, engineKind: .openAI, signature: settings.signature)
    }

    public func synthesisSignature(for chunk: PreparedSpeechChunk) throws -> SpeechSynthesisSignature {
        SpeechSynthesisSignature("openai|\(settings.signature)|\(chunk.voiceID?.rawValue ?? "")")
    }

    public func synthesize(_ chunk: PreparedSpeechChunk) async throws -> SpeechSynthesisAsset {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        var chunkSettings = settings
        chunkSettings.voice = chunk.voiceID?.rawValue ?? settings.voice
        chunkSettings.speed *= try BuiltInSpeechPlanning.speed(from: chunk)
        let client = OpenAISpeechClient(
            settings: chunkSettings,
            credential: credential,
            httpClient: httpClient
        )
        let file = try await client.synthesize(chunk, stagingDirectory: stagingDirectory)
        return .encodedAudio(
            file: file,
            format: chunkSettings.responseFormat,
            duration: nil,
            metadata: ["engine": id.rawValue, "voice": chunkSettings.voice]
        )
    }
}

private enum BuiltInSpeechPlanning {
    private struct Payload: Codable, Sendable {
        let speed: Double
    }

    static func plan(
        _ utterance: SpeechUtterance,
        engineKind: SpeechEngineKind,
        signature: String
    ) throws -> [PreparedSpeechChunk] {
        let source = SpeechSourceDocument(
            sourcePath: utterance.sourceID,
            chapterTitle: utterance.sourceID,
            text: utterance.text
        )
        let plan = SpeechPlanner.makePlan(
            sources: [source],
            engineKind: engineKind,
            engineSettingsSignature: "\(signature)|\(utterance.voice.rawValue)|\(utterance.speed)"
        )
        let payload = try EnginePreparedPayload(Payload(speed: utterance.speed), typeIdentifier: "speech-speed-v1")
        return plan.chunks.map { chunk in
            PreparedSpeechChunk(
                chapterIndex: chunk.chapterIndex,
                chapterTitle: chunk.chapterTitle,
                sourcePath: chunk.sourcePath,
                chunkIndex: chunk.chunkIndex,
                text: chunk.text,
                previousText: chunk.previousText ?? utterance.previousText,
                nextText: chunk.nextText ?? utterance.nextText,
                characterCount: chunk.characterCount,
                boundaryBefore: chunk.boundaryBefore,
                containsParagraphBreak: chunk.containsParagraphBreak,
                stableHash: chunk.stableHash,
                engineID: engineKind.id,
                voiceID: utterance.voice,
                semanticRole: utterance.role,
                enginePayload: payload
            )
        }
    }

    static func speed(from chunk: PreparedSpeechChunk) throws -> Double {
        guard let payload = chunk.enginePayload else { return 1 }
        return try payload.decode(Payload.self).speed
    }
}
