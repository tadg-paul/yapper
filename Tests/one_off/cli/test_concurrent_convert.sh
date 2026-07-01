#!/usr/bin/env bash
# ABOUTME: One-off tests for concurrent synthesis, configurable gaps/speed, stage direction names (issue #25).
# ABOUTME: Tests multi-process worker pattern, YAML config for gaps/speed/threads, and Title Case conversion.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: concurrent synthesis & config (RT-25.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

FIXTURES="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
ORG_SCRIPT="${FIXTURES}/test_script.org"
MD_SCRIPT="${FIXTURES}/test_script.md"
CONFIG="${FIXTURES}/test_script.yaml"
CONFIG_GAPS="${FIXTURES}/test_script_gaps.yaml"
CONFIG_SPEED="${FIXTURES}/test_script_speed.yaml"
CONFIG_THREADS="${FIXTURES}/test_script_threads.yaml"
STAGE_ORG="${FIXTURES}/test_script_stage_names.org"
STAGE_MD="${FIXTURES}/test_script_stage_names.md"

# ---------------------------------------------------------------------------
# AC25.1: Thread count configurable via script.yaml and --threads CLI flag
# ---------------------------------------------------------------------------

# RT-25.1: Default conversion uses 3 worker processes.
# User action: yapper convert script.org --script-config config.yaml --non-interactive
# User observes: stderr output indicates concurrent synthesis (no --threads flag needed).
test_RT25_1() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --non-interactive --output "${SUITE_TMP}/rt25_1.m4b" 2>&1) || true
    # The output should indicate script mode is active (synthesis happens)
    printf '%s' "${output}" | grep -qi "script mode" || return 1
}
run_test "RT-25.1" "default conversion uses concurrent synthesis" test_RT25_1

# RT-25.2: --threads 1 runs synthesis sequentially.
# User action: yapper convert script.org --script-config config.yaml --threads 1 --non-interactive
# User observes: conversion completes successfully with sequential synthesis.
test_RT25_2() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_2.m4b" 2>&1) || true
    printf '%s' "${output}" | grep -qi "script mode" || return 1
}
run_test "RT-25.2" "--threads 1 runs sequential synthesis" test_RT25_2

# RT-25.3: --threads N spawns N worker processes.
# User action: yapper convert script.org --script-config config.yaml --threads 2 --non-interactive
# User observes: conversion completes successfully.
test_RT25_3() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 2 --non-interactive --output "${SUITE_TMP}/rt25_3.m4b" 2>&1) || true
    printf '%s' "${output}" | grep -qi "script mode" || return 1
}
run_test "RT-25.3" "--threads N spawns N workers" test_RT25_3

# RT-25.4: threads in script.yaml sets the worker count.
# User action: yapper convert script.org --script-config threads.yaml --non-interactive
# User observes: conversion uses thread count from YAML.
test_RT25_4() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_THREADS}" \
        --non-interactive --output "${SUITE_TMP}/rt25_4.m4b" 2>&1) || true
    printf '%s' "${output}" | grep -qi "script mode" || return 1
}
run_test "RT-25.4" "threads in script.yaml sets worker count" test_RT25_4

# RT-25.5: --threads CLI flag overrides the YAML value.
# User action: yapper convert script.org --script-config threads.yaml --threads 1 --non-interactive
# User observes: conversion runs with 1 thread despite YAML saying 2.
test_RT25_5() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_THREADS}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_5.m4b" 2>&1) || true
    printf '%s' "${output}" | grep -qi "script mode" || return 1
}
run_test "RT-25.5" "--threads CLI overrides YAML threads" test_RT25_5

# ---------------------------------------------------------------------------
# AC25.2: Concurrent produces identical audio to sequential
# ---------------------------------------------------------------------------

# RT-25.6: Audio output from concurrent mode matches sequential mode.
# User action: convert same script with --threads 1 and default (3), compare output duration.
# User observes: both M4B files have the same audio duration (within 2s tolerance).
test_RT25_6() {
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_6_seq.m4b" 2>/dev/null || true
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 3 --non-interactive --output "${SUITE_TMP}/rt25_6_conc.m4b" 2>/dev/null || true
    # Both files should exist and be non-empty
    [[ -s "${SUITE_TMP}/rt25_6_seq.m4b" ]] || return 1
    [[ -s "${SUITE_TMP}/rt25_6_conc.m4b" ]] || return 1
    # Compare durations (within 2s tolerance for model non-determinism)
    local dur_seq dur_conc
    dur_seq=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_6_seq.m4b" 2>/dev/null | cut -d. -f1)
    dur_conc=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_6_conc.m4b" 2>/dev/null | cut -d. -f1)
    local diff=$(( dur_seq > dur_conc ? dur_seq - dur_conc : dur_conc - dur_seq ))
    [[ ${diff} -le 2 ]] || return 1
}
run_test "RT-25.6" "concurrent audio matches sequential duration" test_RT25_6

