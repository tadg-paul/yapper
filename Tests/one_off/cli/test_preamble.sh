#!/usr/bin/env bash
# ABOUTME: One-off tests for preamble rendering, footnotes, and metadata flow (issue #24).
# ABOUTME: Tests intro chapter synthesis, footnote narrator asides, and title/author pre-population.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: preamble, footnotes, metadata (RT-24.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

FIXTURES="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
PREAMBLE_ORG="${FIXTURES}/test_script_preamble.org"
PREAMBLE_MD="${FIXTURES}/test_script_preamble.md"
FOOTNOTE_ORG="${FIXTURES}/test_script_footnotes.org"
CONFIG_PREAMBLE="${FIXTURES}/test_script_preamble.yaml"
CONFIG_NO_PREAMBLE="${FIXTURES}/test_script_no_preamble.yaml"
CONFIG_INTRO_VOICE="${FIXTURES}/test_script_intro_voice.yaml"
CONFIG_DEFAULT="${FIXTURES}/test_script.yaml"

# ---------------------------------------------------------------------------
# AC24.1: Preamble synthesised as intro chapter
# ---------------------------------------------------------------------------

# RT-24.1: Org-mode script with character table and outline produces a preamble chapter.
# User action: yapper convert preamble.org --script-config preamble.yaml --dry-run --non-interactive
# User observes: dry-run output includes an "Introduction" or preamble section.
test_RT24_1() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Should show preamble/introduction content
    printf '%s' "${output}" | grep -qi "introduction\|preamble\|characters\|outline" || return 1
}
run_test "RT-24.1" "org-mode preamble chapter produced" test_RT24_1

# RT-24.2: Markdown script with pre-scene content produces a preamble chapter.
# User action: yapper convert preamble.md --script-config preamble.yaml --dry-run --non-interactive
# User observes: dry-run output includes preamble content.
test_RT24_2() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_MD}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "introduction\|preamble\|characters\|setting" || return 1
}
run_test "RT-24.2" "markdown preamble chapter produced" test_RT24_2

# RT-24.3: Character descriptions from table included in preamble.
# User action: yapper convert preamble.org --script-config preamble.yaml --dry-run --non-interactive
# User observes: character descriptions visible in dry-run output.
test_RT24_3() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Character descriptions from the org table should appear
    printf '%s' "${output}" | grep -qi "curious girl\|quiet fellow" || return 1
}
run_test "RT-24.3" "character descriptions in preamble" test_RT24_3

# ---------------------------------------------------------------------------
# AC24.2: render-intro config controls preamble
# ---------------------------------------------------------------------------

# RT-24.4: render-intro: false suppresses preamble chapter.
# User action: yapper convert preamble.org --script-config no_preamble.yaml --dry-run --non-interactive
# User observes: no preamble/introduction section in dry-run output.
test_RT24_4() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_NO_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Should NOT contain preamble/introduction markers
    if printf '%s' "${output}" | grep -qi "introduction.*chapter\|preamble.*chapter"; then
        return 1
    fi
}
run_test "RT-24.4" "render-intro: false suppresses preamble" test_RT24_4

# RT-24.5: Omitting render-intro defaults to true.
# User action: yapper convert preamble.org --script-config (no render-intro key) --dry-run --non-interactive
# User observes: preamble is rendered (default on).
test_RT24_5() {
    # Create a config with no render-intro key
    local minimal_config="${SUITE_TMP}/minimal.yaml"
    cat > "${minimal_config}" <<YAML
auto-assign-voices: true
YAML
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${minimal_config}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "introduction\|preamble\|curious girl\|outline" || return 1
}
run_test "RT-24.5" "render-intro defaults to true" test_RT24_5

# ---------------------------------------------------------------------------
# AC24.3: intro-voice used for preamble
# ---------------------------------------------------------------------------

# RT-24.6: intro-voice in config is used for preamble synthesis.
# User action: yapper convert preamble.org --script-config intro_voice.yaml --dry-run --non-interactive
# User observes: dry-run shows intro voice name for preamble.
test_RT24_6() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_INTRO_VOICE}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "bf_emma\|intro.*bf_emma" || return 1
}
run_test "RT-24.6" "intro-voice used for preamble" test_RT24_6

