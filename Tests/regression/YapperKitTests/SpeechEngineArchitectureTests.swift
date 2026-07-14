// ABOUTME: Regression tests for the public, extensible speech-engine architecture.
// ABOUTME: Exercises YapperKit as a library consumer without CLI-target dependencies.

import Foundation
import Testing
@testable import YapperKit

@Suite(.serialized)
struct SpeechEngineArchitectureTests {
    @Test("RT-46.52: built-in engines declare IPA capability")
    func builtInEnginesDeclareIPACapability() {
        #expect(SpeechEngineCapabilities.yapper.supportsIPA)
        #expect(!SpeechEngineCapabilities.fal.supportsIPA)
        #expect(!SpeechEngineCapabilities.openAI.supportsIPA)
    }

    @Test("RT-46.37, RT-46.47: registered engines carry private prepared payloads")
    func registeredEngineCarriesPrivatePreparedPayload() async throws {
        let recorder = EngineRecorder()
        var registry = SpeechEngineRegistry()
        registry.register(SpeechEngineDescriptor(
            id: "test-local",
            capabilities: .testLocal,
            makeEngine: {
                TestSpeechEngine(engineID: "test-local", recorder: recorder, signatureValue: "model-a")
            }
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
                return TestSpeechEngine(
                    engineID: "persistent-local",
                    recorder: recorder,
                    signatureValue: "model-a"
                )
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
            makeEngine: {
                TestSpeechEngine(engineID: .yapper, recorder: EngineRecorder(), signatureValue: "yapper")
            }
        ))

        #expect(throws: SpeechEngineRegistryError.self) {
            _ = try registry.makeSession(engineID: "absent")
        }
        #expect(registry.registeredEngineIDs == [.yapper])
    }

    @Test("RT-46.30: bounded engine concurrency is enforced without reordering assets")
    func boundedConcurrencyPreservesOrder() async throws {
        let probe = ConcurrencyProbe()
        let session = SpeechEngineSession(engine: BoundedTestEngine(probe: probe))
        let utterances = (0..<5).map { index in
            SpeechUtterance(
                text: "Line \(index)",
                sourceID: String(index),
                role: .narration,
                voice: "voice"
            )
        }

        let assets = try await session.synthesize(utterances)
        let order = assets.compactMap { asset -> Int? in
            guard case .pcm(let audio) = asset, let sample = audio.samples.first else { return nil }
            return Int(sample)
        }

        let maximumActive = await probe.maximumActive
        #expect(maximumActive == 2)
        #expect(order == [0, 1, 2, 3, 4])
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private(set) var maximumActive = 0

    func begin() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func end() {
        active -= 1
    }
}

private struct BoundedTestEngine: SpeechEngine {
    let probe: ConcurrencyProbe
    let id: SpeechEngineID = "bounded-test"
    let capabilities = SpeechEngineCapabilities.testLocal
    let executionPolicy = SpeechExecutionPolicy(mode: .boundedConcurrent, maximumConcurrency: 2)

    func plan(_ utterance: SpeechUtterance) throws -> [PreparedSpeechChunk] {
        [PreparedSpeechChunk(
            chapterIndex: 0,
            chapterTitle: utterance.sourceID,
            sourcePath: utterance.sourceID,
            chunkIndex: 0,
            text: utterance.text,
            previousText: nil,
            nextText: nil,
            characterCount: utterance.text.count,
            boundaryBefore: "none",
            containsParagraphBreak: false,
            stableHash: utterance.sourceID,
            engineID: id,
            voiceID: utterance.voice,
            semanticRole: utterance.role
        )]
    }

    func synthesisSignature(for chunk: PreparedSpeechChunk) throws -> SpeechSynthesisSignature {
        "bounded"
    }

    func synthesize(_ chunk: PreparedSpeechChunk) async throws -> SpeechSynthesisAsset {
        await probe.begin()
        let index = Int(chunk.sourcePath) ?? 0
        do {
            try await Task.sleep(for: .milliseconds((5 - index) * 5))
            await probe.end()
            return .pcm(AudioResult(samples: [Float(index)]))
        } catch {
            await probe.end()
            throw error
        }
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
    let engineID: SpeechEngineID
    let recorder: EngineRecorder
    let signatureValue: String

    var id: SpeechEngineID { engineID }
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