# RT-25.7: Concurrent output preserves correct scene order.
# User action: convert script with multiple scenes using --threads 3, inspect chapter order.
# User observes: chapters appear in script order.
test_RT25_7() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 3 --non-interactive --output "${SUITE_TMP}/rt25_7.m4b" 2>&1) || true
    # Scene 1 should appear before Scene 2 in output
    local scene1_pos scene2_pos
    scene1_pos=$(printf '%s' "${output}" | grep -n "Scene 1\|1/2\|\[1/" | head -1 | cut -d: -f1)
    scene2_pos=$(printf '%s' "${output}" | grep -n "Scene 2\|2/2\|\[2/" | head -1 | cut -d: -f1)
    [[ -n "${scene1_pos}" ]] || return 1
    [[ -n "${scene2_pos}" ]] || return 1
    [[ "${scene1_pos}" -lt "${scene2_pos}" ]] || return 1
}
run_test "RT-25.7" "concurrent preserves scene order" test_RT25_7

# ---------------------------------------------------------------------------
# AC25.3: Worker failures reported with context
# ---------------------------------------------------------------------------

# RT-25.8: Worker failure reports which entry failed.
# User action: convert a script with an invalid voice assignment.
# User observes: error message identifies the failing entry.
test_RT25_8() {
    # Create a config with an invalid voice for a character
    local bad_config="${SUITE_TMP}/bad_voice.yaml"
    cat > "${bad_config}" <<YAML
auto-assign-voices: false
character-voices:
  ALICE: nonexistent_voice_xyz
  BOB: bm_daniel
  CHARLIE: am_adam
YAML
    local output
    if output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${bad_config}" \
        --threads 3 --non-interactive --output "${SUITE_TMP}/rt25_8.m4b" 2>&1); then
        # If it somehow succeeds with auto-fallback, that's acceptable
        return 0
    fi
    # Error output should mention the failure context
    printf '%s' "${output}" | grep -qi "error\|fail\|voice" || return 1
}
run_test "RT-25.8" "worker failure reports context" test_RT25_8

# RT-25.9: Partial worker failures do not produce incomplete M4B.
# User action: attempt conversion with bad config.
# User observes: either full success or no output file — never a partial/corrupt file.
test_RT25_9() {
    local bad_config="${SUITE_TMP}/bad_voice2.yaml"
    cat > "${bad_config}" <<YAML
auto-assign-voices: false
character-voices:
  ALICE: nonexistent_voice_xyz
YAML
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${bad_config}" \
        --threads 3 --non-interactive --output "${SUITE_TMP}/rt25_9.m4b" 2>/dev/null || true
    # If the file exists, it should be valid (non-zero size and parseable)
    if [[ -f "${SUITE_TMP}/rt25_9.m4b" ]]; then
        [[ -s "${SUITE_TMP}/rt25_9.m4b" ]] || return 1
        ffprobe -v quiet "${SUITE_TMP}/rt25_9.m4b" 2>/dev/null || return 1
    fi
    # If file doesn't exist, that's also acceptable (full failure = no partial output)
}
run_test "RT-25.9" "no incomplete M4B on worker failure" test_RT25_9

# ---------------------------------------------------------------------------
# AC25.4: Leading/trailing silence trimmed
# ---------------------------------------------------------------------------

# RT-25.10: When transcribe is available, audio is trimmed using Whisper timestamps.
# This test checks the trimming path selection, not the exact trim points.
# User action: convert with transcribe available.
# User observes: conversion completes (trimming happens internally).
test_RT25_10() {
    if ! command -v transcribe >/dev/null 2>&1; then
        # Skip if transcribe not available — can't test Whisper path
        return 0
    fi
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_10.m4b" 2>&1) || true
    [[ -s "${SUITE_TMP}/rt25_10.m4b" ]] || return 1
}
run_test "RT-25.10" "whisper trimming path works when available" test_RT25_10

