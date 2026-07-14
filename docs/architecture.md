<!-- Version: 0.6 | Last updated: 2026-07-14 -->

# Yapper - Architecture

## Overview

Yapper is a two-layer Swift system: **YapperKit** (library) and **yapper** (CLI). YapperKit owns local TTS inference, speech planning, provider boundaries, and audio output. The CLI handles document ingestion, chapter detection, engine selection, and audiobook assembly.

```
┌──────────────────────────────────────────────────┐
│                  yapper (CLI)                     │
│                                                   │
│  Document Ingestion    Chapter Detection           │
│  (pandoc, pdftotext,   (epub TOC, heading          │
│   calibre)             heuristics)                 │
│                                                   │
│  Audiobook Assembly    Voice Assignment            │
│  (ffmpeg: mp3/m4b,     (random, explicit,          │
│   chapter markers,      per-chapter)               │
│   metadata)                                        │
├──────────────────────────────────────────────────┤
│                 YapperKit                         │
│                                                   │
│  Text Chunker     Inference Engine   Audio Output  │
│  (sentence-level   (own Kokoro impl   (afplay for   │
│   splitting,        on MLX Swift)      playback,    │
│   510-token cap)                       PCM buffer   │
│                                        for files)   │
│                                                   │
│  Timestamps        Voice Registry    Mel Spectrogram│
│  (word-level,       (enumerate,       (quality      │
│   from inference)    load, filter)     comparison)  │
├──────────────────────────────────────────────────┤
│  MisakiSwift (G2P) + MLX Swift (Metal inference)  │
└──────────────────────────────────────────────────┘
```

The diagram above shows the default native Yapper engine, whose current implementation uses open-source Kokoro model weights. Kokoro is model provenance, not a public engine identity. Yapper, FAL, and OpenAI are peer engines selected for `speak`, prose conversion, script conversion, and voice preview; `yapper` remains local, offline, and the default.

## Speech planning and engine boundary

All speech engines share an open, provider-neutral preparation boundary:

1. Document ingestion and chapter detection produce ordered `Chapter` values.
2. `ProsePreprocessor` applies markup cleanup, section-break handling, emphasis quoting, dialogue-dash conversion, intra-word hyphen normalization, and `speech-substitution` replacements.
3. `SpeechPlanner` creates `PreparedSpeechChunk` values with chapter/source metadata, transformed text, adjacent context, character counts, boundary metadata, and stable hashes.
4. The selected engine synthesizes those prepared chunks.
5. Audio assembly writes the final M4A, MP3, or M4B only after required chunks have succeeded.

Chunk constraints are engine-specific. Native Yapper delegates to `TextChunker` and the Kokoro 510-token budget. FAL and OpenAI use remote character/request constraints over the same transformed prose, so provider clients never parse raw Markdown.

The synthesis boundary is local/remote neutral and not a closed engine enum:

```swift
public struct SpeechEngineID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
}

public protocol SpeechEngine: Sendable {
    var id: SpeechEngineID { get }
    var capabilities: SpeechEngineCapabilities { get }
    var executionPolicy: SpeechExecutionPolicy { get }
    func plan(_ utterance: SpeechUtterance) throws -> [PreparedSpeechChunk]
    func synthesisSignature(for chunk: PreparedSpeechChunk) throws -> SpeechSynthesisSignature
    func synthesize(_ chunk: PreparedSpeechChunk) async throws -> SpeechSynthesisAsset
}

public enum SpeechSynthesisAsset: Sendable {
    case pcm(AudioResult)
    case encodedAudio(file: URL, format: String, duration: TimeInterval?, metadata: [String: String])
}
```

`SpeechEngineRegistry` resolves open identifiers to invocation-scoped factories. `SpeechEngineSession` retains one engine instance across planned chunks. Engine-owned opaque payloads and deterministic synthesis signatures allow a future F5 implementation to add reference profiles and model settings without changing document/script parsing, audio asset types, or a closed prepared-work enum.

YapperKit owns the engine protocol, registry, planning values, built-in adapters, and audio assets. Its public synthesis path imports neither ArgumentParser nor Yams and does not discover Homebrew paths, user config, `afplay`, or `ffmpeg`. CLI and host applications inject model/resource paths, credentials, staging locations, and playback services. Legacy document/audiobook helpers that wrap macOS commands are platform-gated and report that a host adapter is required on iOS. The package declares macOS 15 and iOS 18 library support; native host applications can use the synthesis boundary without adopting the CLI.

