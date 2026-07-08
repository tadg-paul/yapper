// ABOUTME: Implements FAL and OpenAI speech provider request/response handling.
// ABOUTME: Uses Codable payloads and injectable HTTP clients for testable remote synthesis.

import Foundation

public struct FALSpeechSettings: Codable, Equatable, Sendable {
    public var endpoint: String
    public var voice: String
    public var outputFormat: String
    public var stability: Double
    public var similarityBoost: Double
    public var style: Double?
    public var speed: Double
    public var languageCode: String?
    public var textNormalization: String
    public var generationBaseURL: URL
    public var platformBaseURL: URL

    public init(
        endpoint: String = "fal-ai/elevenlabs/tts/multilingual-v2",
        voice: String = "Rachel",
        outputFormat: String = "mp3_44100_128",
        stability: Double = 0.5,
        similarityBoost: Double = 0.75,
        style: Double? = nil,
        speed: Double = 1.0,
        languageCode: String? = nil,
        textNormalization: String = "auto",
        generationBaseURL: URL = URL(string: "https://fal.run")!,
        platformBaseURL: URL = URL(string: "https://api.fal.ai")!
    ) {
        self.endpoint = endpoint
        self.voice = voice
        self.outputFormat = outputFormat
        self.stability = stability
        self.similarityBoost = similarityBoost
        self.style = style
        self.speed = speed
        self.languageCode = languageCode
        self.textNormalization = textNormalization
        self.generationBaseURL = generationBaseURL
        self.platformBaseURL = platformBaseURL
    }

    public var signature: String {
        [
            endpoint, voice, outputFormat, String(stability), String(similarityBoost),
            style.map { String($0) } ?? "", String(speed), languageCode ?? "", textNormalization
        ].joined(separator: "|")
    }
}

public struct OpenAISpeechSettings: Codable, Equatable, Sendable {
    public var model: String
    public var voice: String
    public var responseFormat: String
    public var speed: Double
    public var instructions: String?
    public var baseURL: URL

    public init(
        model: String = "gpt-4o-mini-tts",
        voice: String = "alloy",
        responseFormat: String = "aac",
        speed: Double = 1.0,
        instructions: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.model = model
        self.voice = voice
        self.responseFormat = responseFormat
        self.speed = speed
        self.instructions = instructions
        self.baseURL = baseURL
    }

    public var signature: String {
        [model, voice, responseFormat, String(speed), instructions ?? ""].joined(separator: "|")
    }
}

public struct FALSpeechClient: Sendable {
    private let settings: FALSpeechSettings
    private let credential: ResolvedSpeechCredential
    private let httpClient: SpeechHTTPClient
    private let timeout: TimeInterval

    public init(
        settings: FALSpeechSettings,
        credential: ResolvedSpeechCredential,
        httpClient: SpeechHTTPClient = URLSessionSpeechHTTPClient(),
        timeout: TimeInterval = 120
    ) {
        self.settings = settings
        self.credential = credential
        self.httpClient = httpClient
        self.timeout = timeout
    }

    public func synthesize(_ chunk: PreparedSpeechChunk, stagingDirectory: URL) async throws -> URL {
        let audioURL = try await requestAudioURL(for: chunk)
        let (data, response) = try await httpClient.data(for: URLRequest(url: audioURL), timeout: timeout)
        guard (200..<300).contains(response.statusCode) else {
            throw SpeechProviderError.downloadFailed(
                provider: "FAL",
                url: redactedURL(audioURL),
                message: "HTTP \(response.statusCode)"
            )
        }
        guard !data.isEmpty else {
            throw SpeechProviderError.emptyAudio(provider: "FAL")
        }
        let file = stagingDirectory.appendingPathComponent("\(chunk.stableHash).\(fileExtension(forFALOutput: settings.outputFormat))")
        try data.write(to: file, options: .atomic)
        return file
    }