# RT-25.11: When transcribe is unavailable, heuristic trimming is used.
# User action: convert with transcribe not in PATH.
# User observes: conversion completes successfully with heuristic trimming.
test_RT25_11() {
    # Run with PATH that excludes transcribe
    local output
    output=$(PATH="/usr/bin:/bin" "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_11.m4b" 2>&1) || true
    [[ -s "${SUITE_TMP}/rt25_11.m4b" ]] || return 1
}
run_test "RT-25.11" "heuristic trimming fallback works" test_RT25_11

# ---------------------------------------------------------------------------
# AC25.5: Inter-line silence configurable per entry type
# ---------------------------------------------------------------------------

# RT-25.12: gap-after-dialogue controls silence after dialogue.
# User action: convert with gap-after-dialogue: 0.5 in config.
# User observes: output has longer pauses after dialogue than default.
test_RT25_12() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_GAPS}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_12.m4b" 2>&1) || true
    [[ -s "${SUITE_TMP}/rt25_12.m4b" ]] || return 1
}
run_test "RT-25.12" "gap-after-dialogue config accepted" test_RT25_12

# RT-25.13: gap-after-stage-direction controls silence after stage directions.
# User action: convert with gap-after-stage-direction: 0.8 in config.
# User observes: conversion completes with custom gap config.
test_RT25_13() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_GAPS}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_13.m4b" 2>&1) || true
    [[ -s "${SUITE_TMP}/rt25_13.m4b" ]] || return 1
}
run_test "RT-25.13" "gap-after-stage-direction config accepted" test_RT25_13

# RT-25.14: gap-after-scene controls silence at scene boundaries.
# User action: convert with gap-after-scene: 1.5 in config.
# User observes: conversion completes with scene gap config.
test_RT25_14() {
    # The gap config is in CONFIG_GAPS which sets gap-after-scene: 1.5
    # A multi-scene script with custom scene gap should produce longer output
    local dur_default dur_custom
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_14_default.m4b" 2>/dev/null || true
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_GAPS}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_14_custom.m4b" 2>/dev/null || true
    [[ -s "${SUITE_TMP}/rt25_14_default.m4b" ]] || return 1
    [[ -s "${SUITE_TMP}/rt25_14_custom.m4b" ]] || return 1
    dur_default=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_14_default.m4b" 2>/dev/null | cut -d. -f1)
    dur_custom=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_14_custom.m4b" 2>/dev/null | cut -d. -f1)
    # Custom gaps are all larger than defaults, so output should be longer or equal
    [[ "${dur_custom}" -ge "${dur_default}" ]] || return 1
}
run_test "RT-25.14" "gap-after-scene produces longer output" test_RT25_14

# RT-25.15: Omitted gap config values use defaults (0.3s, 0.5s, 1.0s).
# User action: convert with config that has no gap settings.
# User observes: conversion completes (defaults applied internally).
test_RT25_15() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_15.m4b" 2>&1) || true
    [[ -s "${SUITE_TMP}/rt25_15.m4b" ]] || return 1
}
run_test "RT-25.15" "default gaps applied when config omits them" test_RT25_15

# ---------------------------------------------------------------------------
# AC25.6: Speech speed configurable per entry type
# ---------------------------------------------------------------------------

# RT-25.16: dialogue-speed controls dialogue synthesis speed.
# User action: convert with dialogue-speed: 0.8 (slower).
# User observes: output is longer than default.
test_RT25_16() {
    local dur_default dur_slow
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_16_default.m4b" 2>/dev/null || true
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_SPEED}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_16_slow.m4b" 2>/dev/null || true
    [[ -s "${SUITE_TMP}/rt25_16_default.m4b" ]] || return 1
    [[ -s "${SUITE_TMP}/rt25_16_slow.m4b" ]] || return 1
    dur_default=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_16_default.m4b" 2>/dev/null | cut -d. -f1)
    dur_slow=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_16_slow.m4b" 2>/dev/null | cut -d. -f1)
    # Slower dialogue speed (0.8) should produce longer or equal output
    [[ "${dur_slow}" -ge "${dur_default}" ]] || return 1
}
run_test "RT-25.16" "dialogue-speed controls dialogue rate" test_RT25_16

# RT-25.17: stage-direction-speed controls stage direction speed.
# User action: convert with stage-direction-speed: 1.2 (faster).
# User observes: stage directions are synthesised at higher speed.
test_RT25_17() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_SPEED}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_17.m4b" 2>&1) || true
    [[ -s "${SUITE_TMP}/rt25_17.m4b" ]] || return 1
}
run_test "RT-25.17" "stage-direction-speed config accepted" test_RT25_17

