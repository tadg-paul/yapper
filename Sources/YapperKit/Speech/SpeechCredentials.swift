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
            return "yapper.remote-speech.fal.api-key"
        case .falAccount:
            return "yapper.remote-speech.fal.account-api-key"
        case .openAIGeneration:
            return "yapper.remote-speech.openai.api-key"
        case .openAIAdmin:
            return "yapper.remote-speech.openai.admin-api-key"
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
        }
    }
}

public struct SpeechCredentialConfig: Sendable {
    public let value: String?
    public let baseDirectory: URL?

    public init(value: String?, baseDirectory: URL?) {
        self.value = value
        self.baseDirectory = baseDirectory
    }
}

public struct SpeechCredentialResolver: Sendable {
    private let environment: [String: String]
    private let timeout: TimeInterval

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 5
    ) {
        self.environment = environment
        self.timeout = timeout
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
        guard let rawValue = config.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        if let helperPath = helperPath(for: rawValue, baseDirectory: config.baseDirectory) {
            let secret = try runHelper(path: helperPath, slot: slot)
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

    private func helperPath(for value: String, baseDirectory: URL?) -> String? {
        let expanded = expandTilde(value)
        let isAbsolute = expanded.hasPrefix("/")
        let absoluteCandidate = URL(fileURLWithPath: expanded)
        let candidates: [URL]
        if isAbsolute {
            candidates = [absoluteCandidate]
        } else if let baseDirectory {
            candidates = [baseDirectory.appendingPathComponent(expanded)]
        } else {
            candidates = [absoluteCandidate]
        }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }

        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") || value.hasPrefix("~") {
            return candidates[0].path
        }
        return nil
    }

    private func runHelper(path: String, slot: SpeechCredentialSlot) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
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
            throw SpeechCredentialError.helperFailed(slot: slot, path: path, status: process.terminationStatus)
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
    }

    private func expandTilde(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
}
