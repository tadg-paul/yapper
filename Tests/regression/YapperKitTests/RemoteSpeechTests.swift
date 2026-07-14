// ABOUTME: Regression tests for remote speech planning, credentials, and provider payloads.
// ABOUTME: Uses fake HTTP responses so FAL and OpenAI are never contacted by regression tests.

import Foundation
import Testing
@testable import YapperKit

@Suite(.serialized)
struct RemoteSpeechTests {
    @Test("RT-41.3 and RT-41.4: remote plans share prose preprocessing with engine-specific constraints")
    func remotePlansSharePreprocessingWithProviderConstraints() {
        let source = SpeechSourceDocument(
            sourcePath: "/book/chapter.md",
            chapterTitle: "Chapter",
            text: "that is a lovely *jacket*.\n\n--- I would like cheese, he said."
        )

        let falPlan = SpeechPlanner.makePlan(
            sources: [source],
            engineKind: .fal,
            substitutions: ["jacket": "coat"],
            engineSettingsSignature: "fal-settings"
        )
        let openAIPlan = SpeechPlanner.makePlan(
            sources: [source],
            engineKind: .openAI,
            substitutions: ["jacket": "coat"],
            engineSettingsSignature: "openai-settings"
        )

        #expect(falPlan.chapters[0].transformedText == "that is a lovely \"coat\".\n\n\"I would like cheese, he said.\"")
        #expect(openAIPlan.chapters[0].transformedText == falPlan.chapters[0].transformedText)
        #expect(falPlan.constraints.policyName == "remote-sentence-2500")
        #expect(openAIPlan.constraints.policyName == "remote-sentence-4096")
    }

