// ABOUTME: Defines extensible speech-engine contracts for local and API-backed synthesis.
// ABOUTME: Keeps engine identity, lifecycle, prepared work, and output independent of the CLI.

import CryptoKit
import Foundation

public struct SpeechEngineID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    public static let yapper: SpeechEngineID = "yapper"
    public static let fal: SpeechEngineID = "fal"
    public static let openAI: SpeechEngineID = "openai"
}

/// Compatibility identifier used by the existing provider planner.
/// New orchestration and registries use open `SpeechEngineID` values.
public enum SpeechEngineKind: String, Codable, CaseIterable, Sendable {
    case yapper
    case fal
    case openAI = "openai"
    case f5

    public var id: SpeechEngineID { SpeechEngineID(rawValue) }

    public var isRemote: Bool {
        switch self {
        case .fal, .openAI:
            return true
        case .yapper, .f5:
            return false
        }
    }
}

public enum SpeechEngineLocality: String, Codable, Sendable {
    case local
    case remote
}

public enum SpeechSynthesisAudioKind: String, Codable, Sendable {
    case pcm
    case encodedAudio = "encoded-audio"
}

public struct SpeechEngineCapabilities: Codable, Equatable, Sendable {
    public let engineID: SpeechEngineID
    public let locality: SpeechEngineLocality
    public let emittedAudioKind: SpeechSynthesisAudioKind
    public let requiresGenerationCredential: Bool
    public let supportsAccountReporting: Bool
    public let supportsReferenceAudio: Bool
    public let supportsStreaming: Bool
    public let supportsVoiceDiscovery: Bool
    public let supportsIPA: Bool
    public let licenceCategory: String?

    public var isRemote: Bool { locality == .remote }

    public init(
        engineID: SpeechEngineID,
        locality: SpeechEngineLocality,
        emittedAudioKind: SpeechSynthesisAudioKind,
        requiresGenerationCredential: Bool,
        supportsAccountReporting: Bool,
        supportsReferenceAudio: Bool,
        supportsStreaming: Bool,
        supportsVoiceDiscovery: Bool = false,
        supportsIPA: Bool = false,
        licenceCategory: String? = nil
    ) {
        self.engineID = engineID
        self.locality = locality
        self.emittedAudioKind = emittedAudioKind
        self.requiresGenerationCredential = requiresGenerationCredential
        self.supportsAccountReporting = supportsAccountReporting
        self.supportsReferenceAudio = supportsReferenceAudio
        self.supportsStreaming = supportsStreaming
        self.supportsVoiceDiscovery = supportsVoiceDiscovery
        self.supportsIPA = supportsIPA
        self.licenceCategory = licenceCategory
    }

    public init(
        engineKind: SpeechEngineKind,
        isRemote: Bool,
        emittedAudioKind: SpeechSynthesisAudioKind,
        requiresGenerationCredential: Bool,
        supportsAccountReporting: Bool,
        supportsReferenceAudio: Bool,
        supportsStreaming: Bool,
        licenceCategory: String? = nil
    ) {
        self.init(
            engineID: engineKind.id,
            locality: isRemote ? .remote : .local,
            emittedAudioKind: emittedAudioKind,
            requiresGenerationCredential: requiresGenerationCredential,
            supportsAccountReporting: supportsAccountReporting,
            supportsReferenceAudio: supportsReferenceAudio,
            supportsStreaming: supportsStreaming,
            supportsVoiceDiscovery: engineKind == .yapper,
            supportsIPA: engineKind == .yapper,
            licenceCategory: licenceCategory
        )
    }

    public static let yapper = SpeechEngineCapabilities(
        engineID: .yapper,
        locality: .local,
        emittedAudioKind: .pcm,
        requiresGenerationCredential: false,
        supportsAccountReporting: false,
        supportsReferenceAudio: false,
        supportsStreaming: true,
        supportsVoiceDiscovery: true,
        supportsIPA: true,
        licenceCategory: "Apache-2.0 weights"
    )

