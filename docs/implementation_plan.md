<!-- Version: 0.5 | Last updated: 2026-04-06 -->

# Yapper - Implementation Plan

## Phasing

Work is divided into issues. Each issue is self-contained with its own ACs and tests. Issues are ordered by dependency - later issues build on earlier ones.

## Phase 1: Foundation ✅ (v0.1.0-v0.3.0)

All Phase 1 work is complete.

### [Issue #1](https://github.com/tigger04/yapper/issues/1) - Project scaffolding + model/voice loading ✅

- Swift Package with `YapperKit` (library) and `yapper` (executable) targets
- Dependencies: MisakiSwift 1.0.6, MLX Swift 0.30.2, swift-argument-parser 1.7.1
- `xcodebuild` required for Metal shader compilation (not `swift build`)
- VoiceRegistry loads individual `.safetensors` voice files (v1.0 format, not `.npz`)
- Makefile with build, test, install, uninstall targets
- 13 automated tests

### [Issue #2](https://github.com/tigger04/yapper/issues/2) - Inference engine + text chunking + live playback ✅

- Full Kokoro-82M inference pipeline: BERT -> duration -> prosody -> text encoder -> decoder -> iSTFT
- 17 inference source files + 7 building block files
- TextChunker: sentence-boundary splitting with 510-token budget
- AudioPlayer: AVAudioEngine streaming with pause/resume/stop
- Word-level timestamps from predicted phoneme durations
- Speed control (0.5x-2.0x)
- 19 automated tests

### [Issue #3](https://github.com/tigger04/yapper/issues/3) - Audio wobble fix ✅

- Root cause: two bugs in AdainResBlk1d (shortcut upsample method + missing padding)
- Intermediate tensors now numerically identical to KokoroSwift at every stage
- Mel-spectrogram comparison infrastructure for regression guarding
- A/B comparison tests against kokoro-tts
- 7 automated tests

## Phase 2: CLI - Core Commands ✅ (v0.4.0-v0.7.0)

All Phase 2 work is complete.

### [Issue #4](https://github.com/tigger04/yapper/issues/4) - `yapper speak` command ✅

- `yapper speak "text"` - speak the argument
- `echo "text" | yapper speak` - speak from stdin
- `yapper speak < file.txt` - speak from file redirect
- `--voice NAME` and `--speed FLOAT` flags
- Playback via afplay (temp WAV)
- 14 automated tests

### [Issue #5](https://github.com/tigger04/yapper/issues/5) - `yapper voices` command ✅

- `yapper voices` - list all voices with name, accent, gender
- `yapper voices --preview NAME` - speak a sample sentence with the named voice
- 8 automated tests

### [Issue #6](https://github.com/tigger04/yapper/issues/6) - Plain text to audio file ✅

- `yapper convert input.txt -o output.m4a`
- Default format: M4A (AAC). MP3 available via `--format mp3`
- ID3 tags: `--author`, `--title` flags
- Existing output files backed up (.bak, .1.bak, .2.bak)
- Multiple input files, `--dry-run`, non-UTF-8/empty rejection
- 25 automated tests

### [Issue #7](https://github.com/tigger04/yapper/issues/7) - Epub parsing and chapter detection ✅

- Native epub parser: OPF manifest, spine, TOC (NCX + nav)
- Epub 2 and epub 3 support
- HTML stripping, entity decoding, metadata extraction
- Edge cases: no-TOC, missing metadata, invalid ZIP, zero-byte
- 21 automated tests

### [Issue #8](https://github.com/tigger04/yapper/issues/8) - Document conversion pipeline ✅

- PDF (pdftotext), docx/odt (pandoc), md/html (h1 splitting), txt (ALL CAPS heuristics), mobi (ebook-convert)
- Case-insensitive extension dispatch, YAML frontmatter stripping
- Missing tool errors with install hints
- 18 automated tests

### [Issue #9](https://github.com/tigger04/yapper/issues/9) - Audiobook generation ✅

- M4B with chapter markers, voice-per-chapter, metadata, progress on stderr
- Default M4B for multi-chapter, M4A for single-chapter
- Track numbers from chapter order or filename digits
- Interactive metadata prompts (TTY-aware)
- Validated: chapter markers display in Apple Books
- 14 automated tests

**Total at v0.7.0: ~110 automated tests**

## Packaging and distribution (v0.8.0-v0.8.6)

### [Issue #10](https://github.com/tigger04/yapper/issues/10) - Standalone CLI binary ✅