    @Test("RT-41.25 through RT-41.27 and RT-41.37: config credentials resolve before environment fallback")
    func configCredentialsResolveBeforeEnvironmentFallback() throws {
        let resolver = SpeechCredentialResolver(environment: [
            "FAL_KEY": "env-fal-generation-secret",
            "FAL_ACCOUNT_KEY": "env-fal-account-secret",
            "OPENAI_API_KEY": "env-openai-generation-secret",
            "OPENAI_ADMIN_KEY": "env-openai-admin-secret"
        ])

        let falGeneration = try #require(try resolver.resolve(
            slot: .falGeneration,
            config: SpeechCredentialConfig(value: "config-fal-generation-secret", baseDirectory: nil)
        ))
        let falAccount = try #require(try resolver.resolve(
            slot: .falAccount,
            config: SpeechCredentialConfig(value: "config-fal-account-secret", baseDirectory: nil)
        ))
        let openAIGeneration = try #require(try resolver.resolve(
            slot: .openAIGeneration,
            config: SpeechCredentialConfig(value: "config-openai-generation-secret", baseDirectory: nil)
        ))
        let openAIAdmin = try #require(try resolver.resolve(
            slot: .openAIAdmin,
            config: SpeechCredentialConfig(value: "config-openai-admin-secret", baseDirectory: nil)
        ))
        let fallback = try #require(try resolver.resolve(slot: .falGeneration))

        #expect(falGeneration.value == "config-fal-generation-secret")
        #expect(falAccount.value == "config-fal-account-secret")
        #expect(openAIGeneration.value == "config-openai-generation-secret")
        #expect(openAIAdmin.value == "config-openai-admin-secret")
        #expect(fallback.value == "env-fal-generation-secret")
        #expect(falGeneration.redactedDescription == "config literal: configured value")
        #expect(fallback.redactedDescription == "env: FAL_KEY")
        #expect(!falGeneration.redactedDescription.contains("secret"))
        #expect(falAccount.value != falGeneration.value)
    }

    @Test("RT-41.38: helper credentials execute directly and trim one newline")
    func helperCredentialExecutesDirectly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_remote_speech_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let helper = directory.appendingPathComponent("print-key.sh")
        try "#!/usr/bin/env bash\nprintf 'helper-secret\\n'\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        let resolver = SpeechCredentialResolver(environment: [:])
        let credential = try #require(try resolver.resolve(
            slot: .openAIGeneration,
            config: SpeechCredentialConfig(value: "./print-key.sh", baseDirectory: directory)
        ))

        #expect(credential.value == "helper-secret")
        #expect(credential.sourceKind == .helper)
        #expect(!credential.redactedDescription.contains("helper-secret"))
    }

    @Test("RT-47.28: canonical literal credentials are never interpreted as helper paths")
    func canonicalLiteralCredentialRemainsLiteral() throws {
        let resolver = SpeechCredentialResolver(environment: [:])
        let credential = try #require(try resolver.resolve(
            slot: .openAIGeneration,
            config: SpeechCredentialConfig(
                source: .literal("./not-a-helper.sh"),
                baseDirectory: FileManager.default.temporaryDirectory
            )
        ))

        #expect(credential.value == "./not-a-helper.sh")
        #expect(credential.sourceKind == .configLiteral)
    }

    @Test("RT-47.29: canonical helper credentials resolve from the declaring directory")
    func canonicalHelperUsesDeclaringDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("print-key.sh")
        try "#!/bin/sh\nprintf canonical-helper-secret".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        let resolver = SpeechCredentialResolver(environment: [:])
        let credential = try #require(try resolver.resolve(
            slot: .falGeneration,
            config: SpeechCredentialConfig(source: .helper("./print-key.sh"), baseDirectory: directory)
        ))

        #expect(credential.value == "canonical-helper-secret")
        #expect(credential.sourceKind == .helper)
        #expect(credential.sourceDescription == helper.path)
    }

    @Test("RT-41.33: FAL synthesis sends generation payload only when synthesis is invoked")
    func falClientPayloadIncludesContext() async throws {
        let httpClient = FakeSpeechHTTPClient()
        await httpClient.enqueueJSON(#"{"audio":{"url":"https://media.example.test/audio/out.mp3?token=secret"}}"#)
        await httpClient.enqueueData(Data("audio-bytes".utf8), contentType: "audio/mpeg")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_fal_provider_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = FALSpeechSettings(
            voice: "Aria",
            outputFormat: "mp3_44100_128",
            style: 0.2,
            speed: 0.95,
            generationBaseURL: URL(string: "https://fal.example.test")!
        )
        let credential = ResolvedSpeechCredential(
            value: "fal-secret",
            sourceKind: .environment,
            sourceDescription: "FAL_KEY"
        )
        let client = FALSpeechClient(settings: settings, credential: credential, httpClient: httpClient)
        let chunk = PreparedSpeechChunk(
            chapterIndex: 0,
            chapterTitle: "Chapter",
            sourcePath: "chapter.md",
            chunkIndex: 1,
            text: "Current text.",
            previousText: "Previous text.",
            nextText: "Next text.",
            characterCount: 13,
            boundaryBefore: "character-limit",
            containsParagraphBreak: false,
            stableHash: "abc123"
        )

        let file = try await client.synthesize(chunk, stagingDirectory: directory)
        let requests = await httpClient.requests
        let generationBody = try #require(String(data: requests[0].httpBody ?? Data(), encoding: .utf8))

        #expect(requests.count == 2)
        #expect(file.lastPathComponent == "abc123.mp3")
        #expect(generationBody.contains(#""previous_text":"Previous text.""#))
        #expect(generationBody.contains(#""next_text":"Next text.""#))
        #expect(generationBody.contains(#""apply_text_normalization":"auto""#))
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Key fal-secret")
    }

    @Test("RT-41.10 and RT-41.33: OpenAI payload follows speech API and legacy models omit instructions")
    func openAIClientOmitsInstructionsForLegacyModels() async throws {
        let httpClient = FakeSpeechHTTPClient()
        await httpClient.enqueueData(Data("aac-bytes".utf8), contentType: "audio/aac")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_openai_provider_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = OpenAISpeechSettings(
            model: "tts-1",
            voice: "alloy",
            responseFormat: "aac",
            speed: 1.1,
            instructions: "Read with warmth.",
            baseURL: URL(string: "https://openai.example.test/v1")!
        )
        let credential = ResolvedSpeechCredential(
            value: "openai-secret",
            sourceKind: .environment,
            sourceDescription: "OPENAI_API_KEY"
        )
        let client = OpenAISpeechClient(settings: settings, credential: credential, httpClient: httpClient)
        let chunk = PreparedSpeechChunk(
            chapterIndex: 0,
            chapterTitle: "Chapter",
            sourcePath: "chapter.md",
            chunkIndex: 0,
            text: "Current text.",
            previousText: nil,
            nextText: nil,
            characterCount: 13,
            boundaryBefore: "none",
            containsParagraphBreak: false,
            stableHash: "def456"
        )

        _ = try await client.synthesize(chunk, stagingDirectory: directory)
        let request = try #require(await httpClient.requests.first)
        let body = try #require(String(data: request.httpBody ?? Data(), encoding: .utf8))

        #expect(body.contains(#""model":"tts-1""#))
        #expect(body.contains(#""response_format":"aac""#))
        #expect(!body.contains("instructions"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-secret")
    }

    @Test("RT-46.11 and RT-46.47: built-in provider adapters synthesize through public sessions")
    func providerAdaptersSynthesizeThroughPublicSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yapper_engine_adapter_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let credential = ResolvedSpeechCredential(
            value: "provider-secret",
            sourceKind: .configLiteral,
            sourceDescription: "configured value"
        )

        let falHTTP = FakeSpeechHTTPClient()
        await falHTTP.enqueueJSON(#"{"audio":{"url":"https://media.example.test/voice.mp3"}}"#)
        await falHTTP.enqueueData(Data("fal-audio".utf8), contentType: "audio/mpeg")
        let fal = FALSpeechEngine(
            settings: FALSpeechSettings(generationBaseURL: URL(string: "https://fal.example.test")!),
            credential: credential,
            stagingDirectory: directory,
            httpClient: falHTTP
        )
        let falAssets = try await SpeechEngineSession(engine: fal).synthesize([
            SpeechUtterance(
                text: "Hello from FAL.",
                sourceID: "line-1",
                role: .dialogue,
                voice: "Aria",
                speed: 0.8,
                previousText: "Before.",
                nextText: "After."
            )
        ])
        let falRequests = await falHTTP.requests
        let falBody = try #require(String(data: falRequests[0].httpBody ?? Data(), encoding: .utf8))
        #expect(falAssets.count == 1)
        #expect(falBody.contains(#""voice":"Aria""#))
        #expect(falBody.contains(#""speed":0.8"#))

        let openAIHTTP = FakeSpeechHTTPClient()
        await openAIHTTP.enqueueData(Data("openai-audio".utf8), contentType: "audio/aac")
        let openAI = OpenAISpeechEngine(
            settings: OpenAISpeechSettings(baseURL: URL(string: "https://openai.example.test/v1")!),
            credential: credential,
            stagingDirectory: directory,
            httpClient: openAIHTTP
        )
        let openAIAssets = try await SpeechEngineSession(engine: openAI).synthesize([
            SpeechUtterance(
                text: "Hello from OpenAI.",
                sourceID: "line-2",
                role: .narration,
                voice: "coral",
                speed: 1.1
            )
        ])
        let openAIRequests = await openAIHTTP.requests
        let openAIBody = try #require(String(data: openAIRequests[0].httpBody ?? Data(), encoding: .utf8))
        #expect(openAIAssets.count == 1)
        #expect(openAIBody.contains(#""voice":"coral""#))
        #expect(openAIBody.contains(#""speed":1.1"#))
    }

    @Test("RT-41.9 and RT-41.12: FAL reporter returns pricing estimate and balance diagnostics")
    func falReporterReturnsPricingAndBalance() async {
        let httpClient = FakeSpeechHTTPClient()
        await httpClient.enqueueJSON(#"{"prices":[{"endpoint_id":"fal-ai/elevenlabs/tts/multilingual-v2","unit_price":"0.18","unit":"1000 characters","currency":"usd"}]}"#)
        await httpClient.enqueueJSON(#"{"credits":{"current_balance":"12.5","currency":"usd"}}"#)
        let credential = ResolvedSpeechCredential(
            value: "fal-account-secret",
            sourceKind: .environment,
            sourceDescription: "FAL_ACCOUNT_KEY"
        )
        let reporter = FALAccountReporter(
            baseURL: URL(string: "https://api.fal.example.test")!,
            credential: credential,
            httpClient: httpClient
        )

        let diagnostics = await reporter.dryRunDiagnostics(
            endpoint: "fal-ai/elevenlabs/tts/multilingual-v2",
            characterCount: 2500
        )

        #expect(diagnostics.contains {
            $0.label == "FAL pricing" && $0.value.contains("estimated 0.4500 usd")
        })
        #expect(diagnostics.contains {
            $0.label == "FAL account balance" && $0.value == "12.5 usd"
        })
    }

    @Test("RT-41.34: FAL account 403 diagnostic names likely Admin-scope problem")
    func falReporterAdminScopeDiagnostic() async {
        let httpClient = FakeSpeechHTTPClient()
        await httpClient.enqueueJSON(#"{"message":"forbidden"}"#, status: 403)
        await httpClient.enqueueJSON(#"{"credits":{"current_balance":12.5,"currency":"usd"}}"#)
        let credential = ResolvedSpeechCredential(
            value: "fal-account-secret",
            sourceKind: .environment,
            sourceDescription: "FAL_ACCOUNT_KEY"
        )
        let reporter = FALAccountReporter(
            baseURL: URL(string: "https://api.fal.example.test")!,
            credential: credential,
            httpClient: httpClient
        )

        let diagnostics = await reporter.dryRunDiagnostics(
            endpoint: "fal-ai/elevenlabs/tts/multilingual-v2",
            characterCount: 100
        )

        #expect(diagnostics.contains {
            $0.label == "FAL pricing" && $0.value.contains("Admin scope")
        })
    }

    @Test("RT-44.4: FAL reporter identifies authenticated account responses without balance fields")
    func falReporterIdentifiesAuthenticatedBalanceResponseWithoutBalance() async {
        let httpClient = FakeSpeechHTTPClient()
        await httpClient.enqueueJSON(#"{"prices":[{"endpoint_id":"fal-ai/elevenlabs/tts/multilingual-v2","unit_price":"0.1","unit":"1000 characters","currency":"USD"}]}"#)
        await httpClient.enqueueJSON(#"{"username":"example-user"}"#)
        let credential = ResolvedSpeechCredential(
            value: "fal-account-secret",
            sourceKind: .environment,
            sourceDescription: "FAL_ACCOUNT_KEY"
        )
        let reporter = FALAccountReporter(
            baseURL: URL(string: "https://api.fal.example.test")!,
            credential: credential,
            httpClient: httpClient
        )

        let diagnostics = await reporter.dryRunDiagnostics(
            endpoint: "fal-ai/elevenlabs/tts/multilingual-v2",
            characterCount: 22
        )

        #expect(diagnostics.contains {
            $0.label == "FAL account balance" && $0.value == "authenticated, balance unavailable"
        })
    }

    @Test("RT-41.15 and RT-41.35: OpenAI reporter keeps partial usage when costs fail")
    func openAIReporterKeepsPartialUsageWhenCostsFail() async {
        let httpClient = FakeSpeechHTTPClient()
        await httpClient.enqueueJSON(#"{"data":[{"results":[{"characters":1200,"num_model_requests":3}]}]}"#)
        await httpClient.enqueueJSON(#"{"error":{"message":"unavailable"}}"#, status: 500)
        let credential = ResolvedSpeechCredential(
            value: "openai-admin-secret",
            sourceKind: .environment,
            sourceDescription: "OPENAI_ADMIN_KEY"
        )
        let reporter = OpenAIAdminReporter(
            baseURL: URL(string: "https://api.openai.example.test/v1")!,
            credential: credential,
            httpClient: httpClient
        )

        let diagnostics = await reporter.usageAndCostDiagnostics()

        #expect(diagnostics.contains {
            $0.label == "OpenAI audio speech usage" && $0.value.contains("characters 1200")
        })
        #expect(diagnostics.contains {
            $0.label == "OpenAI organization costs" && $0.value.contains("unavailable")
        })
    }

    @Test("RT-44.3: OpenAI reporter accepts string-valued cost amounts")
    func openAIReporterAcceptsStringValuedCostAmounts() async {
        let httpClient = FakeSpeechHTTPClient()
        await httpClient.enqueueJSON(#"{"data":[{"results":[{"characters":1200,"num_model_requests":3}]}]}"#)
        await httpClient.enqueueJSON(#"{"data":[{"results":[{"amount":{"value":"0.1234","currency":"usd"}}]}]}"#)
        let credential = ResolvedSpeechCredential(
            value: "openai-admin-secret",
            sourceKind: .environment,
            sourceDescription: "OPENAI_ADMIN_KEY"
        )
        let reporter = OpenAIAdminReporter(
            baseURL: URL(string: "https://api.openai.example.test/v1")!,
            credential: credential,
            httpClient: httpClient
        )

        let diagnostics = await reporter.usageAndCostDiagnostics()

        #expect(diagnostics.contains {
            $0.label == "OpenAI organization costs" && $0.value.contains("last 24h 0.1234 usd")
        })
    }
}

private actor FakeSpeechHTTPClient: SpeechHTTPClient {
    private struct Response {
        let data: Data
        let status: Int
        let contentType: String
    }

    private var responses: [Response] = []
    private(set) var requests: [URLRequest] = []

    func enqueueJSON(_ json: String, status: Int = 200) {
        responses.append(Response(data: Data(json.utf8), status: status, contentType: "application/json"))
    }

    func enqueueData(_ data: Data, status: Int = 200, contentType: String) {
        responses.append(Response(data: data, status: status, contentType: contentType))
    }

    func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.test")!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": response.contentType]
        )!
        return (response.data, httpResponse)
    }
}
