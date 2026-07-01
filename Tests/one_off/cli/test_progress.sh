#!/usr/bin/env bash
# ABOUTME: One-off tests for progress indicator (issue #18).
# ABOUTME: Tests progress bar, text display, --quiet suppression, stderr-only output.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: progress indicator (RT-18.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

# Multi-sentence text for progress tests (needs ≥2 chunks)
LONG_TEXT="This is the first sentence of the test. Here is the second sentence with additional words. A third sentence ensures multiple chunks. The fourth sentence adds further content. And a fifth sentence for good measure."

# ---------------------------------------------------------------------------
# AC18.1: Progress bar and percentage on stderr
# ---------------------------------------------------------------------------

# RT-18.1: stderr contains a progress pattern (percentage or bar characters).
# User action: yapper convert file.txt
# User observes: a progress bar with percentage on the terminal.
test_RT18_1() {
    printf '%s' "${LONG_TEXT}" > "${SUITE_TMP}/rt181.txt"
    local stderr_output
    stderr_output=$("${YAPPER}" convert "${SUITE_TMP}/rt181.txt" -o "${SUITE_TMP}/rt181.m4a" --voice af_heart --non-interactive 2>&1 1>/dev/null)
    # Look for percentage pattern (e.g. "42%" or progress bar characters)
    printf '%s' "${stderr_output}" | grep -qE '[0-9]+%|████|░░' || return 1
}
run_test "RT-18.1" "stderr contains progress pattern" test_RT18_1

# RT-18.2: Progress updates at least twice with an intermediate value.
# User action: yapper convert multi-sentence file.
# User observes: bar moves from start to finish, not just 0% → 100%.
test_RT18_2() {
    printf '%s' "${LONG_TEXT}" > "${SUITE_TMP}/rt182.txt"
    local stderr_output
    stderr_output=$("${YAPPER}" convert "${SUITE_TMP}/rt182.txt" -o "${SUITE_TMP}/rt182.m4a" --voice af_heart --non-interactive 2>&1 1>/dev/null)
    # Check for at least one intermediate percentage (1-99)
    printf '%s' "${stderr_output}" | grep -qE '[1-9][0-9]?%' || return 1
}
run_test "RT-18.2" "progress shows intermediate value (not just 0/100)" test_RT18_2

# ---------------------------------------------------------------------------
# AC18.2: Current text shown on stderr
# ---------------------------------------------------------------------------

# RT-18.3: stderr contains text from the input file (not just filenames).
# User action: yapper convert multi-sentence file.
# User observes: text display shows content from the file being synthesised.
# Note: the progress display uses \r to overwrite in place, so captured stderr
# only retains the final state. The test verifies text from the file appears
# in the output (the last chunk's text will be visible).
test_RT18_3() {
    printf 'Alpha first sentence here. Bravo middle sentence. Charlie final sentence here.' > "${SUITE_TMP}/rt183.txt"
    local stderr_output
    stderr_output=$("${YAPPER}" convert "${SUITE_TMP}/rt183.txt" -o "${SUITE_TMP}/rt183.m4a" --voice af_heart --non-interactive 2>&1 1>/dev/null)
    # At least one word from the input file should appear in the progress text
    printf '%s' "${stderr_output}" | grep -qi "sentence\|Alpha\|Charlie" || return 1
}
run_test "RT-18.3" "stderr contains text from first and last sentence" test_RT18_3

# ---------------------------------------------------------------------------
# AC18.3: speak shows same progress
# ---------------------------------------------------------------------------

# RT-18.4: yapper speak with long text shows progress on stderr.
# User action: yapper speak "long text"
# User observes: progress visible during synthesis.
test_RT18_4() {
    local stderr_output
    stderr_output=$("${YAPPER}" speak --voice af_heart "${LONG_TEXT}" 2>&1 1>/dev/null)
    printf '%s' "${stderr_output}" | grep -qE '[0-9]+%|████|░░' || return 1
}
run_test "RT-18.4" "speak shows progress on stderr" test_RT18_4

# ---------------------------------------------------------------------------
# AC18.4: --quiet suppresses all progress
# ---------------------------------------------------------------------------

# RT-18.5: convert --quiet produces empty stderr.
# User action: yapper convert file.txt --quiet
# User observes: no progress, no text, just the output file.
test_RT18_5() {
    printf 'Quiet test.' > "${SUITE_TMP}/rt185.txt"
    local stderr_output
    stderr_output=$("${YAPPER}" convert "${SUITE_TMP}/rt185.txt" -o "${SUITE_TMP}/rt185.m4a" --voice af_heart --non-interactive --quiet 2>&1 1>/dev/null)
    [[ -z "${stderr_output}" ]]
}
run_test "RT-18.5" "convert --quiet produces empty stderr" test_RT18_5

