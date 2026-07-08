<!-- Version: 1.1 | Last updated: 2026-07-08 -->

# CLI Guide

Yapper provides three commands and a shorthand:

| Command | Purpose |
|---------|---------|
| `yapper speak` | Speak text aloud through system speakers |
| `yapper convert` | Convert files to audio (M4A, MP3, M4B) |
| `yapper voices` | List and preview available voices |
| `yap` | Shorthand for `yapper speak` |

## Speaking text

```bash
# Speak text aloud
yap "Hello, this is yapper."

# Pin a specific voice
yap --voice bf_emma "Hello, this is yapper."

# Use a random voice instead of the default
yap --random-voice "Surprise me."

# Persistent voice via environment variable
export YAPPER_VOICE=bm_daniel
yap "Now I sound like Daniel every time."

# Custom pronunciation with inline IPA
yap "Hello [Taḋg](/taɪɡ/), how are you today?"

# Read from stdin
echo "Text from a pipe" | yap

# Adjust speed (0.5 = slower, 2.0 = faster)
yap --speed 0.8 "Speaking more slowly now."

# Preview without synthesis
yap --dry-run "What voice would this use?"
```

### Voice resolution

The voice is resolved from these sources, in order of priority:

1. `--voice <name>` - CLI flag, wins unconditionally
2. `$YAPPER_VOICE` - environment variable for persistent preference
3. `--random-voice` - random selection from all installed voices
4. Default - `af_heart` (highest fidelity voice)

Invalid voice names produce a clear error rather than silently falling back.

## Converting files

```bash
# Single file to M4A
yapper convert notes.txt -o notes.m4a

# Single file to MP3
yapper convert notes.txt --format mp3

# Epub to M4B audiobook with chapter markers
yapper convert book.epub -o book.m4b

# Multiple files into one audiobook
yapper convert *.md -o collection.m4b

# Specific voice for conversion
yapper convert notes.txt --voice af_heart -o notes.m4a

# Set metadata
yapper convert notes.txt --title "My Notes" --author "Me" -o notes.m4a

# Non-interactive mode (no prompts, for scripts/CI)
yapper convert book.epub --non-interactive -o book.m4b

# Preview conversion plan without synthesising
yapper convert book.epub --dry-run

# Use FAL/ElevenLabs through the native conversion planner
yapper convert chapter.md --engine fal --voice Aria --dry-run

# Use OpenAI speech through the native conversion planner
yapper convert chapter.md --engine openai --openai-model gpt-4o-mini-tts --voice alloy --dry-run
```

`--engine yapper` is the default and preserves local Kokoro synthesis. `--engine fal` and `--engine openai` reuse Yapper's document ingestion, prose preprocessing, speech substitutions, chunk planning, dry-run rendering, output naming, and audiobook assembly. Dry-run mode never calls provider generation endpoints or writes a final audio file.

Remote prose conversion uses provider-specific chunk constraints instead of Kokoro's 510-token budget. FAL chunks are prepared for the ElevenLabs multilingual endpoint and carry previous/next text context where available. OpenAI chunks respect the speech API input length limit. Script conversion remains native Yapper synthesis; script dry-run still uses the existing script preprocessing path.

Older standalone `tts-fal` and `tts-openai` shell prototypes are not the canonical implementation for Yapper text transformation, chunking, dry-run rendering, or audiobook conversion. They should be treated as deprecated wrappers or operational references; new prose conversion work belongs in `yapper convert`.

Remote credentials should normally be configured under `yapper.remote-speech` in `yapper.yaml` as inline values or executable helper paths. Environment variables are supported only as fallback when the matching YAML key is absent. The `yapper:` namespace keeps provider-specific speech settings out of the shared First Folio top-level config.

### Remote engine flags