# RT-24.7: Without intro-voice, preamble uses narrator voice.
# User action: yapper convert preamble.org --script-config preamble.yaml --dry-run --non-interactive
# User observes: preamble voice matches narrator voice.
test_RT24_7() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Narrator voice should be mentioned for preamble (no intro-voice override in this config)
    printf '%s' "${output}" | grep -qi "narrator\|introduction" || return 1
}
run_test "RT-24.7" "preamble uses narrator voice as fallback" test_RT24_7

# RT-24.8: intro-voice accepts filter shorthands.
# User action: create config with intro-voice: bf, convert --dry-run.
# User observes: a British female voice is selected for the preamble.
test_RT24_8() {
    local shorthand_config="${SUITE_TMP}/shorthand.yaml"
    cat > "${shorthand_config}" <<YAML
auto-assign-voices: true
render-intro: true
intro-voice: bf
YAML
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${shorthand_config}" \
        --dry-run --non-interactive 2>&1)
    # Should select a bf_* voice
    printf '%s' "${output}" | grep -qi "bf_" || return 1
}
run_test "RT-24.8" "intro-voice accepts filter shorthands" test_RT24_8

# ---------------------------------------------------------------------------
# AC24.4: Title/author pre-populate interactive prompts
# ---------------------------------------------------------------------------

# RT-24.9: Interactive prompt displays script-derived title as default.
# User action: yapper convert preamble.org (interactive mode), observe prompt.
# User observes: prompt shows "Enter title [The Preamble Test]:".
# Note: testing interactive prompts is tricky; we test the non-interactive path
# and verify the metadata flows through correctly.
test_RT24_9() {
    local output
    # In non-interactive mode, script title should be used for M4B metadata
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --non-interactive --output "${SUITE_TMP}/rt24_9.m4b" 2>&1) || true
    # Check the M4B has the script title in metadata
    local meta
    meta=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "${SUITE_TMP}/rt24_9.m4b" 2>/dev/null)
    printf '%s' "${meta}" | grep -qi "Preamble Test" || return 1
}
run_test "RT-24.9" "script title used as M4B metadata" test_RT24_9

# RT-24.10: Interactive prompt displays script-derived author as default.
# User action: similar to RT-24.9 but for author.
# User observes: author metadata in output file.
test_RT24_10() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --non-interactive --output "${SUITE_TMP}/rt24_10.m4b" 2>&1) || true
    local meta
    meta=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt24_10.m4b" 2>/dev/null)
    printf '%s' "${meta}" | grep -qi "Test Writer" || return 1
}
run_test "RT-24.10" "script author used as M4B metadata" test_RT24_10

# RT-24.11: In non-interactive mode, script-derived values used without prompting.
# User action: yapper convert preamble.org --non-interactive.
# User observes: no prompt, metadata from script applied.
test_RT24_11() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --non-interactive --output "${SUITE_TMP}/rt24_11.m4b" 2>&1) || true
    # Should not contain "Enter title" prompt
    if printf '%s' "${output}" | grep -qi "Enter title"; then
        return 1
    fi
    [[ -s "${SUITE_TMP}/rt24_11.m4b" ]] || return 1
}
run_test "RT-24.11" "non-interactive uses script metadata without prompting" test_RT24_11

# ---------------------------------------------------------------------------
# AC24.5: Title/author announced in audio
# ---------------------------------------------------------------------------

# RT-24.12: Output audio begins with title announcement.
# User action: convert with preamble, inspect dry-run for title text.
# User observes: title appears in the preamble content.
test_RT24_12() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "The Preamble Test" || return 1
}
run_test "RT-24.12" "title in preamble output" test_RT24_12

