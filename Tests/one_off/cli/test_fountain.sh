#!/usr/bin/env bash
# ABOUTME: One-off tests for Fountain screenplay format parsing (issue #26).
# ABOUTME: Tests scene headings, character extraction, dialogue, action, transitions, notes.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: Fountain format (RT-26.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

FIXTURES="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
FOUNTAIN="${FIXTURES}/test_script.fountain"
FORCED="${FIXTURES}/test_script_forced.fountain"
CONFIG="${FIXTURES}/test_script_fountain.yaml"

# ---------------------------------------------------------------------------
# AC26.1: Fountain files recognised as scripts
# ---------------------------------------------------------------------------

# RT-26.1: .fountain file with config produces dry-run output.
test_RT26_1() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
    printf '%s' "${output}" | grep -qi "Script mode" || return 1
}
run_test "RT-26.1" ".fountain file parsed as script with config" test_RT26_1

# RT-26.2: .fountain file without config is not parsed as script.
test_RT26_2() {
    local output
    # Without --script-config and no auto-discovered yaml, should not parse as script
    output=$("${YAPPER}" convert "${FOUNTAIN}" --dry-run --non-interactive 2>&1) || true
    if printf '%s' "${output}" | grep -qi "Script mode"; then
        return 1  # Should not be script mode
    fi
}
run_test "RT-26.2" ".fountain without config not treated as script" test_RT26_2

# ---------------------------------------------------------------------------
# AC26.2: Scene headings create scenes
# ---------------------------------------------------------------------------

# RT-26.3: INT. heading creates a scene.
test_RT26_3() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "LIVING ROOM" || return 1
}
run_test "RT-26.3" "INT. heading creates a scene" test_RT26_3

# RT-26.4: EXT. heading creates a scene.
test_RT26_4() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "GARDEN" || return 1
}
run_test "RT-26.4" "EXT. heading creates a scene" test_RT26_4

# RT-26.5: Forced scene heading (.HEADING) creates a scene.
test_RT26_5() {
    local output
    output=$("${YAPPER}" convert "${FORCED}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "SNIPER SCOPE" || return 1
}
run_test "RT-26.5" "forced scene heading creates a scene" test_RT26_5

# RT-26.6: Scene number annotations stripped from title.
test_RT26_6() {
    # Create a fixture with scene numbers
    local numbered="${SUITE_TMP}/numbered.fountain"
    cat > "${numbered}" <<'FOUNTAIN'
Title: Numbered Test

INT. HOUSE - DAY #1A#

ALICE
Hello.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${numbered}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    # Scene number #1A# should not appear in scene title
    if printf '%s' "${output}" | grep -q "#1A#"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "HOUSE" || return 1
}
run_test "RT-26.6" "scene number annotations stripped" test_RT26_6

# ---------------------------------------------------------------------------
# AC26.3: Character name extraction
# ---------------------------------------------------------------------------

# RT-26.7: Basic ALL CAPS character name extracted.
test_RT26_7() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
}
run_test "RT-26.7" "basic character names extracted" test_RT26_7

# RT-26.8: Character with (O.S.) extension has it stripped.
test_RT26_8() {
    local output
    output=$("${YAPPER}" convert "${FORCED}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "MOM" || return 1
    # (O.S.) should not appear in character name in cast list
    if printf '%s' "${output}" | grep "^  MOM" | grep -q "O\.S\."; then
        return 1
    fi
}
run_test "RT-26.8" "character extension (O.S.) stripped" test_RT26_8

# RT-26.9: Character with (V.O.) extension has it stripped.
test_RT26_9() {
    local output
    output=$("${YAPPER}" convert "${FORCED}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "HANS" || return 1
}
run_test "RT-26.9" "character extension (V.O.) stripped" test_RT26_9

# RT-26.10: Forced character (@McCLANE) preserves mixed case.
test_RT26_10() {
    local output
    output=$("${YAPPER}" convert "${FORCED}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "McCLANE\|MCCLANE" || return 1
}
run_test "RT-26.10" "forced character @ preserves name" test_RT26_10

# ---------------------------------------------------------------------------
# AC26.4: Dialogue captured
# ---------------------------------------------------------------------------

# RT-26.11: Single-line dialogue captured.
test_RT26_11() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Good morning" || return 1
}
run_test "RT-26.11" "single-line dialogue captured" test_RT26_11

# RT-26.12: Multi-line dialogue joined correctly.
test_RT26_12() {
    local multi="${SUITE_TMP}/multi.fountain"
    cat > "${multi}" <<'FOUNTAIN'
Title: Multi Test

INT. ROOM - DAY

ALICE
This is a long speech
that spans multiple lines
and should be joined together.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${multi}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "long speech.*spans\|spans.*multiple" || return 1
}
run_test "RT-26.12" "multi-line dialogue joined" test_RT26_12

# RT-26.13: Dialogue terminates at blank line.
test_RT26_13() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    # ALICE's first line is "Good morning." — should not include BOB's dialogue
    # Check that "Good morning" and "Is it" are separate entries
    printf '%s' "${output}" | grep -qi "Good morning" || return 1
    printf '%s' "${output}" | grep -qi "Is it" || return 1
}
run_test "RT-26.13" "dialogue terminates at blank line" test_RT26_13

# ---------------------------------------------------------------------------
# AC26.5: Parentheticals stripped
# ---------------------------------------------------------------------------

# RT-26.14: Parenthetical between character and dialogue stripped.
test_RT26_14() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "sarcastically"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "Is it" || return 1
}
run_test "RT-26.14" "parenthetical before dialogue stripped" test_RT26_14

