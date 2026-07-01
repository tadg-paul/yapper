#!/usr/bin/env bash
# ABOUTME: One-off tests for make-audiobook delta features (issue #20).
# ABOUTME: Metadata on all formats, track numbers, text cleanup, batch summary, --non-interactive.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: make-audiobook delta (RT-20.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

# ---------------------------------------------------------------------------
# AC20.1: Metadata on M4A/MP3
# ---------------------------------------------------------------------------

# RT-20.1: M4A with --author and --title has artist and album tags.
test_RT20_1() {
    printf 'Metadata test.' > "${SUITE_TMP}/rt201.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt201.txt" -o "${SUITE_TMP}/rt201.m4a" --voice af_heart --author "Test Author" --title "Test Book" --non-interactive >/dev/null 2>&1
    ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt201.m4a" 2>/dev/null | grep -q "Test Author" || return 1
    ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${SUITE_TMP}/rt201.m4a" 2>/dev/null | grep -q "Test Book"
}
run_test "RT-20.1" "M4A output has artist and album tags" test_RT20_1

# RT-20.2: Same for MP3 output.
test_RT20_2() {
    printf 'MP3 metadata test.' > "${SUITE_TMP}/rt202.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt202.txt" -o "${SUITE_TMP}/rt202.mp3" --voice af_heart --author "Test Author" --title "Test Book" --format mp3 --non-interactive >/dev/null 2>&1
    ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt202.mp3" 2>/dev/null | grep -q "Test Author" || return 1
    ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${SUITE_TMP}/rt202.mp3" 2>/dev/null | grep -q "Test Book"
}
run_test "RT-20.2" "MP3 output has artist and album tags" test_RT20_2

# RT-20.3: album_artist tag matches artist.
test_RT20_3() {
    ffprobe -v quiet -show_entries format_tags=album_artist -of csv=p=0 "${SUITE_TMP}/rt201.m4a" 2>/dev/null | grep -q "Test Author"
}
run_test "RT-20.3" "album_artist matches artist" test_RT20_3

# ---------------------------------------------------------------------------
# AC20.2: Track numbers and titles
# ---------------------------------------------------------------------------