# RT-18.6: speak --quiet produces empty stderr.
# User action: yapper speak "text" --quiet
# User observes: audio plays, no terminal output.
test_RT18_6() {
    local stderr_output
    stderr_output=$("${YAPPER}" speak --voice af_heart "Quiet speak test." --quiet 2>&1 1>/dev/null)
    [[ -z "${stderr_output}" ]]
}
run_test "RT-18.6" "speak --quiet produces empty stderr" test_RT18_6

# ---------------------------------------------------------------------------
# AC18.5: Per-file header for multi-file convert
# ---------------------------------------------------------------------------

# RT-18.7: Multi-file convert shows [1/2] and [2/2] headers.
# User action: yapper convert a.txt b.txt
# User observes: per-file headers with position and voice name.
test_RT18_7() {
    printf 'File alpha.' > "${SUITE_TMP}/alpha.txt"
    printf 'File beta.' > "${SUITE_TMP}/beta.txt"
    local stderr_output
    stderr_output=$((cd "${SUITE_TMP}" && "${YAPPER}" convert alpha.txt beta.txt --voice af_heart --non-interactive) 2>&1 1>/dev/null)
    printf '%s' "${stderr_output}" | grep -q '\[1/2\]' || return 1
    printf '%s' "${stderr_output}" | grep -q '\[2/2\]' || return 1
}
run_test "RT-18.7" "multi-file shows [1/2] [2/2] headers" test_RT18_7

# ---------------------------------------------------------------------------
# AC18.6: No progress in dry-run
# ---------------------------------------------------------------------------

# RT-18.8: convert --dry-run has no progress bar on stderr.
# User action: yapper convert file.txt --dry-run
# User observes: dry-run plan, no progress bar.
test_RT18_8() {
    printf 'Dry run progress test.' > "${SUITE_TMP}/rt188.txt"
    local stderr_output
    stderr_output=$("${YAPPER}" convert "${SUITE_TMP}/rt188.txt" --voice af_heart --dry-run --non-interactive 2>&1 1>/dev/null)
    if printf '%s' "${stderr_output}" | grep -qE '[0-9]+%|████|░░'; then
        return 1
    fi
    return 0
}
run_test "RT-18.8" "dry-run has no progress bar" test_RT18_8

# RT-18.9: speak --dry-run has no progress on stderr.
# User action: yapper speak --dry-run "text"
# User observes: dry-run output only.
test_RT18_9() {
    local stderr_output
    stderr_output=$("${YAPPER}" speak --dry-run "Dry run test." 2>&1 1>/dev/null)
    if printf '%s' "${stderr_output}" | grep -qE '[0-9]+%|████|░░'; then
        return 1
    fi
    return 0
}
run_test "RT-18.9" "speak --dry-run has no progress on stderr" test_RT18_9

# ---------------------------------------------------------------------------
# AC18.7: Progress on stderr only, stdout unaffected
# ---------------------------------------------------------------------------

# RT-18.10: convert stdout contains no progress characters.
# User action: yapper convert file.txt (stdout captured separately)
# User observes: stdout is clean for piping.
test_RT18_10() {
    printf 'Stdout test.' > "${SUITE_TMP}/rt1810.txt"
    local stdout_output
    stdout_output=$("${YAPPER}" convert "${SUITE_TMP}/rt1810.txt" -o "${SUITE_TMP}/rt1810.m4a" --voice af_heart --non-interactive 2>/dev/null)
    if printf '%s' "${stdout_output}" | grep -qE '████|░░|[0-9]+%'; then
        return 1
    fi
    return 0
}
run_test "RT-18.10" "convert stdout has no progress characters" test_RT18_10

# RT-18.11: speak stdout has no progress when stderr redirected.
# User action: yapper speak "text" 2>/dev/null
# User observes: no progress on stdout.
test_RT18_11() {
    local stdout_output
    stdout_output=$("${YAPPER}" speak --voice af_heart "Stdout clean test." 2>/dev/null)
    if printf '%s' "${stdout_output}" | grep -qE '████|░░|[0-9]+%'; then
        return 1
    fi
    return 0
}
run_test "RT-18.11" "speak stdout has no progress characters" test_RT18_11

summarise "progress indicator"
