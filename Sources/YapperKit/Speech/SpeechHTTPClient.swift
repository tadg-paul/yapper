// ABOUTME: Provides an injectable HTTP boundary for remote speech providers.
// ABOUTME: Enables regression tests to avoid live FAL and OpenAI network calls.

import Foundation

public protocol SpeechHTTPClient: Sendable {
    func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionSpeechHTTPClient: SpeechHTTPClient {
    public init() {}

    public func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechProviderError.invalidHTTPResponse
        }
        return (data, httpResponse)
    }
}

public enum SpeechProviderError: Error, CustomStringConvertible, Equatable {
    case missingCredential(provider: String, slot: String)
    case invalidHTTPResponse
    case httpFailure(provider: String, context: String, status: Int, body: String)
    case malformedResponse(provider: String, expectedFields: String)
    case emptyAudio(provider: String)
    case downloadFailed(provider: String, url: String, message: String)

    public var description: String {
        switch self {
        case .missingCredential(let provider, let slot):
            return "\(provider) requires \(slot) credentials."
        case .invalidHTTPResponse:
            return "Provider response was not an HTTP response."
        case .httpFailure(let provider, let context, let status, let body):
            let suffix = body.isEmpty ? "" : ": \(body)"
            return "\(provider) \(context) failed with HTTP \(status)\(suffix)"
        case .malformedResponse(let provider, let expectedFields):
            return "\(provider) response did not contain expected audio field(s): \(expectedFields)"
        case .emptyAudio(let provider):
            return "\(provider) returned an empty audio response."
        case .downloadFailed(let provider, let url, let message):
            return "\(provider) audio download failed for \(url): \(message)"
        }
    }
}