| Flag | Engine | Purpose |
|------|--------|---------|
| `--engine yapper\|fal\|openai` | convert | Select local Yapper or remote API-backed synthesis |
| `--fal-endpoint <id>` | fal | FAL model endpoint, default `fal-ai/elevenlabs/tts/multilingual-v2` |
| `--fal-output-format <fmt>` | fal | FAL audio output format, default `mp3_44100_128` |
| `--stability <n>` | fal | ElevenLabs stability, 0...1 |
| `--similarity-boost <n>` | fal | ElevenLabs similarity boost, 0...1 |
| `--style <n>` | fal | ElevenLabs style exaggeration, 0...1 |
| `--language-code <code>` | fal | Optional provider language enforcement |
| `--text-normalization auto\|on\|off` | fal | FAL text normalization mode |
| `--openai-model <model>` | openai | OpenAI speech model, default `gpt-4o-mini-tts` |
| `--openai-format <fmt>` | openai | OpenAI response format, default `aac` |
| `--instructions <text>` | openai | Speech instructions for models that support them |

### Supported input formats

| Format | Extension | Requires |
|--------|-----------|----------|
| Plain text | `.txt` | - |
| Markdown | `.md`, `.markdown` | - |
| Epub | `.epub` | - |
| PDF | `.pdf` | `pdftotext` (poppler) |
| Word | `.docx` | `pandoc` |
| OpenDocument | `.odt` | `pandoc` |
| HTML | `.html` | `pandoc` |
| Mobi | `.mobi` | `ebook-convert` (Calibre) |

### Output formats

| Format | Extension | Notes |
|--------|-----------|-------|
| M4A | `.m4a` | Default for single files |
| M4B | `.m4b` | Default for multi-chapter input; audiobook with chapter markers |
| MP3 | `.mp3` | Via `--format mp3` |

The output format is inferred from: `--format` flag > `-o` file extension > automatic (M4B for multi-chapter, M4A otherwise).

## Script conversion

Convert plays and screenplays with distinct voices per character:

```bash
# Force script mode with defaults (no config file needed)
yapper convert play.org --script

# Auto-detect from script.yaml alongside the script file
yapper convert play.org

# Specify config explicitly
yapper convert play.fountain --script-config config.yaml

# Preview cast and structure
yapper convert play.org --script --dry-run

# Control concurrency
yapper convert play.org --threads 1
```

Supported script formats: org-mode (`.org`), markdown (`.md`), Fountain (`.fountain`). See [script-reading.md](script-reading.md) for format details.

## Voice management

```bash
# List all available voices
yapper voices

# List voice names only (scriptable)
yapper voices -1

# Preview a specific voice
yapper voices --preview bf_emma

# Preview all British female voices
yapper voices --preview bf

# Preview all voices with the full Stella passage
yapper voices --preview all --full

# Preview with custom text
yapper voices --preview am_adam "Custom text to speak."

# Preview with text from stdin
echo "Text from pipe" | yapper voices --preview bf -
```

### Filter shorthands

Voice filters use a two-character code: accent + gender.

| Code | Meaning |
|------|---------|
| `a` | American accent |
| `b` | British accent |
| `f` | Female |
| `m` | Male |

Examples: `bf` = British female, `am` = American male, `a` = any American, `f` = any female.

## Common flags

| Flag | Commands | Purpose |
|------|----------|---------|
| `--voice <name>` | speak, convert | Specific voice name (default: af_heart) |
| `--engine <name>` | convert | Speech engine: yapper, fal, openai |
| `--random-voice` | speak | Use a random voice instead of the default |
| `--speed <n>` | speak, convert | Speed multiplier (default: 1.0) |
| `--dry-run` | speak, convert | Preview without synthesis |
| `-q`, `--quiet` | speak, convert | Suppress progress output |
| `--non-interactive` | convert | Skip interactive prompts |
| `-o <path>` | convert | Output file path |
| `--format <fmt>` | convert | Output format (m4a, mp3, m4b) |
| `--script` | convert | Force script mode using defaults |
| `--threads <n>` | convert | Worker processes for script mode |
| `--script-config <path>` | convert | Path to script YAML config |
| `--title <text>` | convert | Title metadata |
| `--author <text>` | convert | Author metadata |
| `-1` | voices | One name per line |
| `--preview <spec>` | voices | Preview voice(s) |
| `--full` | voices | Full Stella passage for preview |