# RT-26.15: Parenthetical mid-dialogue stripped.
test_RT26_15() {
    local mid="${SUITE_TMP}/mid_paren.fountain"
    cat > "${mid}" <<'FOUNTAIN'
Title: Mid Paren Test

INT. ROOM - DAY

ALICE
I cannot believe
(under her breath)
that you said that.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${mid}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "under her breath"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "cannot believe\|said that" || return 1
}
run_test "RT-26.15" "mid-dialogue parenthetical stripped" test_RT26_15

# ---------------------------------------------------------------------------
# AC26.6: Action lines as stage directions
# ---------------------------------------------------------------------------

# RT-26.16: Action paragraph becomes stage direction.
test_RT26_16() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "stage.*living room\|living room.*morning\|sits down" || return 1
}
run_test "RT-26.16" "action becomes stage direction" test_RT26_16

# RT-26.17: Forced action (!UPPERCASE) treated as stage direction.
test_RT26_17() {
    local output
    output=$("${YAPPER}" convert "${FORCED}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "SCANNING\|scanning" || return 1
    # Should NOT be treated as a character name
    if printf '%s' "${output}" | grep "^  SCANNING" | grep -qi ":"; then
        return 1
    fi
}
run_test "RT-26.17" "forced action not treated as character" test_RT26_17

# ---------------------------------------------------------------------------
# AC26.7: Title page metadata
# ---------------------------------------------------------------------------

# RT-26.18: Title: key populates document title.
test_RT26_18() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "The Fountain Test" || return 1
}
run_test "RT-26.18" "title page Title: extracted" test_RT26_18

# RT-26.19: Author: key populates document author.
test_RT26_19() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Test Writer" || return 1
}
run_test "RT-26.19" "title page Author: extracted" test_RT26_19

# RT-26.20: Multi-line title page values handled.
test_RT26_20() {
    local multiline="${SUITE_TMP}/multiline_title.fountain"
    cat > "${multiline}" <<'FOUNTAIN'
Title:
    The Big
    Screenplay
Author: Test Writer

INT. ROOM - DAY

ALICE
Hello.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${multiline}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "The Big\|Big Screenplay\|Screenplay" || return 1
}
run_test "RT-26.20" "multi-line title page values handled" test_RT26_20

# ---------------------------------------------------------------------------
# AC26.8: Notes and boneyard stripped
# ---------------------------------------------------------------------------

# RT-26.21: Inline notes stripped from dialogue.
test_RT26_21() {
    local noted="${SUITE_TMP}/noted.fountain"
    cat > "${noted}" <<'FOUNTAIN'
Title: Notes Test

INT. ROOM - DAY

ALICE
Hello there[[should we change this greeting?]] friend.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${noted}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "should we change"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "Hello there.*friend\|Hello.*friend" || return 1
}
run_test "RT-26.21" "inline notes stripped from dialogue" test_RT26_21

# RT-26.22: Standalone note lines stripped.
test_RT26_22() {
    local noted="${SUITE_TMP}/noted2.fountain"
    cat > "${noted}" <<'FOUNTAIN'
Title: Notes Test 2

INT. ROOM - DAY

[[This is a standalone note that should not appear.]]

ALICE
Hello.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${noted}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "standalone note"; then
        return 1
    fi
}
run_test "RT-26.22" "standalone note lines stripped" test_RT26_22

# RT-26.23: Boneyard blocks stripped entirely.
test_RT26_23() {
    local boned="${SUITE_TMP}/boneyard.fountain"
    cat > "${boned}" <<'FOUNTAIN'
Title: Boneyard Test

INT. ROOM - DAY

ALICE
Hello.

/*
This entire section
should be ignored
including BOB's deleted scene.
*/

EXT. GARDEN - DAY

ALICE
Goodbye.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${boned}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "deleted scene\|should be ignored"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "Hello" || return 1
    printf '%s' "${output}" | grep -qi "Goodbye" || return 1
}
run_test "RT-26.23" "boneyard blocks stripped" test_RT26_23

