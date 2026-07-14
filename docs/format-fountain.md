<!-- Version: 1.0 | Last updated: 2026-04-26 -->

# Fountain Screenplay Format Specification

This document defines how yapper interprets [Fountain](https://fountain.io) (`.fountain`, `.spmd`) files as screenplays for multi-voice audiobook conversion.

## File structure

```fountain
Title: My Screenplay
Author: Writer Name
Draft date: 2026-04-26

INT. LIVING ROOM - DAY

A small room. Morning light through the curtains.

ALICE
Good morning.

BOB
(sarcastically)
Is it.

Alice sits down on the sofa.

CUT TO:

EXT. GARDEN - DAY

ALICE
Much better out here.
```

## Element mapping

| Fountain element | Yapper interpretation | ScriptDocument field |
|---|---|---|
| Title page `Title:` | Play/screenplay title | `title` |
| Title page `Subtitle:` | Subtitle | `subtitle` |
| Title page `Author:` | Author name | `author` |
| Title page (other keys) | Collected as preamble | `preamble` |
| Scene heading (`INT.`/`EXT.`/forced `.`) | Scene boundary | `scenes[].title` (becomes M4B chapter) |
| Character line (ALL CAPS) | Dialogue attribution | `scenes[].entries[]` (type: `.dialogue`) |
| Dialogue text | Dialogue content | `ScriptEntry.text` |
| Parenthetical `(notes)` | Stripped (acting direction) | - |
| Action paragraph | Stage direction | `scenes[].entries[]` (type: `.stageDirection`) |
| Transition (`CUT TO:`) | Stage direction | `scenes[].entries[]` (type: `.stageDirection`) |
| Centred text (`>text<`) | Stage direction | `scenes[].entries[]` (type: `.stageDirection`) |
| Notes (`[[text]]`) | Stripped entirely | - |
| Boneyard (`/* */`) | Stripped entirely | - |
| Sections (`#`, `##`) | Structural markers (skipped) | - |
| Synopses (`= text`) | Collected for outline | `outline` |
| Lyrics (`~text`) | Stage direction | `scenes[].entries[]` (type: `.stageDirection`) |
| Page breaks (`===`) | Ignored | - |
| Emphasis (`*`, `**`, `_`) | Stripped before synthesis | - |
| Forced character (`@`) | Character line override | Parsed as dialogue attribution |
| Forced action (`!`) | Action line override | Parsed as stage direction |
| Forced heading (`.`) | Scene heading override | Parsed as scene boundary |
| Forced transition (`>`) | Transition override | Parsed as stage direction |
| Dual dialogue (`^`) | Sequential rendering | Rendered in order (no simultaneous playback) |

## Parsing rules

Fountain is **paragraph-based**: elements are separated by blank lines. Classification depends on the content pattern of each paragraph block, unlike org-mode (line-prefix-based) and markdown (marker-based).

### Title page

Optional. Detected at the very start of the file as key-value pairs before the first blank line:

```fountain
Title: My Screenplay
Author: Writer Name
Draft date: 2026-04-26
Contact:
    Production Company
    123 Main Street
```

- Keys end with colons
- Values can be inline or on indented continuation lines (3+ spaces or tab)
- `Title:` and `Author:` populate metadata; other keys go to preamble
- The title page ends at the first blank line

### Scene headings

A line that starts with `INT`, `EXT`, `EST`, `INT./EXT`, `INT/EXT`, or `I/E` (case-insensitive):

```fountain
INT. LIVING ROOM - DAY

EXT. BRICK'S PATIO - NIGHT

INT./EXT. CAR - MOVING
```

Forced scene heading with a leading period:

```fountain
.SNIPER SCOPE POV
```

Scene number annotations (in `#...#`) are stripped from the title:

```fountain
INT. HOUSE - DAY #1A#
```

Produces scene title: "INT. HOUSE - DAY"

### Character names

An entirely uppercase line preceded by a blank line, with no blank line after it. Must contain at least one letter:

```fountain
ALICE
Good morning.

BOB
Is it.
```

Character extensions in parentheses are stripped:

| Character line | Extracted name | Stripped |
|---|---|---|
| `ALICE` | ALICE | - |
| `MOM (O.S.)` | MOM | (O.S.) |
| `HANS (V.O.)` | HANS | (V.O.) |
| `BOB (on the radio)` | BOB | (on the radio) |

Forced character with `@` prefix (preserves mixed case):

```fountain
@McCLANE
Yippee ki-yay.
```

Dual dialogue (caret suffix) is parsed but rendered sequentially:

```fountain
BRICK
Screw retirement.

STEEL ^
Screw retirement.
```

### Dialogue

Text following a character or parenthetical line, continuing until a blank line:

```fountain
ALICE
This is a long speech
that spans multiple lines
and should be joined together.
```

Multi-line dialogue is joined with spaces into a single entry.

### Parentheticals

Lines wrapped in parentheses within a dialogue block. Stripped before synthesis:

```fountain
BOB
(sarcastically)
Is it really?
(under his breath)
I doubt it.
```

Both parentheticals are stripped. Dialogue becomes: "Is it really? I doubt it."

### Action

The default element type. Any paragraph that does not match other element rules:

```fountain
Alice sits down on the sofa. She looks out the window.
```

Forced action with `!` prefix (prevents ALL-CAPS text from being parsed as a character):

```fountain
!SCANNING THE AISLES
```

### Transitions

Uppercase lines ending in `TO:`, preceded and followed by blank lines:

```fountain
CUT TO:

FADE TO:
```

Forced transition with `>` prefix:

```fountain
>BURN TO WHITE.
```

### Centred text

Action text bracketed with `>` and `<`:

```fountain
>THE END<

> BRICK & STEEL <
```

### Notes

Text in double brackets, stripped from all output:

```fountain
ALICE
Hello there[[should we change this?]] friend.

[[This standalone note is also removed.]]
```

### Boneyard

Content between `/* */` markers, completely ignored:

```fountain
/*
INT. DELETED SCENE - DAY

BOB
This scene was cut.
*/
```

Can span multiple lines. All content within is stripped before parsing.

### Lyrics

Lines starting with `~`, rendered as stage directions:

```fountain
~Willy Wonka! Willy Wonka!
~The amazing chocolatier!
```

### Emphasis

Stripped before synthesis:

| Markup | Meaning | Output |
|---|---|---|
| `*text*` | Italic | text |
| `**text**` | Bold | text |
| `***text***` | Bold italic | text |
| `_text_` | Underline | text |

### Sections and synopses

Sections (`#`, `##`, etc.) are structural markers, skipped in output:

```fountain
# Act One

## Sequence One
```

Synopses (`= text`) are collected for the outline:

```fountain
= Set up the characters and the story.
```

## Script detection

A file is recognized as a Fountain screenplay when:
1. The file extension is `.fountain` or `.spmd`
2. Script mode is selected by project config, `--script`, or the deprecated `--script-config` alias

Without a config file, `.fountain` files are not parsed as scripts.

## Configuration

Fountain files use the same `script.yaml` configuration as org-mode and markdown. All config options apply: voice assignment, gaps, speed, preamble, speech substitution, threads. See [script-reading.md](script-reading.md) for the full configuration reference.

## Complete example

```fountain
Title: About Time
Author: Tadg Paul
Draft date: 2026-04-26

INT. KITCHEN - DAY

A kitchen. Moving day. Boxes everywhere. The house not yet lived in.

BEN
Right. Where are we putting everything.

CAIT
Not there.

BEN
I've only come in.

CAIT
Then don't stop there.

Kevin enters behind him dragging a duvet.

KEVIN
Which one's mine.

BEN
The small one.

KEVIN
(protesting)
That's not fair.

BEN
It's character building.

CUT TO:

EXT. GARDEN - DAY

The garden. Afternoon.

KEVIN
I don't want character.

>THE END<
```
