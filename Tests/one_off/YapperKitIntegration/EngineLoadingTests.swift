// ABOUTME: Tests for YapperEngine model and voice loading.
// ABOUTME: Covers RT-1.3 through RT-1.6.

import Testing
import Foundation
@testable import YapperKit

@Suite(.serialized)
struct EngineLoadingTests {

    private static let modelPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/models/kokoro-v1_0.safetensors")
    private static let voicesPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/yapper/voices")

    // RT-1.3: Engine initialises with valid safetensors and npz paths without error
    @Test("RT-1.3: Engine initialises with valid model and voice paths")
    func test_engine_initialises_with_valid_paths_RT1_3() throws {
        let engine = try YapperEngine(modelPath: Self.modelPath, voicesPath: Self.voicesPath)
        #expect(!engine.weights.isEmpty)
    }

    // RT-1.4: Missing model file produces an error identifying the expected path
    @Test("RT-1.4: Missing model file produces descriptive error")
    func test_engine_rejects_missing_model_RT1_4() {
        let badPath = URL(fileURLWithPath: "/nonexistent/model.safetensors")
        #expect(throws: YapperError.modelNotFound(path: badPath.path)) {
            try YapperEngine(modelPath: badPath, voicesPath: Self.voicesPath)
        }
    }

    // RT-1.5: Missing voice file produces an error identifying the expected path
    @Test("RT-1.5: Missing voices directory produces descriptive error")
    func test_engine_rejects_missing_voices_RT1_5() {
        let badPath = URL(fileURLWithPath: "/nonexistent/voices")
        #expect(throws: YapperError.voicesNotFound(path: badPath.path)) {
            try YapperEngine(modelPath: Self.modelPath, voicesPath: badPath)
        }
    }

    // RT-1.6: Corrupted file produces an error distinguishable from file-not-found
    @Test("RT-1.6: Corrupted model file produces distinct error")
    func test_engine_rejects_corrupted_model_RT1_6() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("corrupted.safetensors")
        try Data("not a real safetensors file".utf8).write(to: fakePath)
        defer { try? FileManager.default.removeItem(at: fakePath) }

        do {
            _ = try YapperEngine(modelPath: fakePath, voicesPath: Self.voicesPath)
            Issue.record("Expected invalidModelFile error")
        } catch let error as YapperError {
            switch error {
            case .invalidModelFile(let path, _):
                #expect(path == fakePath.path)
            default:
                Issue.record("Expected invalidModelFile, got \(error)")
            }
        }
    }
}
