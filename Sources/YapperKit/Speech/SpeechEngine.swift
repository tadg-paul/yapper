// ABOUTME: Defines speech engine abstractions shared by local and API-backed synthesis.
// ABOUTME: Keeps provider-specific credentials and billing out of the base synthesis model.

import Foundation

public enum SpeechEngineKind: String, Codable, CaseIterable, Sendable {
    case yapper
    case fal
    case openAI = "openai"
    case f5

    public var isRemote: Bool {
        switch self {
        case .fal, .openAI:
            return true
        case .yapper, .f5:
            return false
        }
    }
}

public enum SpeechSynthesisAudioKind: String, Codable, Sendable {
    case pcm
    case encodedAudio = "encoded-audio"
}

public struct SpeechEngineCapabilities: Codable, Equatable, Sendable {
    public let engineKind: SpeechEngineKind
    public let isRemote: Bool
    public let emittedAudioKind: SpeechSynthesisAudioKind
    public let requiresGenerationCredential: Bool
    public let supportsAccountReporting: Bool
    public let supportsReferenceAudio: Bool
    public let supportsStreaming: Bool
    public let licenceCategory: String?

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
        self.engineKind = engineKind
        self.isRemote = isRemote
        self.emittedAudioKind = emittedAudioKind
        self.requiresGenerationCredential = requiresGenerationCredential
        self.supportsAccountReporting = supportsAccountReporting
        self.supportsReferenceAudio = supportsReferenceAudio
        self.supportsStreaming = supportsStreaming
        self.licenceCategory = licenceCategory
    }

    public static let yapper = SpeechEngineCapabilities(
        engineKind: .yapper,
        isRemote: false,
        emittedAudioKind: .pcm,
        requiresGenerationCredential: false,
        supportsAccountReporting: false,
        supportsReferenceAudio: false,
        supportsStreaming: true,
        licenceCategory: "Apache-2.0 weights"
    )

    public static let fal = SpeechEngineCapabilities(
        engineKind: .fal,
        isRemote: true,
        emittedAudioKind: .encodedAudio,
        requiresGenerationCredential: true,
        supportsAccountReporting: true,
        supportsReferenceAudio: false,
        supportsStreaming: false,
        licenceCategory: "provider-managed"
    )

    public static let openAI = SpeechEngineCapabilities(
        engineKind: .openAI,
        isRemote: true,
        emittedAudioKind: .encodedAudio,
        requiresGenerationCredential: true,
        supportsAccountReporting: true,
        supportsReferenceAudio: false,
        supportsStreaming: false,
        licenceCategory: "provider-managed"
    )

    public static let f5 = SpeechEngineCapabilities(
        engineKind: .f5,
        isRemote: false,
        emittedAudioKind: .pcm,
        requiresGenerationCredential: false,
        supportsAccountReporting: false,
        supportsReferenceAudio: true,
        supportsStreaming: false,
        licenceCategory: "optional local model"
    )
}

public enum SpeechSynthesisAsset: Sendable {
    case pcm(AudioResult)
    case encodedAudio(file: URL, format: String, duration: TimeInterval?, metadata: [String: String])
}

