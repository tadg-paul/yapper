#!/usr/bin/env bash
# ABOUTME: One-off tests for `yapper voices` (issue #5).
# ABOUTME: Each test invokes the built yapper binary exactly as a user would.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: yapper voices (RT-5.x)\n'

# ---------------------------------------------------------------------------
# Issue #5: yapper voices command
# Specs from: https://github.com/tigger04/yapper/issues/5
# ---------------------------------------------------------------------------

# RT-5.1: Output contains at least 3 voices.
# User action: yapper voices
# User observes: a list with at least 3 voice entries.
test_RT5_1() {
    local output
    output=$("${YAPPER}" voices 2>/dev/null)
    local count
    count=$(printf '%s\n' "${output}" | grep -cE '^[a-z][fm]_' || true)
    [[ ${count} -ge 3 ]]
}
run_test "RT-5.1" "at least 3 voices listed" test_RT5_1

# RT-5.2: Each voice line includes name, accent label, and gender label.
# User action: yapper voices
# User observes: formatted table with columns for each field.
test_RT5_2() {
    local output
    output=$("${YAPPER}" voices 2>/dev/null)
    # Check first 3 voice lines have multiple whitespace-separated fields
    local lines
    lines=$(printf '%s\n' "${output}" | grep -E '^[a-z][fm]_' | head -3)
    while IFS= read -r line; do
        local fields
        fields=$(printf '%s' "${line}" | awk '{print NF}')
        [[ ${fields} -ge 3 ]] || return 1
    done <<< "${lines}"
}
run_test "RT-5.2" "each voice line has name, accent, gender" test_RT5_2

# RT-5.3: Output is sorted alphabetically by name.
# User action: yapper voices
# User observes: voice names in alphabetical order.
test_RT5_3() {
    local output
    output=$("${YAPPER}" voices 2>/dev/null)
    local names sorted_names
    names=$(printf '%s\n' "${output}" | grep -oE '^[a-z][fm]_[a-z]+' || true)
    sorted_names=$(printf '%s\n' "${names}" | sort)
    [[ "${names}" == "${sorted_names}" ]]
}
run_test "RT-5.3" "voices sorted alphabetically" test_RT5_3

# RT-5.4: Command exits 0 for a valid voice preview.
# User action: yapper voices --preview af_heart
# User observes: audio plays, exit 0.
test_RT5_4() {
    "${YAPPER}" voices --preview af_heart >/dev/null 2>&1
}
run_test "RT-5.4" "preview valid voice exits 0" test_RT5_4

# RT-5.5: Command exits non-zero with descriptive error for invalid voice preview.
# User action: yapper voices --preview nonexistent
# User observes: error message, non-zero exit.
test_RT5_5() {
    local output
    if output=$("${YAPPER}" voices --preview nonexistent_voice 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "nonexistent_voice"
}
run_test "RT-5.5" "preview invalid voice produces error" test_RT5_5

# RT-5.6: Empty voices directory produces descriptive error.
# This requires pointing yapper at an empty voices directory. The binary
# discovers voices via Defaults.swift path resolution. Until a --voices-path
# flag or env var exists, this test cannot be exercised at the CLI level.
# The underlying VoiceRegistry error is tested in the Swift framework suite.
# Deferred — tracked in #17.

# RT-5.7, RT-5.8: VoiceRegistry error-handling tests.
# Engine-level tests. Remain in Swift framework suite under VoiceRegistryTests.

summarise "yapper voices"
