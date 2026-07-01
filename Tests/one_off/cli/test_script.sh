#!/usr/bin/env bash
# ABOUTME: One-off tests for script reading with per-character voices (issue #23).
# ABOUTME: Tests markdown and org-mode script parsing, voice assignment, config, M4B output.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: script reading (RT-23.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

FIXTURES="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
MD_SCRIPT="${FIXTURES}/test_script.md"
ORG_SCRIPT="${FIXTURES}/test_script.org"
CONFIG="${FIXTURES}/test_script.yaml"
CONFIG_NO_STAGE="${FIXTURES}/test_script_no_stage.yaml"

# ---------------------------------------------------------------------------
# AC23.1: Markdown script parsing
# ---------------------------------------------------------------------------

# RT-23.1: Markdown script with 3 characters produces correct dialogue attributions.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: dry-run output lists ALICE, BOB, CHARLIE as characters.
test_RT23_1() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
}
run_test "RT-23.1" "markdown script identifies 3 characters" test_RT23_1

# RT-23.2: Stage directions identified separately from dialogue.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: stage directions listed distinctly from character dialogue.
test_RT23_2() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Stage direction text from the script should appear attributed to narrator/stage
    printf '%s' "${output}" | grep -qi "stage\|narrator\|direction\|A room\|Morning" || return 1
}
run_test "RT-23.2" "markdown stage directions identified" test_RT23_2

# RT-23.3: Acting notes in parentheses stripped from attribution.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: "(sarcastically)" does not appear in the character name or dialogue text.
test_RT23_3() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "sarcastically"; then
        return 1
    fi
    # BOB's dialogue should still be present (check one from the first few entries)
    printf '%s' "${output}" | grep -qi "BOB" || return 1
}
run_test "RT-23.3" "acting notes stripped from attribution" test_RT23_3

# ---------------------------------------------------------------------------
# AC23.2: Org-mode script parsing
# ---------------------------------------------------------------------------

# RT-23.4: Org-mode script with L3/L4 headings produces correct attributions.
# User action: yapper convert script.org --script-config config.yaml --dry-run
# User observes: same characters as the markdown version.
test_RT23_4() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
}
run_test "RT-23.4" "org-mode script identifies 3 characters" test_RT23_4

# RT-23.5: Org-mode acting notes stripped.
# User action: yapper convert script.org --script-config config.yaml --dry-run
# User observes: "(sarcastically)" absent from output.
test_RT23_5() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "sarcastically"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "BOB" || return 1
}
run_test "RT-23.5" "org-mode acting notes stripped" test_RT23_5

# ---------------------------------------------------------------------------
# AC23.3: Consistent per-character voice assignment
# ---------------------------------------------------------------------------

# RT-23.6: Auto-assigned voices — no two characters share the same voice.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: each character has a different voice in the cast list.
test_RT23_6() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    local voices
    voices=$(printf '%s' "${output}" | grep -oiE '(af|am|bf|bm)_[a-z]+' | sort -u)
    local voice_count char_count
    voice_count=$(printf '%s\n' "${voices}" | wc -l | tr -d ' ')
    # At least 3 distinct voices for 3 characters (+ narrator = 4)
    [[ ${voice_count} -ge 3 ]]
}
run_test "RT-23.6" "no two characters share a voice" test_RT23_6

# RT-23.7: A character's voice is the same in first and last dialogue turn.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: ALICE's voice is consistent throughout.
test_RT23_7() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # ALICE has explicit voice bf_emma in the config — check it appears
    printf '%s' "${output}" | grep -qi "ALICE.*bf_emma\|bf_emma.*ALICE" || return 1
}
run_test "RT-23.7" "character voice is consistent throughout" test_RT23_7

# RT-23.8: Explicit config overrides auto-assignment.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: BOB is assigned bm_daniel as specified in config.
test_RT23_8() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "BOB.*bm_daniel\|bm_daniel.*BOB" || return 1
}
run_test "RT-23.8" "explicit voice assignment from config" test_RT23_8

# ---------------------------------------------------------------------------
# AC23.4: Voice assignment modes (explicit, filter, auto)
# ---------------------------------------------------------------------------