### Remote provider behaviour

FAL generation uses `Authorization: Key ...` against the generation base URL, default `https://fal.run`, while platform/account reporting uses a separate base URL, default `https://api.fal.ai`. OpenAI generation uses `Authorization: Bearer ...` against `/v1/audio/speech`. Provider request and response bodies are typed `Codable` values.

Remote dry-run renders the conversion plan, provider settings, transformed chunks, character count, credential source types, and output path without generation calls or final audio side effects. Normal remote conversion writes a persistent staging directory next to the intended output path, stores `plan.json`, and reuses completed chunks when hashes and engine settings still match. A partial final audiobook is not presented as successful.

```text
output.m4a.yapper-stage/
├── plan.json
├── <chunk-hash>.mp3
└── chapter_1.aac
```

Regression tests stub the HTTP boundary and must not contact FAL or OpenAI. Live provider checks are operational tests only because they spend money and depend on external account state.

## Design decision: own inference layer (Option C)

We evaluated three approaches:

- **Option A:** Depend on KokoroSwift as a runtime SPM dependency
- **Option B:** Write everything from scratch, including G2P
- **Option C (chosen):** Own inference layer on MLX Swift, use MisakiSwift for G2P

### Why Option C

**MisakiSwift for G2P:** Grapheme-to-phoneme is the most complex component - lexicon dictionaries, a BART fallback neural network for out-of-vocabulary words, NLP POS tagging via Apple's NaturalLanguage framework. MisakiSwift is well-maintained, cleanly isolated, and Apache 2.0. No reason to reimplement.

**Own inference layer:** KokoroSwift's `generateAudio` is synchronous - it runs the full pipeline and returns all PCM samples at once. There is no callback, no async/await, and no way to get partial results. Writing our own inference code on MLX Swift, using KokoroSwift as a reference, gives us full control over chunking and streaming from the start.

**What we're not gaining:** There is no meaningful performance difference between using KokoroSwift and our own inference - both hit the same MLX Swift -> Metal backend. The motivation is architectural control, not speed.

**Validation:** After implementation, intermediate tensor comparison confirms our pipeline produces output numerically identical to KokoroSwift at every stage (BERT, duration, prosody, final audio).

## Model constraints

These are properties of the Kokoro-82M model itself, not implementation choices.

### 510-token limit

The model uses a BERT text encoder with a fixed positional embedding table of 512 positions (2 reserved for special tokens -> 510 usable). Input beyond 510 phoneme tokens produces garbage. In practice, 510 phoneme tokens ≈ 2-4 sentences of English. Any text longer than this must be chunked externally.

### Non-autoregressive generation

Kokoro predicts all audio frames in a single forward pass. The pipeline is:

```
text -> G2P -> phonemes -> BERT encoding -> duration prediction ->
prosody prediction -> decoder -> full spectrogram -> iSTFT -> all PCM samples
```

There is no natural streaming point mid-inference. Each call produces the complete waveform for its input.

### Pseudo-streaming strategy

To achieve perceived real-time playback:

1. Split input text at sentence boundaries (using `NLTokenizer` with `.sentence` unit)
2. Greedily batch consecutive sentences into chunks that fit within the 510-token budget
3. In natural prose mode, treat blank-line paragraph breaks as soft pacing markers rather than mandatory synthesis boundaries
4. In paragraph-bounded mode, preserve blank-line boundaries for script-like synthesis where structural separation matters
5. For live playback: generate each chunk, push PCM to `AVAudioEngine` immediately, start generating the next chunk while the current one plays
6. For file output: generate all chunks sequentially, concatenate PCM buffers

## YapperKit

### Responsibilities

