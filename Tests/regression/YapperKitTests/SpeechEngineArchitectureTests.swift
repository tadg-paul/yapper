// ABOUTME: Regression tests for the public, extensible speech-engine architecture.
// ABOUTME: Exercises YapperKit as a library consumer without CLI-target dependencies.

import Foundation
import Testing
@testable import YapperKit

@Suite(.serialized)
struct SpeechEngineArchitectureTests {
    @Test("RT-46.37, RT-46.47: registered engines carry private prepared payloads")
    func registeredEngineCarriesPrivatePreparedPayload() async throws {
        let recorder = EngineRecorder()
        var registry = SpeechEngineRegistry()
        registry.register(SpeechEngineDescriptor(
            id: "test-local",
            capabilities: .testLocal,
            makeEngine: { TestSpeechEngine(recorder: recorder, signatureValue: "model-a") }
        ))

        let session = try registry.makeSession(engineID: "test-local")
        let assets = try await session.synthesize([
            SpeechUtterance(
                text: "Hello from a host application.",
                sourceID: "consumer:1",
                role: .narration,
                voice: "narrator"
            )
        ])

        #expect(assets.count == 1)
        #expect(recorder.decodedPayloads == [TestPreparedPayload(marker: "private:test-local")])
        #expect(recorder.synthesizedTexts == ["Hello from a host application."])
    }

    @Test("RT-46.46: one invocation reuses one model-bearing engine instance")
    func invocationReusesOneEngineInstance() async throws {
        let recorder = EngineRecorder()
        var registry = SpeechEngineRegistry()
        registry.register(SpeechEngineDescriptor(
            id: "persistent-local",
            capabilities: .testLocal,
            makeEngine: {
                recorder.recordConstruction()
                return TestSpeechEngine(recorder: recorder, signatureValue: "model-a")
            }
        ))

        let session = try registry.makeSession(engineID: "persistent-local")
        _ = try await session.synthesize([
            SpeechUtterance(text: "First.", sourceID: "1", role: .narration, voice: "narrator"),
            SpeechUtterance(text: "Second.", sourceID: "2", role: .dialogue, voice: "speaker")
        ])

        #expect(recorder.constructionCount == 1)
        #expect(recorder.synthesizedTexts == ["First.", "Second."])
    }

    @Test("RT-46.48: engine synthesis signatures control staging identity")
    func synthesisSignatureControlsStagingIdentity() throws {
        let chunk = PreparedSpeechChunk.testChunk(engineID: "signature-test")
        let first = SpeechStagingIdentity.make(
            engineID: "signature-test",
            chunk: chunk,
            signature: SpeechSynthesisSignature("model=a|voice=one")
        )
        let changed = SpeechStagingIdentity.make(
            engineID: "signature-test",
            chunk: chunk,
            signature: SpeechSynthesisSignature("model=b|voice=one")
        )
        let repeated = SpeechStagingIdentity.make(
            engineID: "signature-test",
            chunk: chunk,
            signature: SpeechSynthesisSignature("model=a|voice=one")
        )

        #expect(first != changed)
        #expect(first == repeated)
    }

    @Test("RT-46.39: unknown IDs report registered engine identifiers")
    func unknownEngineReportsRegisteredIDs() {
        var registry = SpeechEngineRegistry()
        registry.register(SpeechEngineDescriptor(
            id: .yapper,
            capabilities: .yapper,
            makeEngine: { TestSpeechEngine(recorder: EngineRecorder(), signatureValue: "yapper") }
        ))

        #expect(throws: SpeechEngineRegistryError.self) {
            _ = try registry.makeSession(engineID: "absent")
        }
        #expect(registry.registeredEngineIDs == [.yapper])
    }
}

private struct TestPreparedPayload: Codable, Equatable, Sendable {
    let marker: String
}

private final class EngineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedConstructionCount = 0
    private var storedDecodedPayloads: [TestPreparedPayload] = []
    private var storedSynthesizedTexts: [String] = []

    var constructionCount: Int { lock.withLock { storedConstructionCount } }
    var decodedPayloads: [TestPreparedPayload] { lock.withLock { storedDecodedPayloads } }
    var synthesizedTexts: [String] { lock.withLock { storedSynthesizedTexts } }

    func recordConstruction() {
        lock.withLock { storedConstructionCount += 1 }
    }

    func record(payload: TestPreparedPayload, text: String) {
        lock.withLock {
            storedDecodedPayloads.append(payload)
            storedSynthesizedTexts.append(text)
        }
    }
}

private struct TestSpeechEngine: SpeechEngine {
    let recorder: EngineRecorder
    let signatureValue: String

    var id: SpeechEngineID { "test-local" }
    var capabilities: SpeechEngineCapabilities { .testLocal }
    var executionPolicy: SpeechExecutionPolicy { .persistentSerial }

    func plan(_ utterance: SpeechUtterance) throws -> [PreparedSpeechChunk] {
        [PreparedSpeechChunk(
            chapterIndex: 0,
            chapterTitle: "",
            sourcePath: utterance.sourceID,
            chunkIndex: 0,
            text: utterance.text,
            previousText: utterance.previousText,
            nextText: utterance.nextText,
            characterCount: utterance.text.count,
            boundaryBefore: "none",
            containsParagraphBreak: false,
            stableHash: utterance.sourceID,
            engineID: id,
            voiceID: utterance.voice,
            semanticRole: utterance.role,
            enginePayload: try EnginePreparedPayload(
                TestPreparedPayload(marker: "private:\(id.rawValue)"),
                typeIdentifier: "test-payload"
            )
        )]
    }

    func synthesisSignature(for chunk: PreparedSpeechChunk) throws -> SpeechSynthesisSignature {
        SpeechSynthesisSignature(signatureValue)
    }

    func synthesize(_ chunk: PreparedSpeechChunk) async throws -> SpeechSynthesisAsset {
        let payload = try chunk.enginePayload?.decode(TestPreparedPayload.self)
        recorder.record(payload: try #require(payload), text: chunk.text)
        return .pcm(AudioResult(samples: [0, 0], sampleRate: 24_000))
    }
}

private extension SpeechEngineCapabilities {
    static let testLocal = SpeechEngineCapabilities(
        engineID: "test-local",
        locality: .local,
        emittedAudioKind: .pcm,
        requiresGenerationCredential: false,
        supportsAccountReporting: false,
        supportsReferenceAudio: true,
        supportsStreaming: false
    )
}

private extension PreparedSpeechChunk {
    static func testChunk(engineID: SpeechEngineID) -> PreparedSpeechChunk {
        PreparedSpeechChunk(
            chapterIndex: 0,
            chapterTitle: "Chapter",
            sourcePath: "chapter.md",
            chunkIndex: 0,
            text: "Text.",
            previousText: nil,
            nextText: nil,
            characterCount: 5,
            boundaryBefore: "none",
            containsParagraphBreak: false,
            stableHash: "source-hash",
            engineID: engineID,
            voiceID: "voice",
            semanticRole: .narration
        )
    }
}