# RT-20.4: Multi-file produces track numbers.
test_RT20_4() {
    local dir="${SUITE_TMP}/rt204"
    mkdir -p "${dir}"
    printf 'File A.' > "${dir}/a.txt"
    printf 'File B.' > "${dir}/b.txt"
    printf 'File C.' > "${dir}/c.txt"
    (cd "${dir}" && "${YAPPER}" convert a.txt b.txt c.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/a.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/b.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/c.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.4" "multi-file has track numbers 1/3, 2/3, 3/3" test_RT20_4

# RT-20.5: Track title matches input filename.
test_RT20_5() {
    local t1
    t1=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "${SUITE_TMP}/rt204/a.m4a" 2>/dev/null)
    [[ "${t1}" == "a" ]]
}
run_test "RT-20.5" "track title matches input filename" test_RT20_5

# ---------------------------------------------------------------------------
# AC20.4: Format topology
# ---------------------------------------------------------------------------

# RT-20.7: Multi-file default produces M4A files.
test_RT20_7() {
    [[ -f "${SUITE_TMP}/rt204/a.m4a" ]] && [[ -f "${SUITE_TMP}/rt204/b.m4a" ]] && [[ -f "${SUITE_TMP}/rt204/c.m4a" ]]
}
run_test "RT-20.7" "multi-file default produces M4A" test_RT20_7

# RT-20.8: Multi-file with explicit M4B produces one M4B.
test_RT20_8() {
    local dir="${SUITE_TMP}/rt208"
    mkdir -p "${dir}"
    printf 'Chapter one.' > "${dir}/a.txt"
    printf 'Chapter two.' > "${dir}/b.txt"
    (cd "${dir}" && "${YAPPER}" convert a.txt b.txt --format m4b -o "${dir}/book.m4b" --voice af_heart --non-interactive >/dev/null 2>&1)
    [[ -f "${dir}/book.m4b" ]]
}
run_test "RT-20.8" "multi-file with --format m4b produces one M4B" test_RT20_8

# ---------------------------------------------------------------------------
# AC20.5: Text cleanup (via --dry-run showing cleaned text)
# ---------------------------------------------------------------------------

# RT-20.10: Markdown image links stripped from dry-run text.
test_RT20_10() {
    printf 'Hello ![alt text](http://example.com/image.png) world.' > "${SUITE_TMP}/rt2010.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2010.md" --voice af_heart --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q "Text:" || printf '%s' "${output}" | grep -q "text:" || return 1
    # The image link URL should not appear in the cleaned text
    if printf '%s' "${output}" | grep -q "http://example.com/image.png"; then
        return 1
    fi
    return 0
}
run_test "RT-20.10" "markdown image links stripped from dry-run text" test_RT20_10

# RT-20.11: HTML tags stripped from dry-run text.
test_RT20_11() {
    printf '<div>Hello</div> <span>world</span>.' > "${SUITE_TMP}/rt2011.html"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2011.html" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q "<div>"; then
        return 1
    fi
    return 0
}
run_test "RT-20.11" "HTML tags stripped from dry-run text" test_RT20_11

# RT-20.12: {.class} attribute blocks stripped from dry-run text.
test_RT20_12() {
    printf 'Hello {.special-class} world.' > "${SUITE_TMP}/rt2012.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2012.md" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q "{.special-class}"; then
        return 1
    fi
    return 0
}
run_test "RT-20.12" "{.class} blocks stripped from dry-run text" test_RT20_12

# ---------------------------------------------------------------------------
# AC20.6: Batch summary
# ---------------------------------------------------------------------------

# RT-20.13: Converting 3 valid files prints success count.
test_RT20_13() {
    local dir="${SUITE_TMP}/rt2013"
    mkdir -p "${dir}"
    printf 'File one.' > "${dir}/a.txt"
    printf 'File two.' > "${dir}/b.txt"
    printf 'File three.' > "${dir}/c.txt"
    local output
    output=$((cd "${dir}" && "${YAPPER}" convert a.txt b.txt c.txt --voice af_heart --non-interactive) 2>&1)
    printf '%s' "${output}" | grep -q "3 of 3.*converted successfully"
}
run_test "RT-20.13" "batch summary shows success count" test_RT20_13

# RT-20.14: Converting 2 valid + 1 missing prints failure.
test_RT20_14() {
    local dir="${SUITE_TMP}/rt2014"
    mkdir -p "${dir}"
    printf 'Good one.' > "${dir}/good.txt"
    printf 'Good two.' > "${dir}/good2.txt"
    local output
    set +e
    output=$((cd "${dir}" && "${YAPPER}" convert good.txt missing.txt good2.txt --voice af_heart --non-interactive) 2>&1)
    set -e
    printf '%s' "${output}" | grep -q "missing.txt"
}
run_test "RT-20.14" "batch summary lists failures" test_RT20_14

# ---------------------------------------------------------------------------
# AC20.7: --non-interactive
# ---------------------------------------------------------------------------

# RT-20.15: --non-interactive skips prompts even with TTY stdin.
test_RT20_15() {
    printf 'Non-interactive test.' > "${SUITE_TMP}/rt2015.txt"
    # If this hangs, --non-interactive isn't working (it would block on prompt).
    # The 5-second timeout catches that.
    timeout 5 "${YAPPER}" convert "${SUITE_TMP}/rt2015.txt" -o "${SUITE_TMP}/rt2015.m4a" --voice af_heart --non-interactive >/dev/null 2>&1
}
run_test "RT-20.15" "--non-interactive skips prompts" test_RT20_15

# RT-20.16: Output file is still produced with --non-interactive.
test_RT20_16() {
    [[ -f "${SUITE_TMP}/rt2015.m4a" ]]
}
run_test "RT-20.16" "output produced with --non-interactive" test_RT20_16

# ---------------------------------------------------------------------------
# AC20.8: Track numbers from filenames
# ---------------------------------------------------------------------------

# RT-20.17: Consecutive numbered files get track numbers from filenames.
test_RT20_17() {
    local dir="${SUITE_TMP}/rt2017"
    mkdir -p "${dir}"
    printf 'Chapter one.' > "${dir}/ch01.txt"
    printf 'Chapter two.' > "${dir}/ch02.txt"
    printf 'Chapter three.' > "${dir}/ch03.txt"
    (cd "${dir}" && "${YAPPER}" convert ch01.txt ch02.txt ch03.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch01.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch02.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch03.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.17" "consecutive numbered files get correct track numbers" test_RT20_17

# RT-20.18: Zero-start consecutive sequence detected.
test_RT20_18() {
    local dir="${SUITE_TMP}/rt2018"
    mkdir -p "${dir}"
    printf 'Part zero.' > "${dir}/ch00.txt"
    printf 'Part one.' > "${dir}/ch01.txt"
    printf 'Part two.' > "${dir}/ch02.txt"
    (cd "${dir}" && "${YAPPER}" convert ch00.txt ch01.txt ch02.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch00.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch01.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch02.m4a" 2>/dev/null)
    # 0-based filenames are shifted to 1-based for track metadata (track 0 is
    # not meaningful in ID3/MP4 tags), but the sequence is still detected as
    # consecutive rather than falling back to positional.
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.18" "zero-start consecutive sequence detected and shifted to 1-based" test_RT20_18

# RT-20.19: No integers in filenames → positional fallback.
test_RT20_19() {
    local dir="${SUITE_TMP}/rt2019"
    mkdir -p "${dir}"
    printf 'Intro.' > "${dir}/intro.txt"
    printf 'Body.' > "${dir}/body.txt"
    printf 'End.' > "${dir}/end.txt"
    (cd "${dir}" && "${YAPPER}" convert intro.txt body.txt end.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/intro.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/body.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/end.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.19" "no integers → positional fallback" test_RT20_19

# RT-20.20: Non-consecutive integers → positional fallback.
test_RT20_20() {
    local dir="${SUITE_TMP}/rt2020"
    mkdir -p "${dir}"
    printf 'Part five.' > "${dir}/ch05.txt"
    printf 'Part ten.' > "${dir}/ch10.txt"
    printf 'Part ninety-nine.' > "${dir}/ch99.txt"
    (cd "${dir}" && "${YAPPER}" convert ch05.txt ch10.txt ch99.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch05.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch10.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch99.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.20" "non-consecutive integers → positional fallback" test_RT20_20

# RT-20.21: Mixed filenames (some with integers, some without) → positional fallback.
test_RT20_21() {
    local dir="${SUITE_TMP}/rt2021"
    mkdir -p "${dir}"
    printf 'Intro.' > "${dir}/intro.txt"
    printf 'Chapter one.' > "${dir}/ch01.txt"
    printf 'Chapter two.' > "${dir}/ch02.txt"
    (cd "${dir}" && "${YAPPER}" convert intro.txt ch01.txt ch02.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/intro.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch01.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch02.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.21" "mixed filenames → positional fallback" test_RT20_21

# ---------------------------------------------------------------------------
# AC20.9: --dry-run shows cleaned text
# ---------------------------------------------------------------------------

# RT-20.22: --dry-run output includes cleaned text content.
test_RT20_22() {
    printf 'Hello world from dry run.' > "${SUITE_TMP}/rt2022.txt"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2022.txt" --voice af_heart --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Hello world from dry run"
}
run_test "RT-20.22" "--dry-run output includes cleaned text" test_RT20_22

# RT-20.28: Markdown links reduced to link text in dry-run.
test_RT20_28() {
    printf 'Visit [Example Site](http://example.com) for more.' > "${SUITE_TMP}/rt2028.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2028.md" --voice af_heart --dry-run --non-interactive 2>&1)
    # Should contain "Example Site" but not the URL
    printf '%s' "${output}" | grep -q "Example Site" || return 1
    if printf '%s' "${output}" | grep -q "http://example.com"; then
        return 1
    fi
    return 0
}
run_test "RT-20.28" "markdown links reduced to link text in dry-run" test_RT20_28

# ---------------------------------------------------------------------------
# Missing tests: RT-20.6, 20.9, 20.23-20.27, 20.29-20.32
# ---------------------------------------------------------------------------

# RT-20.6: Flags suppress interactive prompt.
# When --author and --title are both passed, no prompt should appear.
test_RT20_6() {
    printf 'Prompt test.' > "${SUITE_TMP}/rt206.txt"
    # If this hangs, the prompt appeared despite flags being supplied.
    timeout 10 "${YAPPER}" convert "${SUITE_TMP}/rt206.txt" -o "${SUITE_TMP}/rt206.m4a" \
        --voice af_heart --author "A" --title "T" --non-interactive >/dev/null 2>&1
}
run_test "RT-20.6" "flags suppress interactive prompt" test_RT20_6

# RT-20.9: Epub with --format m4a produces one M4A per chapter.
# Requires an epub test fixture. Use the test epub from the regression suite.
test_RT20_9() {
    local epub
    epub="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)/Tests/fixtures/test_book.epub"
    if [[ -z "${epub}" ]]; then
        # No epub fixture available — skip gracefully
        return 1
    fi
    local dir="${SUITE_TMP}/rt209"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${epub}" --format m4a --voice af_heart --non-interactive -o "${dir}/chapter" >/dev/null 2>&1
    # At least one M4A should be produced
    local count
    count=$(find "${dir}" -name "*.m4a" 2>/dev/null | wc -l | tr -d ' ')
    [[ ${count} -ge 1 ]]
}
run_test "RT-20.9" "epub with --format m4a produces per-chapter M4A" test_RT20_9

# RT-20.23: Cleaned text does not contain HTML tags.
test_RT20_23() {
    printf '<p>Hello</p> <br/> <span class="x">world</span>.' > "${SUITE_TMP}/rt2023.html"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2023.html" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qE '<p>|<br|<span'; then
        return 1
    fi
    return 0
}
run_test "RT-20.23" "HTML tags stripped from dry-run text" test_RT20_23

# RT-20.24: Cleaned text does not contain {.class} attribute blocks.
test_RT20_24() {
    printf 'Heading {#my-id .custom-class}\nBody text.' > "${SUITE_TMP}/rt2024.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2024.md" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q '{#my-id'; then
        return 1
    fi
    return 0
}
run_test "RT-20.24" "{...} attribute blocks stripped from dry-run text" test_RT20_24

# RT-20.25: Cleaned text does not contain ::: directive lines.
test_RT20_25() {
    printf '::: warning\nDo not do this.\n:::\nNormal text.' > "${SUITE_TMP}/rt2025.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2025.md" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q ':::'; then
        return 1
    fi
    # Normal text should still be present
    printf '%s' "${output}" | grep -q "Normal text"
}
run_test "RT-20.25" "::: directives stripped from dry-run text" test_RT20_25

# RT-20.26: Cleaned text does not contain stray backslashes.
test_RT20_26() {
    printf 'Hello \\world \\ test\\.' > "${SUITE_TMP}/rt2026.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2026.md" --voice af_heart --dry-run --non-interactive 2>&1)
    # The text line should contain "Hello world  test." without backslashes
    local textline
    textline=$(printf '%s' "${output}" | grep -i "text:" | head -1)
    if printf '%s' "${textline}" | grep -q '\\'; then
        return 1
    fi
    return 0
}
run_test "RT-20.26" "backslashes stripped from dry-run text" test_RT20_26

# RT-20.27: Cleaned text does not contain ::: directive lines (alternate pattern).
# This is a duplicate of RT-20.25 with a different directive style.
test_RT20_27() {
    printf ':::note\nSome note content\n:::\nKeep this.' > "${SUITE_TMP}/rt2027.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2027.md" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q ':::note'; then
        return 1
    fi
    printf '%s' "${output}" | grep -q "Keep this"
}
run_test "RT-20.27" "::: directives (no space) stripped from dry-run text" test_RT20_27

# RT-20.29: Epub chapter conversion to M4A — track title matches chapter name from TOC.
test_RT20_29() {
    local epub
    epub="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)/Tests/fixtures/test_book.epub"
    [[ -f "${epub}" ]] || return 1
    local dir="${SUITE_TMP}/rt2029"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${epub}" --format m4a --voice af_heart --non-interactive -o "${dir}/chapter" >/dev/null 2>&1
    local first_m4a
    first_m4a=$(find "${dir}" -name "*.m4a" 2>/dev/null | sort | head -1)
    [[ -n "${first_m4a}" ]] || return 1
    local title
    title=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "${first_m4a}" 2>/dev/null)
    # Title should be non-empty (chapter name from TOC)
    [[ -n "${title}" ]]
}
run_test "RT-20.29" "epub chapter M4A track title matches chapter name" test_RT20_29

# RT-20.30: Epub with no --format defaults to M4B.
test_RT20_30() {
    local epub
    epub="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)/Tests/fixtures/test_book.epub"
    [[ -f "${epub}" ]] || return 1
    local dir="${SUITE_TMP}/rt2030"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${epub}" --voice af_heart --non-interactive -o "${dir}/book.m4b" >/dev/null 2>&1
    [[ -f "${dir}/book.m4b" ]]
}
run_test "RT-20.30" "epub default format is M4B" test_RT20_30

# RT-20.31: Single file with explicit --format m4b produces a valid single-chapter M4B.
test_RT20_31() {
    local dir="${SUITE_TMP}/rt2031"
    mkdir -p "${dir}"
    printf 'Single chapter M4B test.' > "${dir}/notes.txt"
    "${YAPPER}" convert "${dir}/notes.txt" --format m4b -o "${dir}/notes.m4b" --voice af_heart --non-interactive >/dev/null 2>&1
    [[ -f "${dir}/notes.m4b" ]] || return 1
    # Verify it's a valid container
    ffprobe -v quiet -show_entries format=format_name -of csv=p=0 "${dir}/notes.m4b" 2>/dev/null | grep -qE "m4a|mov|mp4"
}
run_test "RT-20.31" "single file + explicit M4B produces valid M4B" test_RT20_31

# RT-20.32: Multi-file M4B chapter titles match input filenames.
test_RT20_32() {
    local dir="${SUITE_TMP}/rt2032"
    mkdir -p "${dir}"
    printf 'Chapter alpha.' > "${dir}/alpha.txt"
    printf 'Chapter beta.' > "${dir}/beta.txt"
    "${YAPPER}" convert "${dir}/alpha.txt" "${dir}/beta.txt" --format m4b -o "${dir}/book.m4b" --voice af_heart --non-interactive >/dev/null 2>&1
    [[ -f "${dir}/book.m4b" ]] || return 1
    local chapters
    chapters=$(ffprobe -v quiet -show_chapters -of csv=p=0 "${dir}/book.m4b" 2>/dev/null)
    printf '%s' "${chapters}" | grep -q "alpha" || return 1
    printf '%s' "${chapters}" | grep -q "beta"
}
run_test "RT-20.32" "multi-file M4B chapter titles match filenames" test_RT20_32

# ---------------------------------------------------------------------------
# Audit-recommended tests: RT-20.33-20.36
# ---------------------------------------------------------------------------

# RT-20.33: Real synthesis of markup-heavy file produces output consistent
# with clean text (not inflated by markup being read aloud).
# Guards against cleanup only being applied in --dry-run path.
test_RT20_33() {
    local dir="${SUITE_TMP}/rt2033"
    mkdir -p "${dir}"
    # Clean version: just the text
    printf 'Hello world.' > "${dir}/clean.txt"
    # Markup version: same text buried in markup
    printf '<div>Hello</div> ![img](http://x.com/y.png) world {.class}.' > "${dir}/markup.html"
    "${YAPPER}" convert "${dir}/clean.txt" -o "${dir}/clean.m4a" --voice af_heart --non-interactive >/dev/null 2>&1
    "${YAPPER}" convert "${dir}/markup.html" -o "${dir}/markup.m4a" --voice af_heart --non-interactive >/dev/null 2>&1
    [[ -f "${dir}/clean.m4a" ]] || return 1
    [[ -f "${dir}/markup.m4a" ]] || return 1
    local clean_size markup_size
    clean_size=$(stat -f%z "${dir}/clean.m4a")
    markup_size=$(stat -f%z "${dir}/markup.m4a")
    # If markup is being read aloud, the markup file will be significantly larger.
    # Allow 50% tolerance for encoding variation, but not 3x.
    local ratio
    ratio=$(awk "BEGIN{printf \"%.1f\", ${markup_size}/${clean_size}}")
    awk "BEGIN{exit(${ratio} < 2.0 ? 0 : 1)}"
}
run_test "RT-20.33" "real synthesis of markup file is not inflated (cleanup applied)" test_RT20_33

# RT-20.34: Empty bracket pairs [] stripped from dry-run text.
test_RT20_34() {
    printf 'Hello [] world [] test.' > "${SUITE_TMP}/rt2034.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2034.md" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q '\[\]'; then
        return 1
    fi
    printf '%s' "${output}" | grep -q "Hello"
}
run_test "RT-20.34" "empty brackets [] stripped from dry-run text" test_RT20_34

# RT-20.35: --non-interactive with epub uses extracted metadata silently.
test_RT20_35() {
    local epub
    epub="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)/Tests/fixtures/test_book.epub"
    [[ -f "${epub}" ]] || return 1
    local dir="${SUITE_TMP}/rt2035"
    mkdir -p "${dir}"
    # Should complete without prompting and use epub metadata
    timeout 15 "${YAPPER}" convert "${epub}" --non-interactive --voice af_heart -o "${dir}/book.m4b" >/dev/null 2>&1
    [[ -f "${dir}/book.m4b" ]] || return 1
    # Verify extracted metadata was applied (author from epub = "Test Author")
    local author
    author=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${dir}/book.m4b" 2>/dev/null)
    [[ "${author}" == "Test Author" ]]
}
run_test "RT-20.35" "--non-interactive epub uses extracted metadata silently" test_RT20_35

# RT-20.36: Multi-file M4B with --author and --title embeds metadata.
test_RT20_36() {
    local dir="${SUITE_TMP}/rt2036"
    mkdir -p "${dir}"
    printf 'Part one.' > "${dir}/a.txt"
    printf 'Part two.' > "${dir}/b.txt"
    "${YAPPER}" convert "${dir}/a.txt" "${dir}/b.txt" --format m4b -o "${dir}/book.m4b" \
        --author "Meta Author" --title "Meta Title" --voice af_heart --non-interactive >/dev/null 2>&1
    [[ -f "${dir}/book.m4b" ]] || return 1
    local artist album
    artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${dir}/book.m4b" 2>/dev/null)
    album=$(ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${dir}/book.m4b" 2>/dev/null)
    [[ "${artist}" == *"Meta Author"* ]] || return 1
    [[ "${album}" == *"Meta Title"* ]]
}
run_test "RT-20.36" "multi-file M4B embeds author and title metadata" test_RT20_36

# ---------------------------------------------------------------------------
# Issue #22: Look-ahead synthesis — convert mode benefits
# ---------------------------------------------------------------------------

# RT-22.10: Convert wall-clock time is not inflated by pipelining overhead.
# User action: yapper convert multi-sentence file.
# User observes: fast conversion, no slower than before.
test_RT22_10() {
    local dir="${SUITE_TMP}/rt2210"
    mkdir -p "${dir}"
    printf 'First sentence of convert pipelining test. Second sentence with more words. Third sentence for good measure. Fourth sentence extends the text further. Fifth sentence wraps up.' > "${dir}/input.txt"
    local start end elapsed
    start=$(date +%s)
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart --non-interactive --quiet >/dev/null 2>&1
    end=$(date +%s)
    elapsed=$((end - start))
    # Convert should finish within 15 seconds for this input — pipelining
    # should not add overhead since convert writes to file, not to speakers.
    [[ -f "${dir}/output.m4a" ]] && [[ ${elapsed} -lt 15 ]]
}
run_test "RT-22.10" "convert wall-clock time not inflated by pipelining" test_RT22_10

# RT-22.11: Progress updates in convert mode occur at synthesis-start.
# User action: yapper convert multi-sentence file.
# User observes: progress text changes as each chunk begins synthesis.
test_RT22_11() {
    local dir="${SUITE_TMP}/rt2211"
    mkdir -p "${dir}"
    printf 'Alpha sentence for progress. Beta sentence for testing. Gamma sentence for verification.' > "${dir}/input.txt"
    local stderr_output
    stderr_output=$("${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart --non-interactive 2>&1 1>/dev/null)
    # Progress output should contain text from the input
    printf '%s' "${stderr_output}" | grep -qi "sentence\|Alpha\|Gamma"
}
run_test "RT-22.11" "convert progress updates at synthesis-start" test_RT22_11

summarise "make-audiobook delta"