- Load Kokoro-82M model weights (`.safetensors`) via MLX Swift
- Load voice embeddings from individual `.safetensors` files (v1.0 format)
- Run inference: text -> MisakiSwift G2P -> BERT encoding -> duration/prosody prediction -> decoder -> iSTFT -> PCM
- Chunk long text into ≤510-token segments at sentence boundaries
- Plan local and API-backed speech chunks after shared prose preprocessing
- Register or inject speech engines through the public open engine boundary
- Resolve remote credential source metadata without exposing secret values
- Manage voice selection (enumerate, load, filter by accent/gender)
- Provide word-level timestamps for each utterance
- Output raw PCM audio (`[Float]`, 24kHz, mono)
- Stream audio to system output via AVAudioEngine (for live playback)

### Inference pipeline (internal)

```
Input text
    │
    ▼
MisakiSwift G2P ──-> phoneme string + word tokens
    │
    ▼
Tokeniser ──-> phoneme token IDs (vocab lookup)
    │
    ▼
BERT (ALBERT with weight sharing, 12 layers) ──-> hidden states [batch, seq, 768]
    │
    ▼
BERT Projection (Linear 768->512) ──-> [batch, 512, seq]
    │
    ▼
Duration Encoder (3× BiLSTM + AdaLayerNorm) ──-> [batch, seq, 640]
    │
    ▼
Duration Predictor (BiLSTM + sigmoid projection) ──-> per-phoneme durations
    │
    ▼
Alignment matrix (one-hot) ──-> [batch, seq, totalFrames]
    │
    ▼
Prosody Predictor (shared BiLSTM -> F0/N branches with AdainResBlk1d) ──-> F0, N curves
    │
    ▼
Text Encoder (Embedding + CNN + BiLSTM) ──-> ASR features
    │
    ▼
Decoder (AdainResBlk1d blocks + HiFi-GAN Generator + iSTFT) ──-> PCM audio
    │
    ▼
Word timestamps (from predicted durations, divisor 80.0)
```

### Key types

```swift
// Core engine
public class YapperEngine {
    public init(modelPath: URL, voicesPath: URL) throws
    public func synthesize(text: String, voice: Voice, speed: Float) throws -> AudioResult
    public func stream(text: String, voice: Voice, speed: Float, onChunk: (AudioChunk) -> Void) throws
}

// Audio output
public struct AudioResult {
    public let samples: [Float]       // PCM, 24kHz mono
    public let sampleRate: Int        // 24000
    public let timestamps: [WordTimestamp]
}

public struct AudioChunk {
    public let samples: [Float]
    public let timestamps: [WordTimestamp]
    public let isLast: Bool
}

public struct WordTimestamp {
    public let word: String
    public let startTime: Double      // seconds
    public let endTime: Double        // seconds
}

// Voice management
public struct Voice {
    public let name: String           // e.g. "af_heart"
    public let accent: Accent         // .american, .british
    public let gender: Gender         // .female, .male
}

public class VoiceRegistry {
    public func list(filter: VoiceFilter?) -> [Voice]
    public func random(filter: VoiceFilter?, seed: UInt64) -> Voice?
    public func load(name: String) throws -> MLXArray
}

// Live playback
public class AudioPlayer {
    public func scheduleBuffer(_ samples: [Float]) throws
    public func play() throws
    public func pause()
    public func resume() throws
    public func stop()
}
```

### Model and voice file locations

```
~/.local/share/yapper/
├── models/
│   ├── kokoro-v1_0.safetensors     # MLX bf16 model weights (327MB)
│   └── config.json                  # Model configuration
└── voices/
    ├── af_heart.safetensors          # Individual voice embeddings (~522KB each)
    ├── af_bella.safetensors
    ├── am_adam.safetensors
    ├── bf_emma.safetensors
    ├── bm_daniel.safetensors
    └── ...                           # 28 voices available in Kokoro v1.0
```

Voice embeddings are individual `.safetensors` files (v1.0 format), shape `[510, 1, 256]`. This differs from the older bundled `.npz` format used by KokoroSwift's test app.

## CLI (yapper)

### Responsibilities

- Parse CLI arguments (via swift-argument-parser)
- Convert input documents to plain text (calling external tools)
- Detect chapter structure
- Assign voices to chapters
- Call YapperKit for synthesis
- Encode output audio (mp3/m4b via ffmpeg)
- Embed metadata (title, author, chapter markers, cover art)

### Document conversion pipeline

