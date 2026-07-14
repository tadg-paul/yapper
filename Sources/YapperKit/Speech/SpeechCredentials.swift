// ABOUTME: Resolves API credentials from config literals, helper executables, or environment fallback.
// ABOUTME: Reports credential source metadata without exposing resolved secret values.

import Foundation

public enum SpeechCredentialSlot: String, CaseIterable, Sendable {
    case falGeneration = "fal-generation"
    case falAccount = "fal-account"
    case openAIGeneration = "openai-generation"
    case openAIAdmin = "openai-admin"

    public var environmentNames: [String] {
        switch self {
        case .falGeneration:
            return ["FAL_KEY"]
        case .falAccount:
            return ["FAL_ACCOUNT_KEY"]
        case .openAIGeneration:
            return ["OPENAI_API_KEY"]
        case .openAIAdmin:
            return ["OPENAI_SERVICE_KEY", "OPENAI_ADMIN_KEY"]
        }
    }

    public var configPath: String {
        switch self {
        case .falGeneration:
            return "yapper.engines.fal.credentials.generation"
        case .falAccount:
            return "yapper.engines.fal.credentials.account"
        case .openAIGeneration:
            return "yapper.engines.openai.credentials.generation"
        case .openAIAdmin:
            return "yapper.engines.openai.credentials.admin"
        }
    }
}

public enum SpeechCredentialSourceKind: String, Codable, Equatable, Sendable {
    case environment = "env"
    case configLiteral = "config literal"
    case helper
}

public struct ResolvedSpeechCredential: Equatable, Sendable {
    public let value: String
    public let sourceKind: SpeechCredentialSourceKind
    public let sourceDescription: String

    public var redactedDescription: String {
        "\(sourceKind.rawValue): \(sourceDescription)"
    }
}

public enum SpeechCredentialError: Error, CustomStringConvertible, Equatable {
    case helperMissing(slot: SpeechCredentialSlot, path: String)
    case helperNotExecutable(slot: SpeechCredentialSlot, path: String)
    case helperLaunchFailed(slot: SpeechCredentialSlot, path: String, message: String)
    case helperFailed(slot: SpeechCredentialSlot, path: String, status: Int32)
    case helperTimedOut(slot: SpeechCredentialSlot, path: String)
    case helperEmptyOutput(slot: SpeechCredentialSlot, path: String)
    case helperUnsupported(slot: SpeechCredentialSlot, path: String)

    public var description: String {
        switch self {
        case .helperMissing(let slot, let path):
            return "Credential helper for \(slot.configPath) not found: \(path)"
        case .helperNotExecutable(let slot, let path):
            return "Credential helper for \(slot.configPath) is not executable: \(path)"
        case .helperLaunchFailed(let slot, let path, let message):
            return "Credential helper for \(slot.configPath) failed to execute: \(path): \(message)"
        case .helperFailed(let slot, let path, let status):
            return "Credential helper for \(slot.configPath) failed with status \(status): \(path)"
        case .helperTimedOut(let slot, let path):
            return "Credential helper for \(slot.configPath) timed out: \(path)"
        case .helperEmptyOutput(let slot, let path):
            return "Credential helper for \(slot.configPath) returned empty output: \(path)"
        case .helperUnsupported(let slot, let path):
            return "Credential helper for \(slot.configPath) is unsupported on this platform: \(path)"
        }
    }
}

public protocol SpeechCredentialHelperRunning: Sendable {
    func run(path: String, slot: SpeechCredentialSlot, timeout: TimeInterval) throws -> String
}

public struct PlatformSpeechCredentialHelperRunner: SpeechCredentialHelperRunning {
    public init() {}