    public static let fal = SpeechEngineCapabilities(
        engineID: .fal,
        locality: .remote,
        emittedAudioKind: .encodedAudio,
        requiresGenerationCredential: true,
        supportsAccountReporting: true,
        supportsReferenceAudio: false,
        supportsStreaming: false,
        licenceCategory: "provider-managed"
    )

    public static func builtIn(for engineID: SpeechEngineID) -> SpeechEngineCapabilities? {
        switch engineID {
        case .yapper: return .yapper
        case .fal: return .fal
        case .openAI: return .openAI
        default: return nil
        }
    }

    public static let openAI = SpeechEngineCapabilities(
        engineID: .openAI,
        locality: .remote,
        emittedAudioKind: .encodedAudio,
        requiresGenerationCredential: true,
        supportsAccountReporting: true,
        supportsReferenceAudio: false,
        supportsStreaming: false,
        licenceCategory: "provider-managed"
    )
}

public enum SpeechSemanticRole: String, Codable, Equatable, Sendable {
    case narration
    case dialogue
    case introduction
    case stageDirection = "stage-direction"
    case transition
    case footnote
}

public struct SpeechVoiceID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

public struct SpeechUtterance: Codable, Equatable, Sendable {
    public let text: String
    public let sourceID: String
    public let role: SpeechSemanticRole
    public let voice: SpeechVoiceID
    public let speed: Double
    public let previousText: String?
    public let nextText: String?

    public init(
        text: String,
        sourceID: String,
        role: SpeechSemanticRole,
        voice: SpeechVoiceID,
        speed: Double = 1,
        previousText: String? = nil,
        nextText: String? = nil
    ) {
        self.text = text
        self.sourceID = sourceID
        self.role = role
        self.voice = voice
        self.speed = speed
        self.previousText = previousText
        self.nextText = nextText
    }
}

public struct EnginePreparedPayload: Codable, Equatable, Sendable {
    public let typeIdentifier: String
    private let data: Data

    public init<Value: Encodable & Sendable>(_ value: Value, typeIdentifier: String) throws {
        self.typeIdentifier = typeIdentifier
        self.data = try JSONEncoder().encode(value)
    }

    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }
}

public struct SpeechSynthesisSignature: RawRepresentable, Codable, Equatable, Sendable,
    ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct SpeechExecutionPolicy: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case persistentSerial = "persistent-serial"
        case boundedConcurrent = "bounded-concurrent"
        case workerProcesses = "worker-processes"
    }

    public let mode: Mode
    public let maximumConcurrency: Int

    public init(mode: Mode, maximumConcurrency: Int) {
        self.mode = mode
        self.maximumConcurrency = maximumConcurrency
    }

    public static let persistentSerial = SpeechExecutionPolicy(mode: .persistentSerial, maximumConcurrency: 1)
}

public protocol SpeechEngine: Sendable {
    var id: SpeechEngineID { get }
    var capabilities: SpeechEngineCapabilities { get }
    var executionPolicy: SpeechExecutionPolicy { get }
    func plan(_ utterance: SpeechUtterance) throws -> [PreparedSpeechChunk]
    func synthesisSignature(for chunk: PreparedSpeechChunk) throws -> SpeechSynthesisSignature
    func synthesize(_ chunk: PreparedSpeechChunk) async throws -> SpeechSynthesisAsset
}

public struct SpeechEngineDescriptor: Sendable {
    public let id: SpeechEngineID
    public let capabilities: SpeechEngineCapabilities
    private let factory: @Sendable () throws -> any SpeechEngine

    public init(
        id: SpeechEngineID,
        capabilities: SpeechEngineCapabilities,
        makeEngine: @escaping @Sendable () throws -> any SpeechEngine
    ) {
        self.id = id
        self.capabilities = capabilities
        self.factory = makeEngine
    }

    fileprivate func makeEngine() throws -> any SpeechEngine {
        try factory()
    }
}

public enum SpeechEngineRegistryError: Error, Equatable, CustomStringConvertible {
    case duplicateEngine(SpeechEngineID)
    case unknownEngine(requested: SpeechEngineID, registered: [SpeechEngineID])
    case mismatchedEngine(expected: SpeechEngineID, actual: SpeechEngineID)

