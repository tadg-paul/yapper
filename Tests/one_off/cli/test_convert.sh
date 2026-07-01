#!/usr/bin/env bash
# ABOUTME: One-off tests for `yapper convert` (issue #6).
# ABOUTME: Each test invokes the built yapper binary exactly as a user would.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: yapper convert (RT-6.x)\n'

# Shared temp directory for this suite
SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

# ---------------------------------------------------------------------------
# Issue #6: plain text to audio file conversion
# Specs from: https://github.com/tigger04/yapper/issues/6
# ---------------------------------------------------------------------------

# RT-6.1: Output file exists and is valid M4A (ffprobe confirms).
# User action: yapper convert input.txt -o output.m4a
# User observes: output.m4a exists, plays in any audio player.
test_RT6_1() {
    printf 'Hello world.' > "${SUITE_TMP}/rt61.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt61.txt" -o "${SUITE_TMP}/rt61.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${SUITE_TMP}/rt61.m4a" ]] || return 1
    ffprobe -v quiet -show_entries format=format_name -of csv=p=0 "${SUITE_TMP}/rt61.m4a" 2>/dev/null | grep -qE "m4a|mov"
}
run_test "RT-6.1" "output is valid M4A" test_RT6_1

# RT-6.2: Output audio duration is proportional to input text length.
# User action: convert short text, convert long text, compare durations.
# User observes: longer text produces longer audio.
test_RT6_2() {
    printf 'Hi.' > "${SUITE_TMP}/rt62_short.txt"
    printf 'This is a much longer sentence with many more words to speak aloud during this test.' > "${SUITE_TMP}/rt62_long.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt62_short.txt" -o "${SUITE_TMP}/rt62_short.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${SUITE_TMP}/rt62_long.txt" -o "${SUITE_TMP}/rt62_long.m4a" --voice af_heart >/dev/null 2>&1
    local short_size long_size
    short_size=$(stat -f%z "${SUITE_TMP}/rt62_short.m4a")
    long_size=$(stat -f%z "${SUITE_TMP}/rt62_long.m4a")
    [[ ${long_size} -gt ${short_size} ]]
}
run_test "RT-6.2" "duration proportional to text length" test_RT6_2

# RT-6.3: yapper convert notes.txt produces notes.m4a (default output name).
# User action: yapper convert notes.txt (no -o flag)
# User observes: notes.m4a appears in the same directory.
test_RT6_3() {
    local dir="${SUITE_TMP}/rt63"
    mkdir -p "${dir}"
    printf 'Default name test.' > "${dir}/notes.txt"
    (cd "${dir}" && "${YAPPER}" convert notes.txt --voice af_heart >/dev/null 2>&1)
    [[ -f "${dir}/notes.m4a" ]]
}
run_test "RT-6.3" "default output name is input.m4a" test_RT6_3

# RT-6.4: Explicit -o flag overrides the default name.
# User action: yapper convert input.txt -o custom.m4a
# User observes: custom.m4a exists, input.m4a does not.
test_RT6_4() {
    local dir="${SUITE_TMP}/rt64"
    mkdir -p "${dir}"
    printf 'Override test.' > "${dir}/input.txt"
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/custom.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${dir}/custom.m4a" ]] && [[ ! -f "${dir}/input.m4a" ]]
}
run_test "RT-6.4" "explicit -o overrides default name" test_RT6_4

# RT-6.5: --voice am_adam produces audio with the specified voice.
# User action: yapper convert file.txt --voice am_adam --dry-run
# User observes: dry-run output shows voice: am_adam.
test_RT6_5() {
    printf 'Voice test.' > "${SUITE_TMP}/rt65.txt"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt65.txt" --voice am_adam --dry-run 2>&1)
    printf '%s' "${output}" | grep -qi "am_adam"
}
run_test "RT-6.5" "--voice selects the specified voice" test_RT6_5

# RT-6.6: --speed 1.5 produces shorter audio than default.
# User action: convert same text at normal and fast speed, compare.
# User observes: fast output file is smaller.
test_RT6_6() {
    printf 'Speed test sentence with enough words.' > "${SUITE_TMP}/rt66.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt66.txt" -o "${SUITE_TMP}/rt66_normal.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${SUITE_TMP}/rt66.txt" -o "${SUITE_TMP}/rt66_fast.m4a" --voice af_heart --speed 1.5 >/dev/null 2>&1
    local normal_size fast_size
    normal_size=$(stat -f%z "${SUITE_TMP}/rt66_normal.m4a")
    fast_size=$(stat -f%z "${SUITE_TMP}/rt66_fast.m4a")
    [[ ${fast_size} -lt ${normal_size} ]]
}
run_test "RT-6.6" "--speed 1.5 produces shorter audio" test_RT6_6

# RT-6.7: --author "Name" sets the artist ID3 tag.
# User action: yapper convert file.txt --author "Test Author" -o out.m4a
# User observes: ffprobe shows artist=Test Author.
test_RT6_7() {
    printf 'Metadata test.' > "${SUITE_TMP}/rt67.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt67.txt" -o "${SUITE_TMP}/rt67.m4a" --voice af_heart --author "Test Author" >/dev/null 2>&1
    ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt67.m4a" 2>/dev/null | grep -q "Test Author"
}
run_test "RT-6.7" "--author embeds artist metadata" test_RT6_7

