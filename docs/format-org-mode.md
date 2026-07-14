<!-- Version: 1.0 | Last updated: 2026-04-26 -->

# Org-mode Script Format Specification

This document defines how yapper interprets org-mode (`.org`) files as play/screenplay scripts.

## File structure

```org
#+TITLE: Play Title
#+SUBTITLE: A Drama in Two Acts
#+AUTHOR: Author Name

* Characters
|------------+-----------------------------------------------------|
| CHARACTER  | Description of the character                        |
| OTHER CHAR | Another description                                 |
|------------+-----------------------------------------------------|

* Outline
A summary of the play's premise.

* ACT I
** Scene 1: Scene Title
*** Stage direction text.
**** CHARACTER
Dialogue text.
**** CHARACTER acting direction
More dialogue.

[fn:name] Footnote definition text.
```

## Element mapping

| Org-mode element | Yapper interpretation | ScriptDocument field |
|---|---|---|
| `#+TITLE:` | Play title | `title` |
| `#+AUTHOR:` | Author name | `author` |
| `#+SUBTITLE:` | Subtitle | `subtitle` |
| `#+TEMPLATE:`, `#+STARTUP:`, `#+OPTIONS:` | Ignored (org directives) | - |
| `*` (L1 heading) | Act or top-level section marker | Tracked for preamble extraction |
| `**` (L2 heading) | Scene boundary | `scenes[].title` |
| `***` (L3 heading) | Stage direction | `scenes[].entries[]` (type: `.stageDirection`) |
| `****` (L4 heading) | Dialogue attribution | `scenes[].entries[]` (type: `.dialogue`) |
| `*****` (L5 heading) | Transition | `scenes[].entries[]` (type: `.transition`) |
| Body text below `****` | Dialogue continuation | Appended to current dialogue entry |
| `\|` table rows | Character descriptions (in preamble) | `characterDescriptions` |
| `\|---` table separators | Ignored | - |
| `[fn:name]` in text | Footnote reference (stripped) | Triggers footnote aside |
| `[fn:name] definition` at file end | Footnote definition | `footnotes[name]` |

## Heading hierarchy

```
* ACT I                    ← L1: act/section marker (not rendered as audio)
** Scene 1: Title          ← L2: scene boundary (becomes M4B chapter)
*** Stage direction.       ← L3: stage direction (narrator voice)
**** CHARACTER              ← L4: dialogue attribution
Dialogue text here.         ← body: dialogue content
**** CHARACTER (softly)     ← L4: with acting direction in parentheses
More dialogue.
***** FADE OUT.             ← L5: transition (narrator voice)
```

## Dialogue attribution

The L4 heading text after `**** ` is parsed to extract the character name. Acting directions are stripped:

| L4 heading | Extracted character | Stripped direction |
|---|---|---|
| `**** KEVIN` | KEVIN | - |
| `**** KEVIN softly` | KEVIN | softly |
| `**** KEVIN, softly` | KEVIN | softly |
| `**** KEVIN (softly)` | KEVIN | (softly) |
| `**** KEVIN, (softly)` | KEVIN | (softly) |
| `**** GDA CONLON` | GDA CONLON | - |
| `**** GDA CONLON softly` | GDA CONLON | softly |
| `**** CÁIT gives him a look` | CÁIT | gives him a look |

**Rule:** Character names consist of leading ALL-CAPS words (including accented uppercase like CÁIT). The first word containing any lowercase letter marks the start of the acting direction.

## Multi-line dialogue

Dialogue can span multiple lines. All body text below a `****` heading until the next heading or stage direction is joined with spaces into a single dialogue entry:

```org
**** TOM
Once upon a Wednesday meeting:
A document that I had made,
My manager she heaped on praise,
amendments and great parts deleting.
```

Produces one dialogue entry: `"Once upon a Wednesday meeting: A document that I had made, My manager she heaped on praise, amendments and great parts deleting."`

## Preamble content

Everything before the first `**` scene heading is considered preamble:

- `#+TITLE:`, `#+SUBTITLE:`, and `#+AUTHOR:` are extracted as metadata
- `*` L1 headings are tracked by name (e.g. "Characters", "Outline")
- Table rows under "Characters" are parsed as `(name, description)` pairs
- Text under "Outline" becomes the outline field
- Other text under L1 headings is collected as general preamble

When `render-intro: true` (the default), this preamble is synthesized as an introductory M4B chapter.

## Footnotes

Footnote references use the org-mode syntax `[fn:name]`:

```org
**** ALICE
Put it in the press[fn:press] over there.

[fn:press] A press is a type of cupboard or closet.
```

- `[fn:press]` is stripped from the dialogue text before synthesis
- The definition is rendered as a narrator aside immediately after the dialogue line
- Footnote definitions are collected from anywhere in the file (typically at the end)
- Undefined references are stripped silently

## Script detection

A file is recognized as an org-mode script when:
1. The file extension is `.org`
2. Script mode is selected by project config, `--script`, or the deprecated `--script-config` alias

Without a config file, `.org` files are not parsed as scripts.

## Character table format

The character table uses standard org-mode table syntax:

```org
|------------+-----------------------------------------------------|
| KEVIN      | 11yo boy. The returner. Quiet, sensitive kid.       |
| NESSA      | Kevin's sister, 13yo in Act I, 22yo in Act II.      |
| GDA CONLON | Garda. Fifties. Knew the original case.             |
|------------+-----------------------------------------------------|
```

- Separator rows (`|---...`) are ignored
- Each data row yields a `(name, description)` pair
- Names in the table do not need to match speaking characters exactly
- Descriptions are used in the preamble narration

## Complete example

```org
#+TITLE: About Time
#+AUTHOR: Tadg Paul

* Characters
|-------+-------------------------------|
| KEVIN | An eleven-year-old boy        |
| NESSA | Kevin's sister                |
| BEN   | Father, means well            |
|-------+-------------------------------|

* Outline
A missing boy returns to his family after an unexplained absence.

* ACT I
** Scene 1: Moving Day
*** Kitchen and hall. Afternoon. Moving day.
*** BEN enters through the front door carrying a box.
**** BEN
Right. Where are we putting everything.
*** KEVIN enters behind him dragging a duvet.
**** KEVIN
Which one's mine.
**** BEN
The small one.
**** KEVIN
That's not fair.
**** BEN
It's character building.

** Scene 2: The Attic
*** The attic. Evening. KEVIN alone.
**** KEVIN
Hello? Is anyone there?

[fn:press] A press is a type of cupboard or closet.
```