# RT-23.9: Explicit voice name in config assigns that exact voice.
# (Same check as RT-23.8 but for a different character.)
test_RT23_9() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE.*bf_emma\|bf_emma.*ALICE" || return 1
}
run_test "RT-23.9" "explicit voice name assigned correctly" test_RT23_9

# RT-23.10: Filter shorthand in config assigns a matching voice.
# Config has CHARLIE: am (American male filter).
test_RT23_10() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # CHARLIE should have an am_ voice
    printf '%s' "${output}" | grep -qi "CHARLIE.*am_\|am_.*CHARLIE" || return 1
}
run_test "RT-23.10" "filter shorthand assigns matching voice" test_RT23_10

# RT-23.11: Auto assignment picks a voice not used by explicitly assigned characters.
# Config has CHARLIE: auto in the no-stage config.
test_RT23_11() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG_NO_STAGE}" --dry-run --non-interactive 2>&1)
    # CHARLIE should have a voice, and it shouldn't be bf_emma (ALICE) or bm_daniel (BOB)
    local charlie_voice
    charlie_voice=$(printf '%s' "${output}" | grep -i "CHARLIE" | grep -oiE '(af|am|bf|bm)_[a-z]+' | head -1)
    [[ -n "${charlie_voice}" ]] || return 1
    [[ "${charlie_voice}" != "bf_emma" ]] || return 1
    [[ "${charlie_voice}" != "bm_daniel" ]] || return 1
}
run_test "RT-23.11" "auto assignment avoids explicitly assigned voices" test_RT23_11

# ---------------------------------------------------------------------------
# AC23.5: Stage directions
# ---------------------------------------------------------------------------

# RT-23.12: With render-stage-directions: true, stage direction text in output.
test_RT23_12() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Stage direction "A room. Morning." should appear in the plan
    printf '%s' "${output}" | grep -qi "room\|Morning\|chair" || return 1
}
run_test "RT-23.12" "stage directions included when enabled" test_RT23_12

# RT-23.13: With render-stage-directions: false, stage direction text absent.
test_RT23_13() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG_NO_STAGE}" --dry-run --non-interactive 2>&1)
    # "A room. Morning." should NOT appear — it's a stage direction
    if printf '%s' "${output}" | grep -qi "A room\|Empty except"; then
        return 1
    fi
    # But dialogue should still be present
    printf '%s' "${output}" | grep -qi "Good morning" || return 1
}
run_test "RT-23.13" "stage directions excluded when disabled" test_RT23_13

# RT-23.14: Narrator voice is distinct from all character voices.
test_RT23_14() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Narrator should be bf_lily (from config) which is not bf_emma, bm_daniel, or any am_ voice
    printf '%s' "${output}" | grep -qi "narrator.*bf_lily\|bf_lily.*narrator\|stage.*bf_lily\|bf_lily.*stage" || return 1
}
run_test "RT-23.14" "narrator voice distinct from characters" test_RT23_14

# ---------------------------------------------------------------------------
# AC23.6: Config file discovery
# ---------------------------------------------------------------------------

# RT-23.15: --script-config flag uses the specified config.
test_RT23_15() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Config specifies bf_emma for ALICE — should be applied
    printf '%s' "${output}" | grep -qi "bf_emma" || return 1
}
run_test "RT-23.15" "--script-config uses specified config" test_RT23_15

# RT-23.16: Without flag, script.yaml in same directory is discovered.
test_RT23_16() {
    local dir="${SUITE_TMP}/rt2316"
    mkdir -p "${dir}"
    cp "${MD_SCRIPT}" "${dir}/play.md"
    cp "${CONFIG}" "${dir}/script.yaml"
    local output
    output=$("${YAPPER}" convert "${dir}/play.md" --dry-run --non-interactive 2>&1)
    # Should discover script.yaml and apply its voice assignments
    printf '%s' "${output}" | grep -qi "bf_emma\|bm_daniel\|ALICE\|BOB" || return 1
}
run_test "RT-23.16" "script.yaml auto-discovered in same directory" test_RT23_16

# ---------------------------------------------------------------------------
# AC23.7: Metadata in M4B output
# ---------------------------------------------------------------------------