- Resolved by switching MisakiSwift to static linking (forked with `type: .dynamic` removed)
- Upstream PR: [mlalma/MisakiSwift#13](https://github.com/mlalma/MisakiSwift/pull/13)

### [Issue #11](https://github.com/tigger04/yapper/issues/11) - Homebrew formula ✅

- Prebuilt binary formula (source-build blocked by macOS 26 + Xcode 26 + Homebrew nested sandbox)
- `scripts/release.sh` automates: build, sign, notarise, tag, push, update tap formula
- `scripts/release-models.sh` packages model weights + English voices to models-v1 release
- Binary + resource bundles in libexec, wrapper scripts in bin (not symlinks - Bundle.main constraint)
- `brew install tigger04/tap/yapper`

### [Issue #13](https://github.com/tigger04/yapper/issues/13) - Developer ID signing + Apple notarisation ✅

- Developer ID Application certificate + `yapper-notary` keychain profile
- Inside-out codesign (bundles first, then binary), hardened runtime, secure timestamp
- `xcrun notarytool submit --wait`, pre- and post-upload verification via `scripts/verify-signature.sh`
- Runtime synthesis smoke test in release pipeline catches install-topology bugs before shipping

### [Issue #14](https://github.com/tigger04/yapper/issues/14) - `yap` shorthand command ✅

- `yap` is shorthand for `yapper speak` via argv[0] dispatch in `Sources/yapper/Yapper.swift`
- `bin/yap` wrapper uses `exec -a yap` to set argv[0] while exec'ing the real libexec binary

### [Issue #15](https://github.com/tigger04/yapper/issues/15) - Voice selection precedence ✅

- Resolution order: `--voice` flag > `$YAPPER_VOICE` env var > random selection
- `--dry-run` flag on `yapper speak` reports resolved parameters without synthesis
- Dry-run path skips 327 MB model load (loads voice registry only)

### [Issue #17](https://github.com/tigger04/yapper/issues/17) - CLI test suite rewrite ✅

- All CLI tests rewritten as bash scripts invoking the real binary (not in-process Swift)
- 80 bash CLI tests in `Tests/regression/cli/`
- Exposed and fixed: ffmpeg SIGTTIN deadlock (#19), multi-input format topology bug, output directory validation

### [Issue #19](https://github.com/tigger04/yapper/issues/19) - ffmpeg SIGTTIN deadlock fix ✅

- `standardInput = FileHandle.nullDevice` on all ffmpeg subprocess calls

**Total at v0.8.6: 168 automated tests (88 Swift framework + 80 bash CLI before the later release-safe/one-off split)**

## In progress

### [Issue #18](https://github.com/tigger04/yapper/issues/18) - Progress indicator during conversion

- Terminal progress feedback for `yapper convert` (unless `--quiet`)

### [Issue #20](https://github.com/tigger04/yapper/issues/20) - make-audiobook delta

- Metadata on all output formats (artist, album_artist, album, track number, track title)
- Text cleanup after pandoc extraction (strip HTML, markdown images, `{...}` blocks, `:::` directives)
- `--dry-run` shows cleaned text before synthesis
- Batch summary (successes/failures)
- `--non-interactive` flag
- Track numbers derived from filename integer sequences
- Partially implemented, tests written

### [Issue #12](https://github.com/tigger04/yapper/issues/12) - Multi-language voice support

- 54 voices across 8 languages downloaded, 28 English currently recognized
- Pending G2P investigation for non-English languages

### [Issue #16](https://github.com/tigger04/yapper/issues/16) - Config file support [deferred]

- Tracking issue for persistent settings (pronunciation overrides, audiobook presets)
- Deferred until a second use case justifies the infrastructure

## Future

### Clipboard and screen selection reading

- `yapper speak --clipboard` reads `NSPasteboard.general` and speaks it
- `yapper speak --selection` reads selected text via macOS Accessibility APIs

### YapperKit public API stabilization

- Review and finalize public API surface
- Documentation comments on all public types and methods
- Consider independent versioning (separate release cadence from CLI)

### Resumable audiobook generation

- Save synthesis state after each chapter
- `yapper convert --resume` picks up where a failed/interrupted generation left off

### iOS support

- YapperKit is portable (no macOS-specific APIs)
- Requires packaging as an xcframework or SPM-compatible module

## Scope summary

| Phase | Issues | Status | What you get |
|---|---|---|---|
| Phase 1 (Foundation) | [#1](https://github.com/tigger04/yapper/issues/1)-[#3](https://github.com/tigger04/yapper/issues/3) | ✅ v0.3.0 | YapperKit synthesizes text to audio, numerically identical to KokoroSwift |
| Phase 2 (CLI Core) | [#4](https://github.com/tigger04/yapper/issues/4)-[#9](https://github.com/tigger04/yapper/issues/9) | ✅ v0.7.0 | Audiobook generation CLI |
| Packaging | [#10](https://github.com/tigger04/yapper/issues/10)-[#15](https://github.com/tigger04/yapper/issues/15), [#17](https://github.com/tigger04/yapper/issues/17), [#19](https://github.com/tigger04/yapper/issues/19) | ✅ v0.8.6 | Homebrew distribution, notarised, `yap` shorthand, voice selection, test rewrite |
| make-audiobook parity | [#20](https://github.com/tigger04/yapper/issues/20) | In progress | Metadata, text cleanup, batch summary, track numbers |
| Future | [#12](https://github.com/tigger04/yapper/issues/12), [#16](https://github.com/tigger04/yapper/issues/16), [#18](https://github.com/tigger04/yapper/issues/18), TBD | Planned | Multi-language, config, progress, clipboard, iOS |

---

## Changelog

- 0.1 (2026-04-02): Initial implementation plan
- 0.2 (2026-04-02): Updated for Option C - own inference layer
- 0.3 (2026-04-03): Phase 1 complete
- 0.4 (2026-04-04): Phase 2 complete. All issue links added. Phase 3/4 issue numbers TBD.
- 0.5 (2026-04-06): Added packaging/distribution phase (#10-#19), updated scope summary, current test counts.