```
Input file
    │
    ├── .epub ──-> native epub parser (extract chapters + metadata)
    ├── .mobi ──-> ebook-convert (Calibre) -> .epub -> native parser
    ├── .pdf  ──-> pdftotext (poppler) -> plain text (OCR fallback: TODO)
    ├── .docx ──-> pandoc -> plain text
    ├── .odt  ──-> pandoc -> plain text
    ├── .html ──-> pandoc -> plain text
    ├── .md   ──-> pandoc -> plain text
    └── .txt  ──-> direct read
         │
         ▼
    Chapter list: [(title: String, text: String)]
         │
         ▼
    Voice assignment (random/explicit per chapter)
         │
         ▼
    YapperKit synthesis (per chapter)
         │
         ▼
    Audio encoding (ffmpeg)
         │
         ├── .m4a -> one file per chapter/input, with MP4 metadata
         ├── .mp3 -> one file per chapter/input, with ID3 tags
         └── .m4b -> single audiobook file with chapter markers
```

### Output format determines file topology

The output format controls whether `yapper convert` produces one file or many. This replaces the behaviour of `make-audiobook`.

| Output format | File count | When used |
|---|---|---|
| M4B | 1 file with chapter markers | User explicitly requests M4B, or single multi-chapter input defaults to it |
| M4A | 1 file per chapter or per input | Default for multiple independent input files; per-chapter for multi-chapter inputs |
| MP3 | 1 file per chapter or per input | Same as M4A but MP3 encoding |

### Metadata convention

Metadata applies to all output formats, not just M4B. The mappings follow established audiobook tooling conventions (inherited from make-audiobook):

| Source | M4B | M4A | MP3 (ID3) |
|---|---|---|---|
| `--author` / interactive prompt | author | artist | artist |
| `--title` / interactive prompt | title | album | album |
| Chapter number (position) | chapter marker index | track number (n/total) | track number (n/total) |
| Chapter name (TOC / heading / filename) | chapter title | track title | title |

Interactive metadata prompts (author, title) appear when stdin is a TTY, regardless of output format.

### External tool dependencies

| Tool | Used for | Required? |
|---|---|---|
| `ffmpeg` | Audio encoding (PCM->MP3, AAC, M4B assembly) | Yes (for file output) |
| `pandoc` | docx/odt/md/html -> plain text | Yes (for those formats) |
| `pdftotext` | PDF -> plain text | Yes (for PDF) |
| `ebook-convert` | mobi -> epub | Only for .mobi input |

For live playback (`yapper speak`), no external tools are needed.

## Swift Package structure

```
yapper/
├── Package.swift
├── Sources/
│   ├── YapperKit/
│   │   ├── Engine/
│   │   │   ├── YapperEngine.swift
│   │   │   └── TextChunker.swift
│   │   ├── Inference/
│   │   │   ├── KokoroPipeline.swift
│   │   │   ├── KokoroConfig.swift
│   │   │   ├── WeightLoader.swift
│   │   │   ├── MisakiG2P.swift
│   │   │   ├── BERTEncoder.swift
│   │   │   ├── DurationPredictor.swift
│   │   │   ├── ProsodyPredictor.swift
│   │   │   ├── TextEncoder.swift
│   │   │   ├── Decoder.swift
│   │   │   ├── STFT.swift
│   │   │   └── BuildingBlocks/
│   │   │       ├── LSTM.swift
│   │   │       ├── ConvWeighted.swift
│   │   │       ├── AdaIN1d.swift
│   │   │       ├── AdaLayerNorm.swift
│   │   │       ├── AdainResBlk1d.swift
│   │   │       ├── AdaINResBlock1.swift
│   │   │       └── LayerNormInference.swift
│   │   ├── Voice/
│   │   │   ├── Voice.swift
│   │   │   └── VoiceRegistry.swift
│   │   ├── Audio/
│   │   │   ├── AudioResult.swift
│   │   │   ├── AudioPlayer.swift
│   │   │   └── MelSpectrogram.swift
│   │   ├── Timestamps/
│   │   │   └── WordTimestamp.swift
│   │   └── Version.swift
│   └── yapper/
│       ├── Yapper.swift              # Entry point + yap argv[0] dispatch
│       └── Commands/
│           ├── SpeakCommand.swift
│           ├── VoicesCommand.swift
│           ├── ConvertCommand.swift
│           └── Defaults.swift        # Model/voice path resolution
├── Tests/
│   ├── regression/
│   │   ├── YapperKitTests/           # Release-safe Swift framework tests
│   │   └── cli/                      # Fast release-safe CLI smoke
│   │       ├── harness.sh
│   │       └── test_release_cli.sh   # dry-run/listing smoke
│   └── one_off/                      # Per-issue, real synthesis, playback, and integration tests
│       ├── YapperKitIntegration/     # Swift one-off/integration tests
│       └── cli/                      # CLI one-off/integration scripts
├── Formula/
│   └── yapper.rb                     # Homebrew formula (regenerated by make release)
├── scripts/
│   ├── release.sh                    # Build, sign, notarise, tag, push, update tap
│   ├── release-models.sh             # Package model weights + voices to models-v1
│   └── verify-signature.sh           # Post-build codesign verification
├── Makefile
└── docs/
```

