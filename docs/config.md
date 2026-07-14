<!-- Version: 1.3 | Last updated: 2026-07-14 -->

# Configuration

Yapper loads configuration from YAML files in a cascading order. This applies to all modes: `speak`, `convert`, and script conversion.

## Config cascade

Files are loaded and merged in order of precedence (later overrides earlier):

1. **Global** - `~/.config/yapper/yapper.yaml`
2. **Project** - `./yapper.yaml` or `./script.yaml` in the input file's directory
3. **Explicit config** - `--config path/to/config.yaml`

An explicit CLI setting such as `--engine`, `--voice`, or `--speed` overrides all YAML layers. Supported environment values are fallbacks below YAML and above built-in defaults. `--script-config` remains a deprecated compatibility alias for script conversion.

Keys are merged individually. A project config that sets only `yapper.speech-substitution` inherits all other keys from the global config. Maps such as substitutions, engine blocks, and character voices merge per entry; sequences such as voice pools replace lower layers. If both project files exist, `yapper.yaml` wins over the shared `script.yaml` fallback.

## Config keys

### Metadata

```yaml
title: "My Play"
subtitle: "A Drama in Two Acts"
author: "Author Name"
```

### Pronunciation

```yaml
yapper:
  speech-substitution:
    Cáit: Kawch                  # plain text replacement
    Taḋg: "/taɪɡ/"             # IPA notation (slashes denote IPA)
    Gda: Garda                  # regional term expansion
```

Applied to all text before synthesis, in all modes.

**IPA values** are wrapped in `/slashes/`. Yapper automatically converts these to the inline IPA format the G2P engine expects (`[word](/phonemes/)`). Plain text replacements are applied directly.

Substitution keys are matched case-insensitively, so one entry covers lowercase, capitalized, and uppercase occurrences in source text.

For inline IPA in source text (without config), use the bracket syntax directly: `[word](/phonemes/)`.

### Engine selection and defaults

```yaml
yapper:
  engine: yapper
  engines:
    yapper:
      voice: af_heart
      speed: 1.0
      concurrency: 3
    fal:
      endpoint: fal-ai/elevenlabs/tts/multilingual-v2
      voice: Rachel
      speed: 1.0
      concurrency: 3
      output-format: mp3_44100_128
      stability: 0.5
      similarity-boost: 0.75
      text-normalization: auto
    openai:
      model: gpt-4o-mini-tts
      voice: alloy
      speed: 1.0
      concurrency: 3
      output-format: aac
```

`yapper` is the default local engine. FAL and OpenAI are API-backed peers. Unselected unknown engine blocks are retained through config normalization and merge, allowing a registered future engine to add its own option keys without changing the root schema. Selecting an unregistered engine fails and names the registered IDs.

### API credentials

API engines use the same cascade as local synthesis. Each credential slot accepts exactly one tagged `literal` or `helper`. Helpers print the key to stdout, execute directly without shell interpolation, and resolve relative paths from the YAML file that declared them. Environment variables are fallbacks only when canonical and legacy config values are absent.

Remote speech settings live under the `yapper:` namespace because `script.yaml`/`yapper.yaml` is shared with First Folio. Provider-specific keys must not occupy the shared top-level namespace.

```yaml
yapper:
  engines:
    fal:
      credentials:
        generation:
          helper: ./secrets/fal-generation-key
        account:
          helper: ./secrets/fal-account-key
    openai:
      credentials:
        generation:
          helper: ./secrets/openai-generation-key
        admin:
          literal: replace-with-an-api-key
```

The four credential slots are independent:

| Slot | Environment | Config |
|------|-------------|--------|
| FAL generation | `FAL_KEY` | `yapper.engines.fal.credentials.generation` |
| FAL account/reporting | `FAL_ACCOUNT_KEY` | `yapper.engines.fal.credentials.account` |
| OpenAI generation | `OPENAI_API_KEY` | `yapper.engines.openai.credentials.generation` |
| OpenAI admin/reporting | `OPENAI_SERVICE_KEY`, `OPENAI_ADMIN_KEY` | `yapper.engines.openai.credentials.admin` |

Dry-run and verbose output report only the source type, such as `config literal`, `helper`, or `env`; resolved secret values are not printed. Account/admin credentials are optional reporting credentials and do not fall back to generation keys by default.