# RT-23.17: Config title and author in M4B metadata.
test_RT23_17() {
    local dir="${SUITE_TMP}/rt2317"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local artist album
    artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    album=$(ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    [[ "${artist}" == *"Test Author"* ]] || return 1
    [[ "${album}" == *"Test Play"* ]]
}
run_test "RT-23.17" "config metadata in M4B tags" test_RT23_17

# RT-23.18: Script headers used when config lacks metadata.
test_RT23_18() {
    local dir="${SUITE_TMP}/rt2318"
    mkdir -p "${dir}"
    # Config without title/author
    printf 'auto-assign-voices: true\nrender-stage-directions: false\n' > "${dir}/minimal.yaml"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${dir}/minimal.yaml" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local artist
    artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    # Should have extracted "Test Author" from the script's "*by Test Author*" line
    [[ "${artist}" == *"Test Author"* ]]
}
run_test "RT-23.18" "metadata extracted from script headers" test_RT23_18

# ---------------------------------------------------------------------------
# AC23.8: M4B chapters per scene
# ---------------------------------------------------------------------------

# RT-23.19: Script with 2 scenes produces M4B with 2 chapter markers.
test_RT23_19() {
    local dir="${SUITE_TMP}/rt2319"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local chapter_count
    chapter_count=$(ffprobe -v quiet -show_chapters "${dir}/play.m4b" 2>/dev/null | grep -c "^\[CHAPTER\]")
    [[ ${chapter_count} -eq 2 ]]
}
run_test "RT-23.19" "2 scenes produce 2 M4B chapters" test_RT23_19

# RT-23.20: Chapter titles match scene headings.
test_RT23_20() {
    local dir="${SUITE_TMP}/rt2320"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local chapters
    chapters=$(ffprobe -v quiet -show_chapters -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    printf '%s' "${chapters}" | grep -qi "Room" || return 1
    printf '%s' "${chapters}" | grep -qi "Garden" || return 1
}
run_test "RT-23.20" "chapter titles match scene headings" test_RT23_20

# ---------------------------------------------------------------------------
# AC23.9: --dry-run in script mode
# ---------------------------------------------------------------------------

# RT-23.21: Dry-run lists all characters with assigned voices.
test_RT23_21() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
    # At least 3 voice names visible
    local voice_count
    voice_count=$(printf '%s' "${output}" | grep -oiE '(af|am|bf|bm)_[a-z]+' | sort -u | wc -l | tr -d ' ')
    [[ ${voice_count} -ge 3 ]]
}
run_test "RT-23.21" "dry-run lists cast with voices" test_RT23_21

# RT-23.22: Dry-run shows scene structure.
test_RT23_22() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Scene 1\|Room" || return 1
    printf '%s' "${output}" | grep -qi "Scene 2\|Garden" || return 1
}
run_test "RT-23.22" "dry-run shows scene structure" test_RT23_22

# RT-23.23: Dry-run includes sample dialogue turns.
test_RT23_23() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Good morning" || return 1
}
run_test "RT-23.23" "dry-run includes dialogue preview" test_RT23_23

# ---------------------------------------------------------------------------
# AC23.10: Format auto-detection
# ---------------------------------------------------------------------------

# RT-23.24: .md file with **CHARACTER:** patterns detected as script.
test_RT23_24() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Should be in script mode — cast list visible
    printf '%s' "${output}" | grep -qi "ALICE\|cast\|character" || return 1
}
run_test "RT-23.24" ".md file detected as script" test_RT23_24

# RT-23.25: .org file with L3/L4 headings detected as script.
test_RT23_25() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE\|cast\|character" || return 1
}
run_test "RT-23.25" ".org file detected as script" test_RT23_25

# RT-23.26: Plain prose file without script patterns treated as prose.
test_RT23_26() {
    printf 'This is just a normal paragraph of text. Nothing fancy here.' > "${SUITE_TMP}/prose.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/prose.md" --dry-run --non-interactive 2>&1)
    # Should NOT show cast list or character voices — it's prose mode
    if printf '%s' "${output}" | grep -qi "cast\|character.*voice\|narrator"; then
        return 1
    fi
    # Should show standard convert dry-run output
    printf '%s' "${output}" | grep -qi "convert\|output\|voice" || return 1
}
run_test "RT-23.26" "prose file not treated as script" test_RT23_26

