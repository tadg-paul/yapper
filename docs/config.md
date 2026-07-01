<!-- Version: 1.0 | Last updated: 2026-04-26 -->

# Configuration

Yapper loads configuration from YAML files in a cascading order. This applies to all modes: `speak`, `convert`, and script conversion.

## Config cascade

Files are loaded and merged in order of precedence (later overrides earlier):

1. **Global** - `~/.config/yapper/yapper.yaml`
2. **Project** - `./yapper.yaml` or `./script.yaml` in the input file's directory
3. **CLI** - `--script-config path/to/config.yaml`

Keys are merged individually. A project config that sets only `speech-substitution` inherits all other keys from the global config. Dictionary keys (`character-voices`, `speech-substitution`) are merged per-entry, with higher-precedence values winning per key.

## Config keys

### Metadata

```yaml
title: "My Play"
subtitle: "A Drama in Two Acts"
author: "Author Name"
```

### Pronunciation

```yaml
speech-substitution:
  Cáit: Kawch                    # plain text replacement
  Taḋg: "/taɪɡ/"               # IPA notation (slashes denote IPA)
  Gda: Garda                    # regional term expansion
```

Applied to all text before synthesis, in all modes.

**IPA values** are wrapped in `/slashes/`. Yapper automatically converts these to the inline IPA format the G2P engine expects (`[word](/phonemes/)`). Plain text replacements are applied directly.

Substitution keys are matched case-insensitively, so one entry covers lowercase, capitalized, and uppercase occurrences in source text.

For inline IPA in source text (without config), use the bracket syntax directly: `[word](/phonemes/)`.

### Voice assignment (script mode)

```yaml
auto-assign-voices: true
character-voices:
  ALICE: bf_emma                 # explicit voice name
  BOB: bm                       # filter shorthand (British male)
narrator-voice: bf_lily          # voice for stage directions
intro-voice: bf_alice            # voice for preamble (defaults to narrator-voice)
```

### Content rendering (script mode)

```yaml
render:
  stage-directions: true         # synthesise stage directions (default: true)
  frontmatter: true              # synthesise preamble chapter (default: true)
  footnotes: true                # render footnote definitions as narrator asides (default: true)
  character-table: true          # include character descriptions in preamble (default: true)
  transitions: true              # render transitions e.g. CUT TO: (default: true)
```

### Pacing (script mode)

```yaml
dialogue-speed: 1.0              # speech rate for dialogue (default: 1.0)
stage-direction-speed: 0.9       # speech rate for stage directions (default: 1.0)
gap-after-dialogue: 0.3          # silence after dialogue in seconds (default: 0.3)
gap-after-stage-direction: 0.5   # silence after stage directions (default: 0.5)
gap-after-scene: 1.0             # silence at scene boundaries (default: 1.0)
```

### Performance

```yaml
threads: 3                       # concurrent synthesis workers (default: 3)
```

## Example: global config

A minimal global config at `~/.config/yapper/yapper.yaml` for Irish English pronunciation:

```yaml
speech-substitution:
  Taḋg: "/taɪɡ/"
  Cáit: Kawch
  Gda: Garda
  Tusla: Toosla
```

## Example: project script config

A full `script.yaml` placed alongside a play file:

```yaml
title: "About Time"
subtitle: "A Two-Act Play"
author: "Tadg Paul"

auto-assign-voices: true
character-voices:
  KEVIN: am_adam
  NESSA: af_alloy
  CAIT: bf_emma
  BEN: bm_daniel
narrator-voice: bf_alice
intro-voice: bf_alice

render:
  stage-directions: true
  frontmatter: true
  footnotes: true
  character-table: true
  transitions: true

dialogue-speed: 1.0
stage-direction-speed: 0.9
gap-after-dialogue: 0.3
gap-after-stage-direction: 0.5
gap-after-scene: 1.0

speech-substitution:
  Cáit: Kawch
  Taḋg: "/taɪɡ/"
  Gda: Garda

threads: 3
```

## Shared format

The `script.yaml` configuration format is shared with [First Folio](https://github.com/tigger04/first-folio), a companion tool that generates formatted PDF output from the same script formats. A single config file can serve both tools - yapper-specific keys (voices, gaps, speed, threads) are ignored by First Folio, and vice versa.