    public var description: String {
        switch self {
        case .duplicateEngine(let id):
            return "Speech engine '\(id)' is already registered."
        case .unknownEngine(let requested, let registered):
            let available = registered.map(\.rawValue).joined(separator: ", ")
            return "Unsupported engine '\(requested)'. Available engines: \(available)."
        case .mismatchedEngine(let expected, let actual):
            return "Engine factory for '\(expected)' created engine '\(actual)'."
        }
    }
}

public struct SpeechEngineRegistry: Sendable {
    private var descriptors: [SpeechEngineID: SpeechEngineDescriptor] = [:]

    public init() {}

    public var registeredEngineIDs: [SpeechEngineID] {
        descriptors.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public mutating func register(_ descriptor: SpeechEngineDescriptor) {
        precondition(descriptors[descriptor.id] == nil, "Engine ID already registered: \(descriptor.id)")
        descriptors[descriptor.id] = descriptor
    }

    public func descriptor(for engineID: SpeechEngineID) -> SpeechEngineDescriptor? {
        descriptors[engineID]
    }

    public func makeSession(engineID: SpeechEngineID) throws -> SpeechEngineSession {
        guard let descriptor = descriptors[engineID] else {
            throw SpeechEngineRegistryError.unknownEngine(
                requested: engineID,
                registered: registeredEngineIDs
            )
        }
        let engine = try descriptor.makeEngine()
        guard engine.id == engineID else {
            throw SpeechEngineRegistryError.mismatchedEngine(expected: engineID, actual: engine.id)
        }
        return SpeechEngineSession(engine: engine)
    }
}

public struct SpeechEngineSession: Sendable {
    public let engine: any SpeechEngine

    public init(engine: any SpeechEngine) {
        self.engine = engine
    }

    public func synthesize(_ utterances: [SpeechUtterance]) async throws -> [SpeechSynthesisAsset] {
        var chunks: [PreparedSpeechChunk] = []
        for utterance in utterances {
            chunks.append(contentsOf: try engine.plan(utterance))
        }
        guard engine.executionPolicy.mode == .boundedConcurrent,
              engine.executionPolicy.maximumConcurrency > 1 else {
            var assets: [SpeechSynthesisAsset] = []
            for chunk in chunks {
                assets.append(try await engine.synthesize(chunk))
            }
            return assets
        }

        return try await synthesizeBounded(chunks)
    }

    private func synthesizeBounded(
        _ chunks: [PreparedSpeechChunk]
    ) async throws -> [SpeechSynthesisAsset] {
        guard !chunks.isEmpty else { return [] }
        let limit = min(engine.executionPolicy.maximumConcurrency, chunks.count)
        return try await withThrowingTaskGroup(
            of: (Int, SpeechSynthesisAsset).self,
            returning: [SpeechSynthesisAsset].self
        ) { group in
            var nextIndex = 0
            for _ in 0..<limit {
                let index = nextIndex
                nextIndex += 1
                group.addTask { (index, try await engine.synthesize(chunks[index])) }
            }

            var completed: [Int: SpeechSynthesisAsset] = [:]
            while let (index, asset) = try await group.next() {
                completed[index] = asset
                if nextIndex < chunks.count {
                    let scheduledIndex = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (scheduledIndex, try await engine.synthesize(chunks[scheduledIndex]))
                    }
                }
            }
            return try (0..<chunks.count).map { index in
                guard let asset = completed[index] else {
                    throw SpeechEngineSessionError.missingCompletedAsset(index: index)
                }
                return asset
            }
        }
    }
}

public enum SpeechEngineSessionError: Error, Equatable {
    case missingCompletedAsset(index: Int)
}

public enum SpeechStagingIdentity {
    public static func make(
        engineID: SpeechEngineID,
        chunk: PreparedSpeechChunk,
        signature: SpeechSynthesisSignature
    ) -> String {
        let value = [engineID.rawValue, chunk.stableHash, signature.rawValue].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum SpeechSynthesisAsset: Sendable {
    case pcm(AudioResult)
    case encodedAudio(file: URL, format: String, duration: TimeInterval?, metadata: [String: String])
}