# RT-6.9: Missing input file produces descriptive error.
# User action: yapper convert nonexistent.txt
# User observes: error message, non-zero exit.
test_RT6_9() {
    if "${YAPPER}" convert "${SUITE_TMP}/nonexistent_file.txt" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.9" "missing input file produces error" test_RT6_9

# RT-6.10: Missing ffmpeg produces actionable error message.
# This test checks the error-path code, not the actual ffmpeg presence.
# We keep the existing Swift implementation since it manipulates PATH
# to simulate ffmpeg absence — that's an engine-level concern.
# See #17 for the KEEP decision.

# RT-6.13: Empty text file produces descriptive error.
# User action: yapper convert empty.txt
# User observes: error message, non-zero exit.
test_RT6_13() {
    printf '' > "${SUITE_TMP}/rt613.txt"
    if "${YAPPER}" convert "${SUITE_TMP}/rt613.txt" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.13" "empty file produces error" test_RT6_13

# RT-6.14: Whitespace-only file produces descriptive error.
# User action: yapper convert whitespace.txt
# User observes: error message, non-zero exit.
test_RT6_14() {
    printf '   \n\t  \n' > "${SUITE_TMP}/rt614.txt"
    if "${YAPPER}" convert "${SUITE_TMP}/rt614.txt" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.14" "whitespace-only file produces error" test_RT6_14

# RT-6.15: Existing output file is renamed to .bak before overwriting.
# User action: yapper convert file.txt twice to same output path.
# User observes: output.m4a exists, output.m4a.bak exists.
test_RT6_15() {
    local dir="${SUITE_TMP}/rt615"
    mkdir -p "${dir}"
    printf 'Backup test.' > "${dir}/input.txt"
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${dir}/output.m4a" ]] && [[ -f "${dir}/output.m4a.bak" ]]
}
run_test "RT-6.15" "existing output backed up to .bak" test_RT6_15

# RT-6.16: Multiple runs produce .bak, .1.bak, .2.bak etc.
# User action: yapper convert file.txt three times to same output path.
# User observes: output.m4a, output.m4a.bak, output.m4a.1.bak all exist.
test_RT6_16() {
    local dir="${SUITE_TMP}/rt616"
    mkdir -p "${dir}"
    printf 'Incremental backup test.' > "${dir}/input.txt"
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${dir}/output.m4a" ]] && [[ -f "${dir}/output.m4a.bak" ]] && ls "${dir}"/output.m4a.*.bak >/dev/null 2>&1
}
run_test "RT-6.16" "incremental backups (.bak, .1.bak)" test_RT6_16

# RT-6.19: Multiple input files produce multiple output files.
# User action: yapper convert a.txt b.txt c.txt
# User observes: a.m4a, b.m4a, c.m4a all exist.
test_RT6_19() {
    local dir="${SUITE_TMP}/rt619"
    mkdir -p "${dir}"
    printf 'File A.' > "${dir}/a.txt"
    printf 'File B.' > "${dir}/b.txt"
    printf 'File C.' > "${dir}/c.txt"
    (cd "${dir}" && "${YAPPER}" convert a.txt b.txt c.txt --voice af_heart >/dev/null 2>&1)
    [[ -f "${dir}/a.m4a" ]] && [[ -f "${dir}/b.m4a" ]] && [[ -f "${dir}/c.m4a" ]]
}
run_test "RT-6.19" "multiple inputs produce multiple outputs" test_RT6_19

# RT-6.21: Zero input files produces descriptive error.
# User action: yapper convert (no arguments)
# User observes: error message, non-zero exit.
test_RT6_21() {
    if "${YAPPER}" convert >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.21" "zero inputs produces error" test_RT6_21

# RT-6.8: --title "Title" sets the album ID3 tag.
# User action: yapper convert file.txt --title "My Book"
# User observes: ffprobe shows album=My Book.
test_RT6_8() {
    printf 'Title metadata test.' > "${SUITE_TMP}/rt68.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt68.txt" -o "${SUITE_TMP}/rt68.m4a" --voice af_heart --title "My Book" >/dev/null 2>&1
    ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${SUITE_TMP}/rt68.m4a" 2>/dev/null | grep -q "My Book"
}
run_test "RT-6.8" "--title embeds album metadata" test_RT6_8

# RT-6.10: Missing ffmpeg produces actionable error message.
# ffmpeg discovery uses hardcoded paths (/opt/homebrew/bin, /usr/local/bin,
# /usr/bin), not PATH, so this cannot be tested by restricting PATH.
# The underlying error path is tested in the Swift framework suite.
# Skipped at CLI level — tracked in #17.

# RT-6.11: --dry-run outputs the planned actions.
# User action: yapper convert file.txt --dry-run
# User observes: voice, speed, input, output in stdout, no file created.
test_RT6_11() {
    printf 'Dry run test.' > "${SUITE_TMP}/rt611.txt"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt611.txt" --voice af_heart --dry-run 2>&1)
    printf '%s' "${output}" | grep -qi "voice\|af_heart" || return 1
    printf '%s' "${output}" | grep -qi "output\|rt611" || return 1
}
run_test "RT-6.11" "--dry-run outputs planned actions" test_RT6_11

# RT-6.12: --dry-run does not create any output files.
# User action: yapper convert file.txt --dry-run
# User observes: no output file created.
test_RT6_12() {
    local dir="${SUITE_TMP}/rt612"
    mkdir -p "${dir}"
    printf 'Dry run no-create test.' > "${dir}/input.txt"
    (cd "${dir}" && "${YAPPER}" convert input.txt --voice af_heart --dry-run >/dev/null 2>&1)
    [[ ! -f "${dir}/input.m4a" ]]
}
run_test "RT-6.12" "--dry-run does not create output files" test_RT6_12

# RT-6.17: Latin-1 encoded file produces error mentioning encoding.
# User action: yapper convert latin1.txt
# User observes: error about encoding, non-zero exit.
test_RT6_17() {
    # Create a file with Latin-1 bytes (0xe9 = é in Latin-1, invalid UTF-8 sequence)
    printf 'Caf\xe9 au lait' > "${SUITE_TMP}/rt617.txt"
    local output
    if output=$("${YAPPER}" convert "${SUITE_TMP}/rt617.txt" 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "utf-8\|encoding"
}
run_test "RT-6.17" "Latin-1 file produces encoding error" test_RT6_17

# RT-6.18: Binary file produces error distinguishable from encoding error.
# User action: yapper convert binary.dat
# User observes: error, non-zero exit.
test_RT6_18() {
    printf '\x00\x01\x02\x03\xff\xfe\xfd' > "${SUITE_TMP}/rt618.bin"
    if "${YAPPER}" convert "${SUITE_TMP}/rt618.bin" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.18" "binary file produces error" test_RT6_18

# RT-6.20: Failure in one file does not prevent processing of subsequent files.
# User action: yapper convert good.txt missing.txt good2.txt
# User observes: good.m4a and good2.m4a exist despite missing.txt failing.
test_RT6_20() {
    local dir="${SUITE_TMP}/rt620"
    mkdir -p "${dir}"
    printf 'Good file one.' > "${dir}/good.txt"
    printf 'Good file two.' > "${dir}/good2.txt"
    # missing.txt intentionally does not exist
    (cd "${dir}" && "${YAPPER}" convert good.txt missing.txt good2.txt --voice af_heart 2>/dev/null) || true
    [[ -f "${dir}/good.m4a" ]] && [[ -f "${dir}/good2.m4a" ]]
}
run_test "RT-6.20" "failure in one file does not prevent others" test_RT6_20

# RT-6.22: MP3 output via --format mp3 is valid.
# User action: yapper convert file.txt --format mp3
# User observes: valid MP3 file.
test_RT6_22() {
    printf 'MP3 test.' > "${SUITE_TMP}/rt622.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt622.txt" -o "${SUITE_TMP}/rt622.mp3" --voice af_heart --format mp3 >/dev/null 2>&1
    [[ -f "${SUITE_TMP}/rt622.mp3" ]] || return 1
    ffprobe -v quiet -show_entries format=format_name -of csv=p=0 "${SUITE_TMP}/rt622.mp3" 2>/dev/null | grep -q "mp3"
}
run_test "RT-6.22" "MP3 output is valid" test_RT6_22

# RT-6.23: MP3 output has correct audio duration.
# User action: yapper convert file.txt --format mp3
# User observes: MP3 duration is non-trivial (>0.5s).
test_RT6_23() {
    [[ -f "${SUITE_TMP}/rt622.mp3" ]] || return 1
    local duration
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${SUITE_TMP}/rt622.mp3" 2>/dev/null)
    # Check duration is a number > 0.5
    [[ -n "${duration}" ]] && awk "BEGIN{exit(${duration} > 0.5 ? 0 : 1)}"
}
run_test "RT-6.23" "MP3 output has correct duration" test_RT6_23

# RT-6.24: Output to a non-existent output directory produces error.
# User action: yapper convert file.txt -o /nonexistent/path/output.m4a
# User observes: error, non-zero exit.
test_RT6_24() {
    printf 'Directory test.' > "${SUITE_TMP}/rt624.txt"
    if "${YAPPER}" convert "${SUITE_TMP}/rt624.txt" -o "/nonexistent/path/output.m4a" --voice af_heart >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.24" "missing output directory produces error" test_RT6_24

# RT-6.25: Error message names the missing directory.
# User action: yapper convert file.txt -o /nonexistent/path/output.m4a
# User observes: error message mentions the directory.
test_RT6_25() {
    printf 'Directory test.' > "${SUITE_TMP}/rt625.txt"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt625.txt" -o "/nonexistent/path/output.m4a" --voice af_heart 2>&1) || true
    printf '%s' "${output}" | grep -q "nonexistent"
}
run_test "RT-6.25" "error message names the missing directory" test_RT6_25

summarise "yapper convert"