## Build system

**`xcodebuild` is required** - not `swift build`. MLX Swift includes `.metal` shader files that only Xcode's build system can compile. `swift build` succeeds for compilation but the Metal shaders are missing at runtime, causing `Failed to load the default metallib` crashes.

### Makefile targets

| Target | What it does |
|---|---|
| `make dev-prereqs` | Check/run Xcode first-launch setup and install the Metal Toolchain when absent |
| `make build` | `make dev-prereqs` + `xcodebuild build` + MisakiSwift bundle copy |
| `make test` | `make test-framework` + `make test-cli` |
| `make test-framework` | lint + release-safe xcodebuild Swift framework tests |
| `make test-cli` | build + fast, release-safe CLI smoke tests |
| `make test-one-off` | Swift and CLI one-off tests, including real synthesis/playback |
| `make test-one-off-swift` | Swift one-off tests, including real synthesis/integration |
| `make test-one-off-cli` | CLI one-off tests, including real synthesis/playback |
| `make test-audio` | alias for `make test-one-off-cli` |
| `make test-all` | release-safe tests plus one-off tests |
| `make install` | Wrapper scripts to `~/.local/bin/yapper` and `~/.local/bin/yap` |
| `make sync` | Git sync: submodules first (if present), then parent repo |
| `make release` | Run tests, build, sign, notarise, tag, push, update Homebrew formula |
| `make release SKIP_TESTS=1` | Same but skip release-safe tests |
| `make release-models` | Package and upload model weights + voices to models-v1 release |

### Install topology

`make install` writes wrapper scripts, NOT symlinks. On modern macOS, `Bundle.main.bundleURL` resolves to the caller's invocation path, not through symlinks. A symlink at `~/.local/bin/yapper` would cause MLX to look for its resource bundles in `~/.local/bin/` instead of in the DerivedData build directory where they live. The wrapper scripts use `exec` to replace the shell with the real binary, anchoring `_NSGetExecutablePath` to the correct directory.

The `yap` wrapper uses `exec -a yap` to set `argv[0]="yap"` while executing the same binary. The binary's own dispatch code (in `Yapper.swift`) detects `argv[0]=="yap"` and prepends `speak` to the argument list.

### Test architecture

- **Release-safe Swift framework tests** (`Tests/regression/YapperKitTests/`): deterministic in-process tests of YapperKit library types that do not perform real synthesis or playback. Run via xcodebuild.
- **Release-safe CLI smoke tests** (`Tests/regression/cli/test_release_cli.sh`): fast dry-run/listing checks used by `make test` and therefore by `make release`.
- **One-off Swift integration tests** (`Tests/one_off/YapperKitIntegration/`): real synthesis, playback-state, process-wrapper, and external-tool checks. Run with `make test-one-off-swift` or `make test-one-off`.
- **One-off CLI integration tests** (`Tests/one_off/cli/`): subprocess tests that may perform real MLX synthesis, playback, timing, ffmpeg/ffprobe checks, and script conversion. Run with `make test-one-off-cli`, `make test-audio`, or `make test-one-off`.

### MisakiSwift resource bundle workaround

MisakiSwift is statically linked (via a fork with `type: .dynamic` removed). Its resource bundle (G2P lexicons) must be manually copied into the framework directory after building. The Makefile handles this automatically in the `build` and `test-framework` targets.

### Metal Toolchain

Must be installed once: `xcodebuild -downloadComponent MetalToolchain`