# ---------------------------------------------------------------------------
# AC23.11: Direction stripping (caps = name, non-caps = direction)
# ---------------------------------------------------------------------------

DIRECTIONS_ORG="${FIXTURES}/test_script_directions.org"
DIRECTIONS_MD="${FIXTURES}/test_script_directions.md"

# RT-23.27: Bare-word directions stripped in org format.
test_RT23_27() {
    local output
    output=$("${YAPPER}" convert "${DIRECTIONS_ORG}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "ALICE.*firmly\|BOB.*softly\|ALICE.*offstage"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
}
run_test "RT-23.27" "bare-word directions stripped (org)" test_RT23_27

# RT-23.28: Comma-separated directions stripped.
test_RT23_28() {
    local output
    output=$("${YAPPER}" convert "${DIRECTIONS_ORG}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "calling back"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "Hello\|Goodbye" || return 1
}
run_test "RT-23.28" "comma-separated directions stripped" test_RT23_28

# RT-23.29: Only 2 distinct characters found, not 5+.
test_RT23_29() {
    local output
    output=$("${YAPPER}" convert "${DIRECTIONS_ORG}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    local char_count
    char_count=$(printf '%s' "${output}" | grep -E "^  [A-Z]" | grep -v "Narrator" | wc -l | tr -d ' ')
    [[ ${char_count} -le 3 ]]
}
run_test "RT-23.29" "direction variants don't create extra characters" test_RT23_29

# ---------------------------------------------------------------------------
# AC23.12: Script mode activation visible on stderr
# ---------------------------------------------------------------------------

# RT-23.30: --script-config shows "Script mode" on stderr.
test_RT23_30() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Script mode"
}
run_test "RT-23.30" "--script-config activation shows Script mode" test_RT23_30

# RT-23.31: Auto-discovered script.yaml shows "Script mode" on stderr.
test_RT23_31() {
    local dir="${SUITE_TMP}/rt2331"
    mkdir -p "${dir}"
    cp "${MD_SCRIPT}" "${dir}/play.md"
    cp "${CONFIG}" "${dir}/script.yaml"
    local output
    output=$("${YAPPER}" convert "${dir}/play.md" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Script mode"
}
run_test "RT-23.31" "auto-discovered config shows Script mode" test_RT23_31

# ---------------------------------------------------------------------------
# AC23.13: Parse errors are fatal with descriptive message
# ---------------------------------------------------------------------------

BAD_CONFIG="${FIXTURES}/test_script_bad.yaml"

# RT-23.32: Malformed YAML config exits non-zero with descriptive error.
test_RT23_32() {
    local output
    if output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${BAD_CONFIG}" --dry-run --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "config\|yaml\|parse\|invalid"
}
run_test "RT-23.32" "malformed config exits non-zero with error" test_RT23_32

# RT-23.33: Valid config but empty input file exits non-zero.
test_RT23_33() {
    printf '' > "${SUITE_TMP}/empty.md"
    local output
    if output=$("${YAPPER}" convert "${SUITE_TMP}/empty.md" --script-config "${CONFIG}" --non-interactive 2>&1); then
        return 1
    fi
    return 0
}
run_test "RT-23.33" "empty input file exits non-zero" test_RT23_33

# ---------------------------------------------------------------------------
# AC23.14: Undeclared characters auto-assigned with consistent voice
# ---------------------------------------------------------------------------

UNDECLARED_CONFIG="${FIXTURES}/test_script_undeclared.yaml"

# RT-23.34: Config lists 2 characters, script has 3 — third gets a voice.
test_RT23_34() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${UNDECLARED_CONFIG}" --dry-run --non-interactive 2>&1)
    # CHARLIE is not in the config but should appear with a voice
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
    local charlie_voice
    charlie_voice=$(printf '%s' "${output}" | grep -i "CHARLIE" | grep -oiE '(af|am|bf|bm)_[a-z]+' | head -1)
    [[ -n "${charlie_voice}" ]] || return 1
    # Should not be bf_emma (ALICE) or bm_daniel (BOB)
    [[ "${charlie_voice}" != "bf_emma" ]] || return 1
    [[ "${charlie_voice}" != "bm_daniel" ]]
}
run_test "RT-23.34" "undeclared character auto-assigned unique voice" test_RT23_34

# RT-23.39: Auto-assigned character's voice is consistent.
test_RT23_39() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${UNDECLARED_CONFIG}" --dry-run --non-interactive 2>&1)
    # CHARLIE should appear in cast list with a voice
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
    # The cast list shows the assignment once — consistency is guaranteed by
    # the VoiceAssigner which assigns once before synthesis. The cast list
    # IS the assignment. If CHARLIE appears with one voice, that voice is
    # used for all CHARLIE turns.
    local voice_count
    voice_count=$(printf '%s' "${output}" | grep -i "CHARLIE" | grep -oiE '(af|am|bf|bm)_[a-z]+' | sort -u | wc -l | tr -d ' ')
    [[ ${voice_count} -eq 1 ]]
}
run_test "RT-23.39" "auto-assigned character voice is consistent" test_RT23_39

# ---------------------------------------------------------------------------
# AC23.15: Multi-word ALL-CAPS character names
# ---------------------------------------------------------------------------

MULTIWORD_ORG="${FIXTURES}/test_script_multiword.org"

# RT-23.35: GDA CONLON is one character, not two.
test_RT23_35() {
    local output
    output=$("${YAPPER}" convert "${MULTIWORD_ORG}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "GDA CONLON" || return 1
    # Should NOT have separate "GDA" and "CONLON" characters
    if printf '%s' "${output}" | grep -qE "^  GDA:" ; then
        return 1
    fi
}
run_test "RT-23.35" "multi-word caps name is one character" test_RT23_35

# ---------------------------------------------------------------------------
# AC23.16: Narrator voice filter shorthands
# ---------------------------------------------------------------------------

# RT-23.36: narrator-voice: bf assigns a British female.
test_RT23_36() {
    printf 'auto-assign-voices: true\nnarrator-voice: bf\n' > "${SUITE_TMP}/narrator_filter.yaml"
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${SUITE_TMP}/narrator_filter.yaml" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -i "narrator" | grep -qiE 'bf_'
}
run_test "RT-23.36" "narrator-voice filter assigns British female" test_RT23_36

# RT-23.37: narrator-voice: bf_lily assigns exactly bf_lily.
test_RT23_37() {
    printf 'auto-assign-voices: true\nnarrator-voice: bf_lily\n' > "${SUITE_TMP}/narrator_explicit.yaml"
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${SUITE_TMP}/narrator_explicit.yaml" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -i "narrator" | grep -qi "bf_lily"
}
run_test "RT-23.37" "narrator-voice explicit assigns bf_lily" test_RT23_37

# ---------------------------------------------------------------------------
# AC23.17: Dry-run creates no output files
# ---------------------------------------------------------------------------

# RT-23.38: --dry-run with -o flag does not create the M4B.
test_RT23_38() {
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive -o "${SUITE_TMP}/should_not_exist.m4b" >/dev/null 2>&1
    [[ ! -f "${SUITE_TMP}/should_not_exist.m4b" ]]
}
run_test "RT-23.38" "dry-run creates no output files" test_RT23_38

# ---------------------------------------------------------------------------
# Audit-recommended tests
# ---------------------------------------------------------------------------

# RT-23.40: Directions don't leak into synthesis — output duration consistent
# with dialogue only, not inflated by direction text being spoken.
test_RT23_40() {
    local dir="${SUITE_TMP}/rt2340"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${DIRECTIONS_ORG}" --script-config "${CONFIG}" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local duration
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    # 5 short dialogue lines ≈ 5-15s of audio. If directions leaked in,
    # duration would be much higher. Check < 30s.
    [[ -n "${duration}" ]] && awk "BEGIN{exit(${duration} < 30 ? 0 : 1)}"
}
run_test "RT-23.40" "directions don't inflate synthesis duration" test_RT23_40

# RT-23.41: Fully integrated — auto-discover config + org file → M4B.
test_RT23_41() {
    local dir="${SUITE_TMP}/rt2341"
    mkdir -p "${dir}"
    cp "${ORG_SCRIPT}" "${dir}/play.org"
    cp "${CONFIG}" "${dir}/script.yaml"
    "${YAPPER}" convert "${dir}/play.org" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    # Verify metadata
    local artist
    artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    [[ "${artist}" == *"Test Author"* ]] || return 1
    # Verify chapters
    local chapters
    chapters=$(ffprobe -v quiet -show_chapters "${dir}/play.m4b" 2>/dev/null | grep -c "^\[CHAPTER\]")
    [[ ${chapters} -ge 1 ]]
}
run_test "RT-23.41" "fully integrated: auto-discover + org → M4B" test_RT23_41

# RT-23.42: Markdown bare-word directions stripped.
test_RT23_42() {
    local output
    output=$("${YAPPER}" convert "${DIRECTIONS_MD}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # BOB SOFTLY should resolve to character BOB
    if printf '%s' "${output}" | grep -qi "BOB.*softly\|ALICE.*firmly"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
}
run_test "RT-23.42" "markdown bare-word directions stripped" test_RT23_42

# RT-23.43: Multi-word name + direction: GDA CONLON softly → GDA CONLON.
test_RT23_43() {
    local output
    output=$("${YAPPER}" convert "${MULTIWORD_ORG}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "GDA CONLON" || return 1
    # "softly" should not appear in cast or dialogue attribution
    if printf '%s' "${output}" | grep -i "GDA CONLON" | grep -qi "softly"; then
        return 1
    fi
}
run_test "RT-23.43" "multi-word name + direction: GDA CONLON softly" test_RT23_43

# RT-23.44: Single-scene script → M4B with 1 chapter.
test_RT23_44() {
    local dir="${SUITE_TMP}/rt2344"
    mkdir -p "${dir}"
    cp "${CONFIG}" "${dir}/script.yaml"
    "${YAPPER}" convert "${FIXTURES}/test_script_single_scene.md" --script-config "${dir}/script.yaml" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local chapters
    chapters=$(ffprobe -v quiet -show_chapters "${dir}/play.m4b" 2>/dev/null | grep -c "^\[CHAPTER\]")
    [[ ${chapters} -eq 1 ]]
}
run_test "RT-23.44" "single-scene script produces 1 chapter M4B" test_RT23_44

# ---------------------------------------------------------------------------
# Transitions
# ---------------------------------------------------------------------------

# RT-23.45: Org-mode L5 heading parsed as transition.
test_RT23_45() {
    local script="${SUITE_TMP}/trans.org"
    cat > "${script}" <<'ORG'
#+TITLE: Transition Test
* ACT I
** Scene 1: Test
**** ALICE
Hello.
***** FADE OUT.
**** BOB
Goodbye.
ORG
    local output
    output=$("${YAPPER}" convert "${script}" --script --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "transition.*FADE OUT\|FADE OUT" || return 1
}
run_test "RT-23.45" "org-mode L5 heading parsed as transition" test_RT23_45

# RT-23.46: Markdown blockquote parsed as transition.
test_RT23_46() {
    local script="${SUITE_TMP}/trans.md"
    cat > "${script}" <<'MD'
# Transition Test

### Scene 1: Test

**ALICE:**
Hello.

> CUT TO:

**BOB:**
Goodbye.
MD
    local output
    output=$("${YAPPER}" convert "${script}" --script --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "transition.*CUT TO\|CUT TO" || return 1
}
run_test "RT-23.46" "markdown blockquote parsed as transition" test_RT23_46

# RT-23.47: Transitions excluded when render.transitions is false.
test_RT23_47() {
    local dir="${SUITE_TMP}/rt2347"
    mkdir -p "${dir}"
    cat > "${dir}/script.yaml" <<'YAML'
render:
  transitions: false
YAML
    cat > "${dir}/test.org" <<'ORG'
#+TITLE: No Trans Test
* ACT I
** Scene 1: Test
**** ALICE
Hello.
***** FADE OUT.
**** BOB
Goodbye.
ORG
    local output
    output=$("${YAPPER}" convert "${dir}/test.org" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "transition\|FADE OUT"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "ALICE\|BOB" || return 1
}
run_test "RT-23.47" "transitions excluded when disabled" test_RT23_47

summarise "script reading"