# RT-24.13: Author announced after title.
# User action: convert with preamble, inspect dry-run for author text.
# User observes: author appears in the preamble content.
test_RT24_13() {
    local output
    output=$("${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Test Writer" || return 1
}
run_test "RT-24.13" "author in preamble output" test_RT24_13

# RT-24.14: When title or author is absent, only available metadata announced.
# User action: convert a script without #+AUTHOR.
# User observes: preamble includes title but no author announcement.
test_RT24_14() {
    local no_author="${SUITE_TMP}/no_author.org"
    cat > "${no_author}" <<'ORG'
#+TITLE: No Author Play
* Characters
|-------+--------|
| ALICE | A girl |
|-------+--------|
* ACT I
** Scene 1: Test
**** ALICE
Hello.
ORG
    local output
    output=$("${YAPPER}" convert "${no_author}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "No Author Play" || return 1
}
run_test "RT-24.14" "partial metadata still announced" test_RT24_14

# ---------------------------------------------------------------------------
# AC24.6: Footnotes stripped and rendered as narrator asides
# ---------------------------------------------------------------------------

# RT-24.15: [fn:name] markers removed from dialogue text.
# User action: convert footnote script --dry-run.
# User observes: "[fn:press]" does not appear in dialogue text.
test_RT24_15() {
    local output
    output=$("${YAPPER}" convert "${FOOTNOTE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q '\[fn:press\]'; then
        return 1  # Marker still present
    fi
    # But the word "press" should still be in the dialogue
    printf '%s' "${output}" | grep -qi "press" || return 1
}
run_test "RT-24.15" "footnote markers stripped from dialogue" test_RT24_15

# RT-24.16: Footnote definitions synthesised as narrator entries after the referencing line.
# User action: convert footnote script --dry-run.
# User observes: footnote definition text appears as a narrator/stage entry.
test_RT24_16() {
    local output
    output=$("${YAPPER}" convert "${FOOTNOTE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Footnote definition should appear in output
    printf '%s' "${output}" | grep -qi "cupboard\|closet\|built into the wall" || return 1
}
run_test "RT-24.16" "footnote definitions rendered as narrator asides" test_RT24_16

# RT-24.17: Multiple footnotes in a single line each produce a narrator aside.
# User action: convert script where ALICE says "the press[fn:press] and the post[fn:post]".
# User observes: both footnote definitions appear.
test_RT24_17() {
    local output
    output=$("${YAPPER}" convert "${FOOTNOTE_ORG}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Both press and post footnotes should be rendered
    printf '%s' "${output}" | grep -qi "cupboard\|closet" || return 1
    printf '%s' "${output}" | grep -qi "mail\|letters" || return 1
}
run_test "RT-24.17" "multiple footnotes in one line each rendered" test_RT24_17

# RT-24.18: Undefined footnote references stripped without producing an aside.
# User action: convert script with [fn:undefined] in text.
# User observes: marker removed, no error, no aside.
test_RT24_18() {
    local undef_script="${SUITE_TMP}/undef_fn.org"
    cat > "${undef_script}" <<'ORG'
#+TITLE: Undef Footnote Test
* ACT I
** Scene 1: Test
**** ALICE
Check the thing[fn:nonexistent] over there.
ORG
    local output
    output=$("${YAPPER}" convert "${undef_script}" --script-config "${CONFIG_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Marker should be stripped
    if printf '%s' "${output}" | grep -q '\[fn:nonexistent\]'; then
        return 1
    fi
    # "thing" and "over there" should still be present
    printf '%s' "${output}" | grep -qi "thing" || return 1
}
run_test "RT-24.18" "undefined footnotes stripped without error" test_RT24_18

# ---------------------------------------------------------------------------
# AC24.7: render-footnotes config
# ---------------------------------------------------------------------------

# RT-24.19: render-footnotes: false strips markers but does not render definitions.
# User action: convert footnote script with render-footnotes: false --dry-run.
# User observes: markers stripped, no footnote definition text in output.
test_RT24_19() {
    local output
    output=$("${YAPPER}" convert "${FOOTNOTE_ORG}" --script-config "${CONFIG_NO_PREAMBLE}" \
        --dry-run --non-interactive 2>&1)
    # Markers should be stripped
    if printf '%s' "${output}" | grep -q '\[fn:'; then
        return 1
    fi
    # Definition text should NOT appear as a narrator aside
    if printf '%s' "${output}" | grep -qi "cupboard\|closet\|built into the wall"; then
        return 1
    fi
}
run_test "RT-24.19" "render-footnotes: false suppresses definitions" test_RT24_19

# RT-24.20: Omitting render-footnotes defaults to true.
# User action: convert footnote script with config that has no render-footnotes key.
# User observes: footnotes are rendered.
test_RT24_20() {
    local output
    output=$("${YAPPER}" convert "${FOOTNOTE_ORG}" --script-config "${CONFIG_DEFAULT}" \
        --dry-run --non-interactive 2>&1)
    # Should render footnote definitions by default
    printf '%s' "${output}" | grep -qi "cupboard\|closet\|mail\|letters" || return 1
}
run_test "RT-24.20" "render-footnotes defaults to true" test_RT24_20

# ---------------------------------------------------------------------------
# AC24.8: Metadata precedence
# ---------------------------------------------------------------------------

# RT-24.21: CLI --title overrides script.yaml title.
# User action: convert with --title "CLI Title" and script.yaml has title.
# User observes: M4B metadata shows CLI Title.
test_RT24_21() {
    local title_config="${SUITE_TMP}/titled.yaml"
    cat > "${title_config}" <<YAML
auto-assign-voices: true
title: "YAML Title"
YAML
    "${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${title_config}" \
        --title "CLI Title" --non-interactive --output "${SUITE_TMP}/rt24_21.m4b" 2>/dev/null || true
    local meta
    meta=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "${SUITE_TMP}/rt24_21.m4b" 2>/dev/null)
    printf '%s' "${meta}" | grep -qi "CLI Title" || return 1
}
run_test "RT-24.21" "CLI --title overrides YAML title" test_RT24_21

# RT-24.22: script.yaml title overrides org-mode #+TITLE.
# User action: convert with script.yaml title set, org file has #+TITLE.
# User observes: M4B metadata shows YAML title.
test_RT24_22() {
    local yaml_title_config="${SUITE_TMP}/yaml_title.yaml"
    cat > "${yaml_title_config}" <<YAML
auto-assign-voices: true
title: "YAML Overridden Title"
YAML
    "${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${yaml_title_config}" \
        --non-interactive --output "${SUITE_TMP}/rt24_22.m4b" 2>/dev/null || true
    local meta
    meta=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "${SUITE_TMP}/rt24_22.m4b" 2>/dev/null)
    printf '%s' "${meta}" | grep -qi "YAML Overridden Title" || return 1
}
run_test "RT-24.22" "YAML title overrides org-mode #+TITLE" test_RT24_22

# RT-24.23: Interactive input overrides all when provided.
# This is inherently interactive, so we test the non-interactive fallback:
# when no interactive input is given, the highest-precedence metadata wins.
test_RT24_23() {
    # With --title CLI flag and YAML title and org title, CLI wins
    local all_config="${SUITE_TMP}/all_titles.yaml"
    cat > "${all_config}" <<YAML
auto-assign-voices: true
title: "YAML Title"
author: "YAML Author"
YAML
    "${YAPPER}" convert "${PREAMBLE_ORG}" --script-config "${all_config}" \
        --title "CLI Wins" --author "CLI Author" \
        --non-interactive --output "${SUITE_TMP}/rt24_23.m4b" 2>/dev/null || true
    local title_meta author_meta
    title_meta=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "${SUITE_TMP}/rt24_23.m4b" 2>/dev/null)
    author_meta=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt24_23.m4b" 2>/dev/null)
    printf '%s' "${title_meta}" | grep -qi "CLI Wins" || return 1
    printf '%s' "${author_meta}" | grep -qi "CLI Author" || return 1
}
run_test "RT-24.23" "CLI flags take highest precedence" test_RT24_23

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
summarise "preamble, footnotes, metadata"
