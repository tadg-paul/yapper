<!-- Version: 1.0 | Last updated: 2026-04-26 -->

# Synthesis Performance Research Notes

Research conducted 2026-04-25 to explore optimization strategies for
script-to-audio conversion. The baseline problem: converting a
multi-character script to M4B is significantly slower per word than
converting the same text as prose, because each dialogue line requires a
separate `engine.synthesize()` call with full pipeline overhead.

## Test corpus

Test files are preserved in `Tests/fixtures/test-prose/` and
`Tests/fixtures/` for reproducibility.

| File | Location | Words | Lines | Description |
|------|----------|-------|-------|-------------|
| `test-txt-gap.txt` | `test-prose/` | 28 | 7 | Minimal prose with gaps |
| `test-gap.md` | `test-prose/` | 95 | 22 | Short markdown with gaps |
| `draft-poc.org` | `test-prose/` | 948 | 275 | Two scenes of a five-character play (org-mode) |
| `draft-poc.txt` | `test-prose/` | 948 | 322 | Same text as plain prose with blank lines |
| `draft-poc-strip-empty-lines.txt` | `test-prose/` | 948 | 166 | Same text as prose, blank lines removed |
| `draft-poc.md` | `test-prose/` | 1096 | 422 | Same text in markdown script format |
| `about_time.org` | `fixtures/` | ~1200 | ~300 | Full five-scene play (org-mode) |
| `quadriplegia.org` | `fixtures/` | ~2500 | ~600 | Five-scene, nine-character play |

## Baseline measurements