## Platform constraints

- **macOS 15+ (Sequoia)** - required by MisakiSwift
- **iOS 18+** - YapperKit is portable (Package.swift declares both platforms)
- **Apple Silicon only** - MLX does not run on Intel
- **Swift 6.2** - swift-tools-version 6.2 used by MisakiSwift

## Performance considerations

- Kokoro-82M at bf16: ~327MB model, ~522KB per voice
- Inference for "Hello, this is a test." takes ~5-6 seconds on first run (includes model init), ~2 seconds for subsequent calls
- Chunking at sentence boundaries keeps per-inference latency manageable
- MLX Swift's lazy evaluation means tensor operations are batched and executed on Metal GPU

## Key lessons from Phase 1

1. **MLX conv1d is channels-last** - the pipeline operates channels-first (matching PyTorch). All conv wrappers transpose input/output internally.
2. **ConvTranspose1d weight layout** differs between PyTorch and MLX, and between grouped/depthwise and regular convolutions.
3. **AdainResBlk1d shortcut vs residual paths** use different upsampling methods: shortcut = nearest-neighbour, residual = transposed conv + padding.
4. **Voice embeddings changed format** in Kokoro v1.0: individual `.safetensors` `[510, 1, 256]` instead of bundled `.npz` `[510, 2, 256]`.
5. **MLX is not thread-safe** for concurrent tensor operations - test suites must use `@Suite(.serialized)`.
6. **MisakiSwift's resource bundle** must be manually copied into the framework for tests.

## Distribution

### Homebrew formula

`brew install tigger04/tap/yapper` downloads a prebuilt binary tarball (`yapper-macos-arm64.tar.gz`) from the GitHub release, plus model weights and English voices from a separate `models-v1` release. The formula installs:

- `libexec/yapper` - the signed binary
- `libexec/*.bundle` - three Swift resource bundles (MLX metallib, MisakiSwift lexicons, ZIPFoundation)
- `bin/yapper` - wrapper script (`exec` to libexec)
- `bin/yap` - wrapper script (`exec -a yap` to libexec)
- `share/yapper/models/` - Kokoro-82M weights
- `share/yapper/voices/` - 28 English voice embeddings

### Release pipeline (`make release`)

1. Run release-safe tests (unless `SKIP_TESTS=1`)
2. Select a release version. All project `make release` behaviour must treat tag uniqueness as a prerequisite: automatic patch bumps must skip any tag that already exists locally or on `origin`; explicit `VERSION=` values fail fast if their tag already exists.
3. Bump version in `Sources/YapperKit/Version.swift`
4. Build release binary via xcodebuild
5. Developer ID codesign (inside-out: bundles first, then binary) with hardened runtime + secure timestamp
6. Submit to Apple notary service, wait for `status: Accepted`
7. Run `scripts/verify-signature.sh` as pre-upload gate
8. Runtime wrapper smoke test through staged wrapper scripts; real synthesis is skipped when `SKIP_TESTS=1`
9. Tar and upload binary asset to the GitHub release
10. Post-upload: re-download and re-verify the uploaded asset
11. Rewrite `Formula/yapper.rb` with fresh SHA256 and version
12. Push formula to `tigger04/homebrew-tap`

### Signing and notarisation

- Identity: Developer ID Application certificate, auto-discovered from the login keychain
- Keychain profile: `yapper-notary` (stores Apple ID, team ID, app-specific password)
- Stapling is not possible for bare Mach-O binaries (only `.app`, `.dmg`, `.pkg`). Gatekeeper does an online notarisation lookup on first launch for direct-download users. Homebrew users are unaffected (brew strips the quarantine xattr).

---

## Changelog

- 0.1 (2026-04-02): Initial architecture document
- 0.2 (2026-04-02): Option C decision
- 0.3 (2026-04-03): Added conversion pipeline, external dependencies, format topology
- 0.4 (2026-04-06): Updated overview diagram (afplay), package structure (CLI commands, bash tests, scripts, Formula), build system (Makefile targets, install topology, test architecture), added distribution section
- 0.3 (2026-04-03): Phase 1 complete. Updated to reflect actual implementation: package structure matches reality, key types match code, added build system section, key lessons learned, voice format discovery.
