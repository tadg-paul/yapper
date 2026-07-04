// ABOUTME: Core TTS engine. Loads Kokoro-82M model weights and orchestrates inference.
// ABOUTME: Entry point for all YapperKit synthesis operations.

import Foundation
import MLX

/// Errors that can occur during YapperKit operations.
public enum YapperError: Error, Equatable {
    case modelNotFound(path: String)
    case voicesNotFound(path: String)
    case invalidModelFile(path: String, message: String)
    case invalidVoicesFile(path: String, message: String)
    case audioError(message: String)
    case synthesisError(message: String)
}

/// Core TTS engine. Loads the Kokoro-82M model and voice embeddings,
/// then synthesises text to audio.
public class YapperEngine {
    let weights: [String: MLXArray]
    public let voiceRegistry: VoiceRegistry
    private lazy var pipeline: KokoroPipeline = KokoroPipeline(weights: self.weights)
    private let chunker: TextChunker

    /// Initialise the engine with paths to the model weights and voice directory.
    ///
    /// - Parameters:
    ///   - modelPath: Path to the kokoro-v1_0.safetensors file
    ///   - voicesPath: Path to the directory containing individual voice .safetensors files
    /// - Throws: `YapperError` if files are missing, inaccessible, or invalid
    public init(modelPath: URL, voicesPath: URL) throws {
        // Validate model file exists
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw YapperError.modelNotFound(path: modelPath.path)
        }

        // Validate voices directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: voicesPath.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw YapperError.voicesNotFound(path: voicesPath.path)
        }

        // Load and transform model weights
        do {
            self.weights = try WeightLoader.load(from: modelPath)
        } catch let error as YapperError {
            throw error
        } catch {
            throw YapperError.invalidModelFile(
                path: modelPath.path,
                message: error.localizedDescription
            )
        }

        // Load voice registry
        self.voiceRegistry = try VoiceRegistry(voicesPath: voicesPath)

        // Initialise text chunker (pipeline is lazy — created on first synthesis)
        self.chunker = TextChunker()
    }

    /// Synthesise text to PCM audio.
    ///
    /// Handles text of any length by chunking at sentence boundaries.
    ///
    /// - Parameters:
    ///   - text: Input text to synthesise
    ///   - voice: Voice to use
    ///   - speed: Speed multiplier (1.0 = normal, 2.0 = twice as fast)
    /// - Returns: AudioResult with PCM samples at 24kHz and word timestamps
    public func synthesize(
        text: String,
        voice: Voice,
        speed: Float = 1.0,
        chunkingPolicy: TextChunkingPolicy = .naturalProse
    ) throws -> AudioResult {
        let voiceEmbedding = try voiceRegistry.load(name: voice.name)
        let chunks = chunker.chunk(text, policy: chunkingPolicy)

        var allSamples: [Float] = []
        var allTimestamps: [WordTimestamp] = []
        var timeOffset: Double = 0.0

        for chunk in chunks {
            let (samples, timestamps) = try pipeline.synthesise(
                text: chunk.text,
                voiceEmbedding: voiceEmbedding,
                accent: voice.accent,
                speed: speed
            )

            allSamples.append(contentsOf: samples)

            // Offset timestamps by cumulative duration of previous chunks
            let offsetTimestamps = timestamps.map { ts in
                WordTimestamp(
                    word: ts.word,
                    startTime: ts.startTime + timeOffset,
                    endTime: ts.endTime + timeOffset
                )
            }
            allTimestamps.append(contentsOf: offsetTimestamps)

            timeOffset += Double(samples.count) / Double(KokoroPipeline.sampleRate)
        }

        return AudioResult(
            samples: allSamples,
            sampleRate: KokoroPipeline.sampleRate,
            timestamps: allTimestamps
        )
    }

    /// Stream synthesis with per-chunk callbacks.
    ///
    /// - Parameters:
    ///   - text: Input text to synthesise
    ///   - voice: Voice to use
    ///   - speed: Speed multiplier
    ///   - onChunk: Called after each chunk is synthesised
    public func stream(
        text: String,
        voice: Voice,
        speed: Float = 1.0,
        chunkingPolicy: TextChunkingPolicy = .naturalProse,
        onChunk: (AudioChunk) -> Void
    ) throws {
        let voiceEmbedding = try voiceRegistry.load(name: voice.name)
        let chunks = chunker.chunk(text, policy: chunkingPolicy)

        for (index, chunk) in chunks.enumerated() {
            let (samples, timestamps) = try pipeline.synthesise(
                text: chunk.text,
                voiceEmbedding: voiceEmbedding,
                accent: voice.accent,
                speed: speed
            )

            onChunk(AudioChunk(
                samples: samples,
                timestamps: timestamps,
                isLast: index == chunks.count - 1
            ))
        }
    }
}