Manual conversion timings (Taḋg's measurements, `yapper convert`).

Note on line/word counts: in the current version, the script-mode
conversion (`draft-poc.org`) excludes the character list, outline, and
other org-mode metadata from synthesis - only dialogue, stage directions,
and scene content are rendered. The prose versions (`draft-poc.txt`, etc.) contain only the
synthesized text, so their raw file word counts match the 948 words
actually spoken. The difference in line counts between formats reflects
this: the `.org` file has fewer lines (275) because metadata lines are
excluded, while the `.txt` version has more lines (322) because blank
lines separating paragraphs are counted.

| File | Wall time | Audio | Lines | Words/s (wall) | Words/s (audio) | Wall/Audio ratio |
|------|-----------|-------|-------|----------------|-----------------|------------------|
| test-txt-gap.txt | 3.5s | 10s | 7 | 8.0 | 2.8 | 2.8 |
| test-gap.md | 9.9s | 35s | 22 | 9.6 | 2.7 | 3.5 |
| draft-poc.org | 164s | 391s | 275 | 5.8 | 2.4 | 2.4 |
| draft-poc.txt | 159.7s | 430s | 322 | 5.9 | 2.2 | 2.7 |
| draft-poc-strip-empty-lines.txt | 103s | 347s | 166 | 9.2 | 2.7 | 3.4 |

### Key observation

The same 948 words process at 9.2 words/s (wall) as dense prose vs 5.8
words/s as a script. The difference is pipeline call count: dense prose
packs sentences into fewer 510-token chunks, while script mode makes one
`synthesize()` call per dialogue line.

Early prose conversion treated blank-line paragraph breaks as mandatory
chunk splits. Stripping blank lines from the prose version reduced wall
time by 35% (159.7s to 103s) and line count from 322 to 166, confirming
that forced paragraph boundaries created extra full pipeline calls.

Current chunking policy separates those cases. Natural prose mode packs
sentences across paragraph breaks until the token budget requires a
split, while paragraph-bounded mode preserves the old hard paragraph
boundary behaviour for script-like synthesis.

## Kokoro pipeline architecture

Each `pipeline.synthesise()` call performs:

1. G2P (grapheme-to-phoneme, CPU)
2. Tokenisation (CPU)
3. Tensor preparation with BOS/EOS padding (CPU)
4. Style embedding extraction from voice (indexed by token count)
5. BERT encoding (GPU)
6. Duration encoding and prediction (GPU)
7. Alignment matrix construction
8. Prosody prediction (f0, noise) (GPU)
9. Decoder - generates audio waveform (GPU)
10. Timestamp prediction (CPU)

Steps 1-4 are CPU-bound. Steps 5-9 are GPU-bound. The model is
non-autoregressive: each chunk is processed independently with no hidden
state carried between chunks.

The minimum per-call overhead is approximately 0.3-0.5s for very short
text (e.g. "Fair." or "Not there."), dominated by GPU kernel launch and
tensor setup rather than actual inference.

## Hypotheses tested

### 1. Voice switching cost

**Hypothesis:** Switching voices between dialogue lines incurs
significant overhead.

**Result:** Negligible. Voice embeddings are cached after first load
(dictionary lookup). Measured 1.05x speedup from eliminating all voice
switches - within noise.

**Data (draft.org Scene 1, 45 entries):**

| Mode | Wall time | Voice switches |
|------|-----------|---------------|
| Scene order | 42.6s | 39 |
| Per-character batch | 40.5s | 0 |

### 2. Text packing - period-joined lines

**Hypothesis:** Joining all of one character's lines with periods into a
single `synthesize()` call reduces pipeline invocations and speeds up
synthesis.

**Result:** Faster (1.5-1.7x), but produces compressed prosody. Audio
duration is only ~56% of the sequential equivalent - the model delivers
each line as part of a continuous flow rather than as standalone
statements. Unsuitable for dramatic dialogue where each line needs
weight.

**Data (draft.org Scene 1, BEN, 14 lines):**

| Strategy | Wall time | Audio | Audio ratio |
|----------|-----------|-------|-------------|
| Sequential (14 calls) | 8.1s | 27.2s | 100% |
| Period + space (1 call) | 5.6s | 15.3s | 56% |
| Period + newline (1 call) | 5.2s | 15.3s | 56% |
| Period + double-newline (1 call) | 9.4s | 27.2s | 100% |

### 3. Separator comparison: space vs `\n` vs `\n\n`

**Hypothesis:** A single newline might provide a middle ground - some
pause signal without forcing a chunk split.

**Result:** Single `\n` behaves identically to space. The model and
chunker treat them the same. Historically, `\n\n` forced a chunk
boundary because `TextChunker.chunk()` split on blank-line paragraph
breaks as mandatory boundaries.

The current natural prose policy uses the middle ground suggested by
later listening tests: paragraph breaks are retained as metadata and
packed as ordinary sentence spacing unless the token budget requires a
split. Paragraph-bounded mode remains available for script-like
segmentation.

**Additional finding:** Period + newline chosen over period + space as
the default for packing, on the principle that `\n` may provide subtle
intonation cues even if it does not affect chunking. Same speed, no
downside.

### 4. Splicing batched audio

**Hypothesis:** Batch-synthesize each character's lines, then split the
resulting audio and reassemble in scene order.

**Result:** Even-splitting by line count cuts into words. Timestamp-based
splitting might work but is fragile. The compressed prosody from packing
makes individual lines hard to isolate cleanly.

**Conclusion:** Each line must be synthesized individually to get
standalone prosody suitable for dialogue. The assembly approach (one
audio file per line, configurable inter-line gap, M4B manifest defines
order) is the correct architecture.

### 5. In-process concurrent synthesis (threads)

**Hypothesis:** Multiple `synthesize()` calls running concurrently on
separate threads could overlap CPU and GPU work.

**Result:** Segfault. MLX Swift's Metal command buffers are not
thread-safe for concurrent inference. Naive thread-based parallelism is
not viable.

### 6. Multi-process concurrent synthesis

**Hypothesis:** Separate OS processes each get their own Metal context,
allowing true concurrent GPU access.

**Result:** Works. Each worker process loads the model independently and
synthesizes assigned lines to individual WAV files. The main process
assembles the segments in scene order.

**Data (draft.org Scene 1, 45 entries):**

| Concurrency | Wall time | Speedup |
|-------------|-----------|---------|
| Sequential | 40.6s | 1.00x |
| 2-way | 31.5s | 1.29x |
| 3-way | 24.6s | 1.65x |
| 4-way | 22.8s | 1.78x |

Diminishing returns beyond 3-way (GPU saturation on Apple Silicon).
Audio output is identical across all concurrency levels - verified by
overlaying waveforms in Audacity. Sequential produces ~0.9s more audio
over ~2 minutes due to minor model non-determinism between process
invocations.

**Trade-off:** Each worker process loads the full 82M model. Memory
usage scales linearly with concurrency. For a 3-way run, approximately
3x the base memory footprint during synthesis.

## Recommended architecture

Based on these findings, the optimal script-to-audio pipeline is:

1. Parse script into individual entries (dialogue lines + stage
   directions)
2. Spawn N worker processes (default N=3)
3. Each worker synthesizes assigned lines to individual audio files
4. Main process assembles files in scene order with configurable
   inter-line gaps
5. Encode assembled audio to M4B with chapter metadata

### Configurable parameters

Two levers identified as valuable for script audio:

- **Speed** (`--speed`): controls speech rate per line. Dialogue pacing
  varies by genre - slower for drama, faster for comedy.
- **Inter-line gap** (`--pause`): silence inserted between entries at
  assembly time. Does not require re-synthesis to adjust. Could be
  differentiated by transition type (dialogue->dialogue,
  dialogue->stage-direction, scene boundary).

### Expected performance

At 3-way concurrency, script conversion should approach prose-equivalent
throughput: ~9-10 words/s (wall) vs the current ~5.8 words/s.

## Other findings

### Stage direction character names

Character names in stage directions are ALL CAPS (e.g. "KEVIN enters"),
which causes the TTS to spell them out letter by letter. Fix: detect
known character names in stage direction text and convert to Title Case
before passing to the engine.

### LLVM profiling artefact

Debug builds leave a `default.profraw` file in the working directory on
every run. Suppressed by setting `LLVM_PROFILE_FILE=/dev/null` in the
wrapper scripts before `exec`-ing the binary. The env var must be set
before process launch - the LLVM profiling runtime reads it during
static initialization, before `main()`.

### Kokoro speed parameter

The speed parameter divides predicted phoneme durations:
`durFloat = sigmoid(logits).sum(axis: -1) / speed`. Higher values =
faster speech (conventional direction, unlike Piper which inverts it).
Speed 0.67 produces approximately 1.5x slower speech.

### Voice embedding and style

The voice embedding has shape [510, 1, 256]. Style is extracted by
indexing at `tokenCount - 1`, meaning different length inputs get
different style vectors from the same voice. This is by design - the
model adapts its prosodic style to input length.

No explicit emotion, emphasis, or SSML-style controls exist. Prosody is
inferred from text content (via BERT encoding), voice embedding, and
input length. Punctuation (`.` vs `!` vs `...`) is the primary lever for
influencing delivery within the text itself.