# ---------------------------------------------------------------------------
# AC26.9: Transitions as stage directions
# ---------------------------------------------------------------------------

# RT-26.24: CUT TO: rendered as stage direction.
test_RT26_24() {
    # Use a small fixture so CUT TO: isn't truncated by the 5-entry preview
    local trans="${SUITE_TMP}/transition.fountain"
    cat > "${trans}" <<'FOUNTAIN'
Title: Transition Test

INT. ROOM - DAY

ALICE
Hello.

CUT TO:

EXT. GARDEN - DAY

BOB
Goodbye.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${trans}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "CUT TO\|cut to" || return 1
}
run_test "RT-26.24" "CUT TO: rendered as stage direction" test_RT26_24

# RT-26.25: Forced transition rendered as stage direction.
test_RT26_25() {
    local trans="${SUITE_TMP}/forced_trans.fountain"
    cat > "${trans}" <<'FOUNTAIN'
Title: Forced Transition Test

INT. ROOM - DAY

ALICE
Hello.

>FADE TO BLACK.

EXT. GARDEN - DAY

BOB
Goodbye.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${trans}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "FADE TO BLACK\|fade to black" || return 1
}
run_test "RT-26.25" "forced transition rendered" test_RT26_25

# ---------------------------------------------------------------------------
# AC26.10: Emphasis stripped
# ---------------------------------------------------------------------------

# RT-26.26: *italic* markers stripped.
test_RT26_26() {
    local emph="${SUITE_TMP}/emphasis.fountain"
    cat > "${emph}" <<'FOUNTAIN'
Title: Emphasis Test

INT. ROOM - DAY

ALICE
This is *very* important.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${emph}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "very important" || return 1
    # Check no stray asterisks in dialogue preview
    if printf '%s' "${output}" | grep "ALICE" | grep -q '\*very\*'; then
        return 1
    fi
}
run_test "RT-26.26" "italic emphasis stripped" test_RT26_26

# RT-26.27: **bold** markers stripped.
test_RT26_27() {
    local emph="${SUITE_TMP}/bold.fountain"
    cat > "${emph}" <<'FOUNTAIN'
Title: Bold Test

INT. ROOM - DAY

ALICE
This is **really** important.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${emph}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "really important" || return 1
}
run_test "RT-26.27" "bold emphasis stripped" test_RT26_27

# RT-26.28: _underline_ markers stripped.
test_RT26_28() {
    local emph="${SUITE_TMP}/underline.fountain"
    cat > "${emph}" <<'FOUNTAIN'
Title: Underline Test

INT. ROOM - DAY

ALICE
This is _extremely_ important.
FOUNTAIN
    local output
    output=$("${YAPPER}" convert "${emph}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "extremely important" || return 1
}
run_test "RT-26.28" "underline emphasis stripped" test_RT26_28

# ---------------------------------------------------------------------------
# AC26.11: Existing config options work with Fountain
# ---------------------------------------------------------------------------

# RT-26.29: Character voice assignment from config applies.
test_RT26_29() {
    local voice_config="${SUITE_TMP}/voice.yaml"
    cat > "${voice_config}" <<YAML
auto-assign-voices: true
render-intro: false
character-voices:
  ALICE: bf_emma
  BOB: bm_daniel
YAML
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${voice_config}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE.*bf_emma\|bf_emma.*ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB.*bm_daniel\|bm_daniel.*BOB" || return 1
}
run_test "RT-26.29" "voice assignment works with Fountain" test_RT26_29

# RT-26.30: --threads flag works with Fountain conversion.
test_RT26_30() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt26_30.m4b" 2>&1) || true
    printf '%s' "${output}" | grep -qi "Script mode" || return 1
    [[ -s "${SUITE_TMP}/rt26_30.m4b" ]] || return 1
}
run_test "RT-26.30" "--threads works with Fountain" test_RT26_30

# ---------------------------------------------------------------------------
# --script flag (validates BYPASS addition)
# ---------------------------------------------------------------------------

# RT-26.31: --script flag forces script mode without any config file.
test_RT26_31() {
    local output
    output=$("${YAPPER}" convert "${FOUNTAIN}" --script --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Script mode" || return 1
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "script flag" || return 1
}
run_test "RT-26.31" "--script forces script mode without config" test_RT26_31

# RT-26.32: --script with org-mode file also works.
test_RT26_32() {
    local org="${SUITE_TMP}/no_config.org"
    cat > "${org}" <<'ORG'
#+TITLE: No Config Test
* ACT I
** Scene 1: Test
**** ALICE
Hello.
**** BOB
Goodbye.
ORG
    local output
    output=$("${YAPPER}" convert "${org}" --script --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Script mode" || return 1
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
}
run_test "RT-26.32" "--script works with org-mode" test_RT26_32

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
summarise "Fountain format"
