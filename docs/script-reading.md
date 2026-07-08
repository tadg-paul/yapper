<!-- Version: 2.1 | Last updated: 2026-07-08 -->

# Script Reading

Yapper can convert play and screenplay scripts into multi-voice audiobooks (M4B), with distinct voices per character and narrator-read stage directions.

## Supported formats

### Org-mode (`.org`)

```org
#+TITLE: My Play
#+AUTHOR: Author Name

* Characters
|-------+---------------------|
| ALICE | A curious girl      |
| BOB   | Her quiet neighbour |
|-------+---------------------|

* Outline
Two neighbours discuss the weather.

* ACT I
** Scene 1: The Garden
*** A sunny garden. Morning.
**** ALICE
Good morning.
**** BOB softly
Is it.
*** ALICE sits down.
```

- `#+TITLE:` / `#+AUTHOR:` - metadata (used for M4B tags and audio announcement)
- `*` (L1 heading) - act or top-level section
- `**` (L2 heading) - scene boundary (becomes an M4B chapter)
- `***` (L3 heading) - stage direction
- `****` (L4 heading) - dialogue attribution (character name, optionally with acting directions)
- Body text below L4 - the dialogue itself
- `[fn:name]` - footnote reference (stripped from audio, definition read as narrator aside)
- `[fn:name] Definition text` - footnote definition (at end of file)
- Character table (`| NAME | description |`) - parsed for preamble narration

### Markdown (`.md`)

```markdown
# My Play

*by Author Name*

### Scene 1: The Garden

*A sunny garden. Morning.*

**ALICE:**
Good morning.

**BOB (softly):**
Is it.

*ALICE sits down.*
```

- `# Title` - play title
- `*by Author Name*` - author
- `### Scene Title` - scene boundary
- `*italic text*` on its own line - stage direction
- `**CHARACTER:**` or `**CHARACTER (notes):**` - dialogue attribution
- `## ACT` headings - skipped (act markers)

## Configuration

Script mode activates when a `script.yaml` file is found alongside the input file, or when `--script-config path/to/config.yaml` is specified.

For the full configuration reference, config cascade rules, and example configs, see [docs/config.md](config.md).

Script-specific config keys include voice assignment, content rendering (stage directions, preamble, footnotes), pacing (per-type speed and gaps), and performance (thread count). All keys are optional with sensible defaults.

### Script config shape

Yapper-owned script settings live under the `yapper:` namespace so `script.yaml` can remain shared with First Folio. Shared metadata and rendering controls remain top-level.

```yaml
title: "My Play"
author: "Author Name"

render:
  stage-directions: true
  frontmatter: true
  footnotes: true

yapper:
  voices:
    auto-assign: true
    characters:
      ALICE: bf_emma
      BOB: bm
    narrator: bf_lily
    intro: bf_alice
  pacing:
    dialogue-speed: 1.0
    stage-direction-speed: 0.9
    gap-after-dialogue: 0.3
  performance:
    threads: 3
```

Legacy top-level Yapper keys such as `auto-assign-voices`, `character-voices`, `narrator-voice`, `intro-voice`, pacing keys, and `threads` remain accepted for backward compatibility. Using them prints a deprecation warning naming the replacement `yapper.*` path.

### CLI flags

| Flag | Purpose |
|------|---------|
| `--script-config path` | Path to script.yaml (otherwise auto-discovered) |
| `--threads N` | Override worker process count (overrides YAML `yapper.performance.threads`) |
| `--speed N` | Global speed multiplier (multiplied with per-type speeds) |
| `--dry-run` | Preview script structure without synthesis |
| `--non-interactive` | Use metadata from script/config without prompting |

## Voice assignment

Voices are assigned to characters in three phases:

1. **Explicit voice names** - `ALICE: bf_emma` assigns a specific Kokoro voice
2. **Filter shorthands** - `BOB: bm` picks a random British male voice
3. **Auto-assignment** - remaining characters get voices from the available pool

Filter shorthand format: first character = accent (`a` American, `b` British), second character = gender (`f` female, `m` male). Either can be omitted.

Each character retains a consistent voice throughout the entire script.

## Preamble (frontmatter)

When `render.frontmatter` is enabled (the default), a preamble chapter is synthesized before the first scene containing:

1. Title and author announcement
2. Character descriptions from the character table (controlled by `render.character-table`)
3. Outline text

The preamble uses `yapper.voices.intro` if specified, otherwise falls back to `yapper.voices.narrator`.

## Footnotes

Org-mode footnotes (`[fn:name]`) are supported:

- The `[fn:name]` marker is stripped from the spoken dialogue
- The footnote definition is read as a narrator aside immediately after the referencing line
- Useful for glossary notes (e.g. Hiberno-English terms)

Set `render.footnotes: false` to strip markers without reading definitions.

## Transitions

Transitions (e.g. "CUT TO:", "FADE OUT.") are rendered using the narrator voice. The syntax varies by format:

| Format | Syntax | Example |
|--------|--------|---------|
| Org-mode | L5 heading (`*****`) | `***** FADE OUT.` |
| Markdown | Blockquote (`> `) | `> CUT TO:` |
| Fountain | Uppercase line ending in `TO:`, or forced with `>` | `CUT TO:` or `>FADE OUT.` |

Set `render.transitions: false` to exclude transitions from the output.

## Stage direction character names

Character names in stage directions are typically ALL CAPS in scripts (e.g. "KEVIN enters the room"). Yapper automatically converts these to Title Case (e.g. "Kevin enters the room") before synthesis to prevent the TTS from spelling them out letter by letter.

## Performance

Script conversion uses multi-process concurrent synthesis by default (3 worker processes). Each worker gets its own Metal context for GPU access. The thread count is configurable:

- `yapper.performance.threads: N` in script.yaml
- `--threads N` CLI flag (overrides YAML)
- `--threads 1` for sequential synthesis

Optimal thread count depends on hardware. 3 was determined as the sweet spot on M3/24GB (1.65x speedup). Diminishing returns beyond 3-4 due to GPU saturation.

Audio trimming removes model-generated leading (~280ms) and trailing (~80ms) silence from each line before assembly. When `transcribe` (from tigger04/tap/transcribe-summarize) is available, exact Whisper word timestamps are used for precise trimming. Otherwise, heuristic fixed offsets are applied.

## Metadata precedence

Title and author are resolved in order of precedence:

1. CLI flags (`--title`, `--author`)
2. `script.yaml` values
3. Script file metadata (`#+TITLE:`, `# Title`, etc.)
4. Interactive prompt input (when TTY available)

## Output

Script mode always produces M4B output with:
- One chapter per scene (plus optional preamble chapter)
- Chapter titles matching scene headings
- Title and author M4B metadata tags
