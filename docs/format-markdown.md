<!-- Version: 1.0 | Last updated: 2026-04-26 -->

# Markdown Script Format Specification

This document defines how yapper interprets markdown (`.md`, `.markdown`) files as play/screenplay scripts.

## File structure

```markdown
# Play Title

*by Author Name*

## ACT I

### Scene 1: Scene Title

*Stage direction text.*

**CHARACTER:**
Dialogue text.

**CHARACTER (acting direction):**
More dialogue.

[^name]: Footnote definition text.
```

## Element mapping

| Markdown element | Yapper interpretation | ScriptDocument field |
|---|---|---|
| `# Title` | Play title (first H1 heading) | `title` |
| `*by Author Name*` | Author (italic line starting with "by") | `author` |
| `## Heading` | Act marker (skipped) | - |
| `### Scene Title` | Scene boundary | `scenes[].title` |
| `*italic text*` (full line) | Stage direction | `scenes[].entries[]` (type: `.stageDirection`) |
| `**CHARACTER:**` | Dialogue attribution | `scenes[].entries[]` (type: `.dialogue`) |
| `**CHARACTER (notes):**` | Dialogue attribution with acting direction | Character extracted, direction stripped |
| Body text below attribution | Dialogue continuation | Appended to current dialogue entry |
| `> text` (blockquote) | Transition | `scenes[].entries[]` (type: `.transition`) |
| Text before first `###` | Preamble content | `preamble` |
| `[^name]` in text | Footnote reference (stripped) | Triggers footnote aside |
| `[^name]: definition` | Footnote definition | `footnotes[name]` |

## Script detection

A markdown file is recognized as a script when:
1. The file extension is `.md` or `.markdown`
2. Script mode is selected by project config, `--script`, or the deprecated `--script-config` alias
3. At least 2 dialogue patterns (`**CHARACTER:**`) are found in the first 100 lines

The pattern check uses the regex `^\*\*[A-Z\u00C0-\u024F][^*]*:?\*\*` with anchors matching lines. This matches:
- `**BOB:**`
- `**BOB softly:**`
- `**BOB (softly):**`
- `**CÁIT:**` (accented uppercase)

## Dialogue attribution

The bold text between `**...**` is parsed to extract the character name:

| Attribution | Extracted character | Stripped direction |
|---|---|---|
| `**KEVIN:**` | KEVIN | - |
| `**KEVIN softly:**` | KEVIN | softly |
| `**KEVIN, softly:**` | KEVIN | softly |
| `**KEVIN (softly):**` | KEVIN | (softly) |
| `**GDA CONLON:**` | GDA CONLON | - |
| `**CÁIT:**` | CÁIT | - |

**Rule:** A trailing colon inside the bold markers is stripped. Character names consist of leading ALL-CAPS words. The first word containing any lowercase letter marks the start of the acting direction.

## Heading hierarchy

```markdown
# Play Title          ← H1: title (extracted as metadata, then skipped)
*by Author Name*      ← italic "by" line: author

## ACT I              ← H2: act marker (skipped, not rendered)

### Scene 1: Title    ← H3: scene boundary (becomes M4B chapter)

*Stage direction.*    ← italic full line: stage direction (narrator voice)

**CHARACTER:**        ← bold with colon: dialogue attribution
Dialogue text.        ← body: dialogue content
```

## Stage directions

Stage directions are italic lines - a line starting with `*` and ending with `*` (single asterisks, not bold):

```markdown
*A room. Morning. Empty except for a chair.*
*ALICE sits down.*
*CHARLIE enters carrying an umbrella.*
```

- The asterisks are stripped from the text before synthesis
- The line must start and end with single `*` (not `**`)
- Must be a complete line (not inline italic within dialogue)

## Multi-line dialogue

Dialogue continues on subsequent non-empty lines until the next attribution, stage direction, or scene heading:

```markdown
**TOM:**
Once upon a Wednesday meeting:
A document that I had made,
My manager she heaped on praise,
amendments and great parts deleting.
```

All continuation lines are joined with spaces into a single dialogue entry.

## Preamble content

Text between the title/author and the first `### Scene` heading is considered preamble. This excludes:
- `## ACT` headings (act markers)
- Italic lines starting with `*` (these would be stage directions but are skipped in preamble since no scene is active)

Preamble text is collected for the introduction chapter when `render-intro: true`.

Note: the markdown format does not support structured character tables. Character descriptions in markdown preamble are free-form text.

## Footnotes

Footnote references use the markdown syntax `[^name]`:

```markdown
**ALICE:**
Put it in the press[^press] over there.

[^press]: A press is a type of cupboard or closet.
```

- `[^press]` is stripped from the dialogue text before synthesis
- The definition is rendered as a narrator aside immediately after the dialogue line
- Footnote definitions are collected from anywhere in the file
- Undefined references are stripped silently

## Complete example

```markdown
# The Test Play

*by Test Author*

Characters: Alice is a curious girl. Bob is her quiet neighbour.

## ACT I

### Scene 1: The Room

*A room. Morning. Empty except for a chair.*

**ALICE:**
Good morning.

**BOB:**
Is it.

*ALICE sits down.*

**ALICE:**
I think so.

**BOB (sarcastically):**
Wonderful.

### Scene 2: The Garden

*The garden. Afternoon.*

**ALICE:**
Much better out here.

**BOB:**
If you say so.

*CHARLIE enters carrying an umbrella.*

**CHARLIE:**
It's going to rain.

[^press]: A press is a type of cupboard or closet.
```