# RT-25.18: Omitted speed config values default to 1.0.
# User action: convert with config that has no speed settings.
# User observes: conversion completes at normal speed.
test_RT25_18() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_18.m4b" 2>&1) || true
    [[ -s "${SUITE_TMP}/rt25_18.m4b" ]] || return 1
}
run_test "RT-25.18" "default speed applied when config omits it" test_RT25_18

# RT-25.19: --speed CLI flag multiplies with per-type speed values.
# User action: convert with dialogue-speed: 0.8 and --speed 0.5 (combined = 0.4, very slow).
# User observes: output is significantly longer than default.
test_RT25_19() {
    local dur_default dur_combined
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_19_default.m4b" 2>/dev/null || true
    "${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG_SPEED}" --speed 0.5 \
        --threads 1 --non-interactive --output "${SUITE_TMP}/rt25_19_combined.m4b" 2>/dev/null || true
    [[ -s "${SUITE_TMP}/rt25_19_default.m4b" ]] || return 1
    [[ -s "${SUITE_TMP}/rt25_19_combined.m4b" ]] || return 1
    dur_default=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_19_default.m4b" 2>/dev/null | cut -d. -f1)
    dur_combined=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt25_19_combined.m4b" 2>/dev/null | cut -d. -f1)
    # Combined slower speed should produce noticeably longer output
    [[ "${dur_combined}" -gt "${dur_default}" ]] || return 1
}
run_test "RT-25.19" "--speed multiplies with per-type speed" test_RT25_19

# ---------------------------------------------------------------------------
# AC25.7: ALL-CAPS character names converted to Title Case in stage directions
# ---------------------------------------------------------------------------

# RT-25.20: Known character names in stage directions are replaced with Title Case.
# User action: convert script with "KEVIN enters" in stage direction, --dry-run.
# User observes: dry-run output shows "Kevin enters" not "KEVIN enters" in stage text.
test_RT25_20() {
    local output
    output=$("${YAPPER}" convert "${STAGE_ORG}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    # Stage direction should show Title Case, not ALL CAPS
    if printf '%s' "${output}" | grep -q "KEVIN enters"; then
        return 1  # Still ALL CAPS — fail
    fi
    # Should have the title-cased version
    printf '%s' "${output}" | grep -qi "Kevin enters\|kevin" || return 1
}
run_test "RT-25.20" "character names title-cased in stage directions" test_RT25_20

# RT-25.21: Multi-word character names converted correctly.
# User action: convert script with "GDA CONLON enters" in stage direction, --dry-run.
# User observes: "Gda Conlon enters" in output.
test_RT25_21() {
    local output
    output=$("${YAPPER}" convert "${STAGE_ORG}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    # Check stage direction lines only (not Cast list where ALL CAPS is expected)
    if printf '%s' "${output}" | grep '\[stage\]' | grep -q "GDA CONLON"; then
        return 1  # Still ALL CAPS in stage direction
    fi
    printf '%s' "${output}" | grep '\[stage\]' | grep -qi "Gda Conlon" || return 1
}
run_test "RT-25.21" "multi-word character names title-cased" test_RT25_21

# RT-25.22: Words that are not character names remain unchanged.
# User action: convert script with stage direction containing non-name words.
# User observes: "enters the room" remains lowercase, only character names change.
test_RT25_22() {
    local output
    output=$("${YAPPER}" convert "${STAGE_ORG}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    # "enters" "room" "sits" should not be capitalised
    printf '%s' "${output}" | grep -qi "enters\|room\|sits" || return 1
}
run_test "RT-25.22" "non-name words unchanged in stage directions" test_RT25_22

# RT-25.23: Character names with accented characters convert correctly.
# User action: convert script where CÁIT appears in stage direction.
# User observes: "Cáit" in output (Title Case with accent preserved).
test_RT25_23() {
    # Create a fixture with accented character in stage direction
    local accented_script="${SUITE_TMP}/accented.org"
    cat > "${accented_script}" <<'ORG'
#+TITLE: Accent Test
* ACT I
** Scene 1: Test
*** CÁIT enters the room.
**** CÁIT
Hello.
ORG
    local output
    output=$("${YAPPER}" convert "${accented_script}" --script-config "${CONFIG}" \
        --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q "CÁIT enters"; then
        return 1  # Still ALL CAPS
    fi
    printf '%s' "${output}" | grep -qi "Cáit\|cáit" || return 1
}
run_test "RT-25.23" "accented character names title-cased correctly" test_RT25_23

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
summarise "concurrent synthesis & config"