    public func run(path: String, slot: SpeechCredentialSlot, timeout: TimeInterval) throws -> String {
#if os(macOS)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw SpeechCredentialError.helperMissing(slot: slot, path: path)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw SpeechCredentialError.helperNotExecutable(slot: slot, path: path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = []
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw SpeechCredentialError.helperLaunchFailed(
                slot: slot,
                path: path,
                message: error.localizedDescription
            )
        }
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw SpeechCredentialError.helperTimedOut(slot: slot, path: path)
        }
        guard process.terminationStatus == 0 else {
            throw SpeechCredentialError.helperFailed(
                slot: slot,
                path: path,
                status: process.terminationStatus
            )
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        var secret = String(data: data, encoding: .utf8) ?? ""
        if secret.hasSuffix("\n") {
            secret.removeLast()
        }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechCredentialError.helperEmptyOutput(slot: slot, path: path)
        }
        return secret
#else
        throw SpeechCredentialError.helperUnsupported(slot: slot, path: path)
#endif
    }
}

public enum SpeechCredentialInput: Equatable, Sendable {
    case literal(String)
    case helper(String)
    case legacyAuto(String)
}

public struct SpeechCredentialConfig: Sendable {
    public let source: SpeechCredentialInput?
    public let baseDirectory: URL?

    public init(source: SpeechCredentialInput?, baseDirectory: URL?) {
        self.source = source
        self.baseDirectory = baseDirectory
    }

    /// Compatibility initializer for the deprecated scalar credential keys.
    public init(value: String?, baseDirectory: URL?) {
        self.source = value.map(SpeechCredentialInput.legacyAuto)
        self.baseDirectory = baseDirectory
    }
}

public struct SpeechCredentialResolver: Sendable {
    private let environment: [String: String]
    private let timeout: TimeInterval
    private let helperRunner: any SpeechCredentialHelperRunning

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 5,
        helperRunner: any SpeechCredentialHelperRunning = PlatformSpeechCredentialHelperRunner()
    ) {
        self.environment = environment
        self.timeout = timeout
        self.helperRunner = helperRunner
    }

    public func resolve(
        slot: SpeechCredentialSlot,
        config: SpeechCredentialConfig = SpeechCredentialConfig(value: nil, baseDirectory: nil)
    ) throws -> ResolvedSpeechCredential? {
        if let configured = try resolveConfiguredCredential(config, slot: slot) {
            return configured
        }

        for name in slot.environmentNames {
            if let value = environment[name], !value.isEmpty {
                return ResolvedSpeechCredential(
                    value: value,
                    sourceKind: .environment,
                    sourceDescription: name
                )
            }
        }

        return nil
    }

    private func resolveConfiguredCredential(
        _ config: SpeechCredentialConfig,
        slot: SpeechCredentialSlot
    ) throws -> ResolvedSpeechCredential? {
        guard let source = config.source else { return nil }
        let configuredValue: String
        switch source {
        case .literal(let value), .helper(let value), .legacyAuto(let value):
            configuredValue = value
        }
        let rawValue = configuredValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
              !rawValue.isEmpty else {
            return nil
        }

        let helperPath: String?
        switch source {
        case .literal:
            helperPath = nil
        case .helper:
            helperPath = resolvedHelperPath(for: rawValue, baseDirectory: config.baseDirectory)
        case .legacyAuto:
            helperPath = legacyHelperPath(for: rawValue, baseDirectory: config.baseDirectory)
        }
        if let helperPath {
            let secret = try helperRunner.run(path: helperPath, slot: slot, timeout: timeout)
            return ResolvedSpeechCredential(
                value: secret,
                sourceKind: .helper,
                sourceDescription: helperPath
            )
        }

        return ResolvedSpeechCredential(
            value: rawValue,
            sourceKind: .configLiteral,
            sourceDescription: "configured value"
        )
    }

    private func resolvedHelperPath(for value: String, baseDirectory: URL?) -> String {
        let expanded = expandTilde(value)
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        return (baseDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .appendingPathComponent(expanded)
            .standardizedFileURL.path
    }

    private func legacyHelperPath(for value: String, baseDirectory: URL?) -> String? {
        let path = resolvedHelperPath(for: value, baseDirectory: baseDirectory)
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") || value.hasPrefix("~") {
            return path
        }
        return nil
    }

    private func expandTilde(_ path: String) -> String {
        if path == "~" {
            return NSHomeDirectory()
        }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
}
