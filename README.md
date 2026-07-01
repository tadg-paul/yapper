# Yapper

Fast, Apple Silicon-native text-to-speech powered by [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) via [MLX Swift](https://github.com/ml-explore/mlx-swift). CLI tool and embeddable Swift library.

- **Runs entirely on-device** - native Swift + Metal inference, no Python, no cloud, no internet required
- **Multi-voice script reading** - convert plays and screenplays to audiobooks with distinct voices per character and narrator-read stage directions. Supports [org-mode](docs/format-org-mode.md), [markdown](docs/format-markdown.md), and [Fountain](docs/format-fountain.md) formats
- **Audiobook generation** - M4B with chapter markers and metadata from epubs, PDFs, markdown, or multiple text files in one command
- **28 built-in voices** - American and British, male and female, with voice preview and filter shorthands
- **Concurrent synthesis** - multi-process GPU parallelism for 1.65x faster script conversion
- **Configurable pacing** - per-type gaps and speech speed for dialogue, stage directions, and scene boundaries
- **Pronunciation overrides** - inline IPA and bulk substitution via [cascading YAML config](docs/config.md)
- **Script intelligence** - character name Title Case in stage directions, footnote narrator asides, preamble with cast introduction
- **Homebrew install** - Developer ID signed, Apple notarised, one command setup

## Why

High-quality text-to-speech is an accessibility technology that gives real, meaningful benefit to people with disability. It should be open source, fast, and free from commercial paywalls. Yapper exists to make that a reality on Apple Silicon.

## Quickstart

```bash
brew install tigger04/tap/yapper
```

Model weights and 28 English voices are downloaded automatically.

```bash
# Speak text aloud
yap "Hello, this is yapper."

# Convert a file to audio
yapper convert notes.txt -o notes.m4a

# Convert a play to a multi-voice audiobook
yapper convert play.org --script

# Preview all British female voices
yapper voices --preview bf
```

See [docs/cli.md](docs/cli.md) for the full CLI guide.

### Configuration

Yapper loads YAML config in a cascade: global (`~/.config/yapper/yapper.yaml`) > project (`./yapper.yaml`) > CLI (`--script-config`). Use it for pronunciation overrides, voice assignment, pacing, and more.

```yaml
# ~/.config/yapper/yapper.yaml
speech-substitution:
  Taḋg: "/taɪɡ/"
  Cáit: Kawch
```

See [docs/config.md](docs/config.md) for the full reference.

### From source

Requires Xcode 26+ with the Metal Toolchain.

```bash
git clone https://github.com/tigger04/yapper.git
cd yapper
make build
make install    # installs yapper and yap to ~/.local/bin
```

Source builds require manual download of [model weights and voices](https://huggingface.co/mlx-community/Kokoro-82M-bf16). See [docs/architecture.md](docs/architecture.md) for details.

## Requirements

- macOS 15+ (Sequoia) on Apple Silicon
- [Kokoro-82M model weights](https://huggingface.co/mlx-community/Kokoro-82M-bf16) (~327 MB, downloaded automatically by Homebrew)

Runtime tools for file conversion: `ffmpeg` (`brew install ffmpeg`), `pandoc` (`brew install pandoc`), `pdftotext` (`brew install poppler`), `ebook-convert` (install [Calibre](https://calibre-ebook.com)).

## Architecture

Yapper is structured as two layers:

- **YapperKit** - embeddable Swift TTS library (model loading, inference, streaming, voice management)
- **yapper** - CLI tool (document conversion, chapter detection, audiobook assembly, script parsing)

The inference pipeline implements the full Kokoro-82M architecture (StyleTTS2-based, 82M params, non-autoregressive) using MLX Swift for Metal-accelerated computation. See [docs/architecture.md](docs/architecture.md).

## Documentation

| Document | Description |
|----------|-------------|
| [CLI guide](docs/cli.md) | Commands, flags, examples |
| [Configuration](docs/config.md) | YAML config cascade, all keys, examples |
| [Script reading](docs/script-reading.md) | Multi-voice script conversion and pacing |
| [Org-mode format](docs/format-org-mode.md) | Org-mode script format specification |
| [Markdown format](docs/format-markdown.md) | Markdown script format specification |
| [Fountain format](docs/format-fountain.md) | Fountain screenplay format specification |
| [Architecture](docs/architecture.md) | System design, inference pipeline, build system |
| [Vision](docs/VISION.md) | Goals, use cases, future plans |
| [Research notes](docs/research_notes.md) | Synthesis performance findings |

## Features

- Full Kokoro-82M pipeline in Swift (BERT, duration/prosody, HiFi-GAN, iSTFT)
- 28 voices with preview, filter shorthands, and voice introduction
- Document conversion: epub, PDF, docx, odt, markdown, HTML, mobi, plain text
- Script reading: org-mode, markdown, Fountain with per-character voices
- M4B audiobooks with chapter markers and ID3 metadata
- Concurrent multi-process synthesis (configurable thread count)
- Configurable inter-line gaps and per-type speech speed
- Preamble rendering with cast introduction and outline
- Footnote rendering as narrator asides
- Speech substitution and inline IPA pronunciation
- Stage direction character names automatically Title Cased
- Per-line audio trimming (Whisper-based or heuristic)
- Sentence-level text chunking for arbitrarily long input
- Speed control (0.5x-2.0x) and word-level timestamps
- `--dry-run`, `--non-interactive`, `--quiet` flags
- Numerically identical output to [KokoroSwift](https://github.com/mlalma/kokoro-ios)
- Homebrew distribution: Developer ID signed, Apple notarised

**Planned:** iOS support (YapperKit is portable), GUI wrapper, multiple language support, clipboard reading.

## Makefile targets

| Target | Description |
|---|---|
| `make build` | Build via xcodebuild |
| `make test` | Run release-safe tests: Swift framework tests plus fast CLI smoke |
| `make test-audio` | Run audio/playback CLI regression tests |
| `make test-all` | Run release-safe and audio regression tests |
| `make install` | Install yapper and yap to ~/.local/bin |
| `make release` | Release-safe tests, version bump, sign, notarise, tag, push, update Homebrew |

## Acknowledgements

- [hexgrad/Kokoro](https://github.com/hexgrad/kokoro) - [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) model ([Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0))
- [mlalma/kokoro-ios](https://github.com/mlalma/kokoro-ios) - KokoroSwift reference implementation ([MIT](https://opensource.org/licenses/MIT))
- [mlalma/MisakiSwift](https://github.com/mlalma/MisakiSwift) - G2P library ([Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0))
- [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) - Apple's MLX framework ([MIT](https://opensource.org/licenses/MIT))
- [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) - CLI parsing ([Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0))

See [NOTICE](NOTICE) for full attribution details.

## Licence

Apache 2.0 - Copyright Taḋg Paul. See [LICENSE](LICENSE).
