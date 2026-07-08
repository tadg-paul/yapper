// ABOUTME: Resolves API credentials from environment, config literals, or helper executables.
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
    case helperMissing(path: String)
    case helperNotExecutable(path: String)
    case helperFailed(path: String, status: Int32)
    case helperTimedOut(path: String)
    case helperEmptyOutput(path: String)

    public var description: String {
        switch self {
        case .helperMissing(let path):
            return "Credential helper not found: \(path)"
        case .helperNotExecutable(let path):
            return "Credential helper is not executable: \(path)"
        case .helperFailed(let path, let status):
            return "Credential helper failed with status \(status): \(path)"
        case .helperTimedOut(let path):
            return "Credential helper timed out: \(path)"
        case .helperEmptyOutput(let path):
            return "Credential helper returned empty output: \(path)"
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
        for name in slot.environmentNames {
            if let value = environment[name], !value.isEmpty {
                return ResolvedSpeechCredential(
                    value: value,
                    sourceKind: .environment,
                    sourceDescription: name
                )
            }
        }

        guard let rawValue = config.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        if let helperPath = helperPath(for: rawValue, baseDirectory: config.baseDirectory) {
            let secret = try runHelper(path: helperPath)
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

    private func runHelper(path: String) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw SpeechCredentialError.helperMissing(path: path)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw SpeechCredentialError.helperNotExecutable(path: path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = []
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw SpeechCredentialError.helperTimedOut(path: path)
        }
        guard process.terminationStatus == 0 else {
            throw SpeechCredentialError.helperFailed(path: path, status: process.terminationStatus)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        var secret = String(data: data, encoding: .utf8) ?? ""
        if secret.hasSuffix("\n") {
            secret.removeLast()
        }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechCredentialError.helperEmptyOutput(path: path)
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