### Voice assignment (script mode)

```yaml
yapper:
  script:
    voices:
      yapper:
        auto-assign: true
        pool: []
        characters:
          ALICE: bf_emma
          BOB: bm
        narrator: bf_lily
        intro: bf_alice
      openai:
        auto-assign: false
        pool: [alloy, ash, coral]
        characters:
          ALICE: coral
          BOB: ash
        narrator: alloy
        intro: alloy
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
yapper:
  script:
    pacing:
      dialogue-speed: 1.0              # speech rate for dialogue (default: 1.0)
      stage-direction-speed: 0.9       # speech rate for stage directions (default: 1.0)
      gap-after-dialogue: 0.3          # silence after dialogue in seconds (default: 0.3)
      gap-after-stage-direction: 0.5   # silence after stage directions (default: 0.5)
      gap-after-scene: 1.0             # silence at scene boundaries (default: 1.0)
```

### Performance

```yaml
yapper:
  engines:
    yapper:
      concurrency: 3             # native worker processes
    fal:
      concurrency: 3             # bounded provider requests
```

### Legacy Yapper-owned keys

All existing keys remain operational throughout `0.x` and will be removed no earlier than `1.0` through a separate release decision. Each occurrence prints one stdout warning per source file/key naming the canonical replacement without printing secret values. Canonical values override deprecated aliases in the same layer.

| Legacy key | Replacement |
|------------|-------------|
| `speech-substitution` | `yapper.speech-substitution` |
| `auto-assign-voices` | `yapper.script.voices.yapper.auto-assign` |
| `character-voices` | `yapper.script.voices.yapper.characters` |
| `narrator-voice` | `yapper.script.voices.yapper.narrator` |
| `intro-voice` | `yapper.script.voices.yapper.intro` |
| `dialogue-speed` | `yapper.script.pacing.dialogue-speed` |
| `stage-direction-speed` | `yapper.script.pacing.stage-direction-speed` |
| `gap-after-dialogue` | `yapper.script.pacing.gap-after-dialogue` |
| `gap-after-stage-direction` | `yapper.script.pacing.gap-after-stage-direction` |
| `gap-after-scene` | `yapper.script.pacing.gap-after-scene` |
| `threads` | `yapper.engines.yapper.concurrency` |
| `yapper.voices.*` | `yapper.script.voices.yapper.*` |
| `yapper.pacing.*` | `yapper.script.pacing.*` |
| `yapper.performance.threads` | `yapper.engines.yapper.concurrency` |
| `yapper.remote-speech.fal.api-key` | `yapper.engines.fal.credentials.generation.literal` or `.helper` |
| `yapper.remote-speech.fal.account-api-key` | `yapper.engines.fal.credentials.account.literal` or `.helper` |
| `yapper.remote-speech.openai.api-key` | `yapper.engines.openai.credentials.generation.literal` or `.helper` |
| `yapper.remote-speech.openai.admin-api-key` | `yapper.engines.openai.credentials.admin.literal` or `.helper` |

## Example: global config

A minimal global config at `~/.config/yapper/yapper.yaml` for Irish English pronunciation:

```yaml
yapper:
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

render:
  stage-directions: true
  frontmatter: true
  footnotes: true
  character-table: true
  transitions: true

yapper:
  engine: yapper
  engines:
    yapper:
      voice: af_heart
      speed: 1.0
      concurrency: 3

  script:
    voices:
      yapper:
        auto-assign: true
        characters:
          KEVIN: am_adam
          NESSA: af_alloy
          CAIT: bf_emma
          BEN: bm_daniel
        narrator: bf_alice
        intro: bf_alice
    pacing:
      dialogue-speed: 1.0
      stage-direction-speed: 0.9
      gap-after-dialogue: 0.3
      gap-after-stage-direction: 0.5
      gap-after-scene: 1.0

  speech-substitution:
    Cáit: Kawch
    Taḋg: "/taɪɡ/"
    Gda: Garda

```

## Shared format

The project `script.yaml` format is shared with [First Folio](https://github.com/tadg-paul/first-folio). Top-level metadata and `render.*` are joint concerns, `yapper.*` is Yapper-owned, and `folio.*` is First Folio-owned. Each product ignores the other's namespace. Product-specific global files remain separate.