    private func requestAudioURL(for chunk: PreparedSpeechChunk) async throws -> URL {
        let url = settings.generationBaseURL.appendingPathComponent(settings.endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Key \(credential.value)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(FALSpeechRequest(
            text: chunk.text,
            voice: settings.voice,
            outputFormat: settings.outputFormat,
            stability: settings.stability,
            similarityBoost: settings.similarityBoost,
            style: settings.style,
            speed: settings.speed,
            previousText: chunk.previousText,
            nextText: chunk.nextText,
            languageCode: settings.languageCode,
            applyTextNormalization: settings.textNormalization
        ))

        let (data, response) = try await httpClient.data(for: request, timeout: timeout)
        guard (200..<300).contains(response.statusCode) else {
            throw SpeechProviderError.httpFailure(
                provider: "FAL",
                context: settings.endpoint,
                status: response.statusCode,
                body: safeErrorBody(data)
            )
        }

        let decoded = try JSONDecoder().decode(FALSpeechResponse.self, from: data)
        guard let urlString = decoded.audio?.url ?? decoded.audioURL ?? decoded.url,
              let audioURL = URL(string: urlString) else {
            throw SpeechProviderError.malformedResponse(provider: "FAL", expectedFields: "audio.url, audio_url, or url")
        }
        return audioURL
    }

    private func fileExtension(forFALOutput outputFormat: String) -> String {
        if outputFormat.hasPrefix("mp3") { return "mp3" }
        if outputFormat.hasPrefix("pcm") { return "wav" }
        if outputFormat.hasPrefix("opus") { return "opus" }
        if outputFormat.hasPrefix("ulaw") || outputFormat.hasPrefix("alaw") { return "wav" }
        return "audio"
    }
}

public struct OpenAISpeechClient: Sendable {
    private let settings: OpenAISpeechSettings
    private let credential: ResolvedSpeechCredential
    private let httpClient: SpeechHTTPClient
    private let timeout: TimeInterval

    public init(
        settings: OpenAISpeechSettings,
        credential: ResolvedSpeechCredential,
        httpClient: SpeechHTTPClient = URLSessionSpeechHTTPClient(),
        timeout: TimeInterval = 120
    ) {
        self.settings = settings
        self.credential = credential
        self.httpClient = httpClient
        self.timeout = timeout
    }

    public func synthesize(_ chunk: PreparedSpeechChunk, stagingDirectory: URL) async throws -> URL {
        var request = URLRequest(url: settings.baseURL.appendingPathComponent("audio/speech"))
        request.httpMethod = "POST"
        request.addValue("Bearer \(credential.value)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAISpeechRequest(
            model: settings.model,
            input: chunk.text,
            voice: settings.voice,
            responseFormat: settings.responseFormat,
            speed: settings.speed,
            instructions: supportsInstructions(settings.model) ? settings.instructions : nil
        ))

        let (data, response) = try await httpClient.data(for: request, timeout: timeout)
        guard (200..<300).contains(response.statusCode) else {
            throw SpeechProviderError.httpFailure(
                provider: "OpenAI",
                context: settings.model,
                status: response.statusCode,
                body: safeErrorBody(data)
            )
        }
        guard !data.isEmpty else {
            throw SpeechProviderError.emptyAudio(provider: "OpenAI")
        }

        let file = stagingDirectory.appendingPathComponent("\(chunk.stableHash).\(settings.responseFormat)")
        try data.write(to: file, options: .atomic)
        return file
    }

    private func supportsInstructions(_ model: String) -> Bool {
        model != "tts-1" && model != "tts-1-hd"
    }
}

private struct FALSpeechRequest: Encodable {
    let text: String
    let voice: String
    let outputFormat: String
    let stability: Double
    let similarityBoost: Double
    let style: Double?
    let speed: Double
    let previousText: String?
    let nextText: String?
    let languageCode: String?
    let applyTextNormalization: String

    enum CodingKeys: String, CodingKey {
        case text, voice, stability, style, speed
        case outputFormat = "output_format"
        case similarityBoost = "similarity_boost"
        case previousText = "previous_text"
        case nextText = "next_text"
        case languageCode = "language_code"
        case applyTextNormalization = "apply_text_normalization"
    }
}

private struct FALSpeechResponse: Decodable {
    struct Audio: Decodable {
        let url: String?
    }

    let audio: Audio?
    let audioURL: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case audio
        case audioURL = "audio_url"
        case url
    }
}

private struct OpenAISpeechRequest: Encodable {
    let model: String
    let input: String
    let voice: String
    let responseFormat: String
    let speed: Double
    let instructions: String?

    enum CodingKeys: String, CodingKey {
        case model, input, voice, speed, instructions
        case responseFormat = "response_format"
    }
}

private func safeErrorBody(_ data: Data) -> String {
    guard let text = String(data: data, encoding: .utf8) else { return "" }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 500 else { return trimmed }
    return String(trimmed.prefix(500))
}

public func redactedURL(_ url: URL) -> String {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.query = nil
    components?.fragment = nil
    return components?.string ?? "\(url.scheme ?? "url")://\(url.host ?? "unknown")\(url.path)"
}
