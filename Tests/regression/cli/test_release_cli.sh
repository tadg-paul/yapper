#!/usr/bin/env bash
# ABOUTME: Release-safe CLI smoke tests that avoid real synthesis and playback.
# ABOUTME: Exercises argument parsing, dry-run output, voice listing, and yap dispatch.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: release-safe CLI smoke (fast)\n'

YAP_LINK=$(mktemp -d)/yap
ln -s "${YAPPER}" "${YAP_LINK}"
trap 'rm -rf "$(dirname "${YAP_LINK}")"' EXIT

test_release_speak_dry_run() {
    local output
    output=$("${YAPPER}" speak --voice af_heart --speed 1.25 --dry-run "release smoke" 2>&1)
    printf '%s' "${output}" | grep -q '^voice:.*af_heart' || return 1
    printf '%s' "${output}" | grep -q '^speed:.*1.25' || return 1
    printf '%s' "${output}" | grep -q 'text:.*release smoke' || return 1
    printf '%s' "${output}" | grep -q '(dry run' || return 1
}
run_test "FAST-CLI.1" "speak dry-run resolves voice, speed, and text" test_release_speak_dry_run

test_release_speak_preprocessing() {
    local output
    output=$(printf 'that is a lovely *jacket* you are wearing' | "${YAPPER}" speak --dry-run 2>&1)
    printf '%s' "${output}" | grep -q 'text:   that is a lovely "jacket" you are wearing' || return 1
    if printf '%s' "${output}" | grep -q '\*jacket\*'; then
        return 1
    fi
}
run_test "FAST-CLI.2" "speak dry-run applies prose preprocessing" test_release_speak_preprocessing

test_release_speak_hyphen_preprocessing() {
    local output
    output=$(printf 'sea-holly and ice-cream' | "${YAPPER}" speak --dry-run 2>&1)
    printf '%s' "${output}" | grep -q 'text:   sea holly and ice cream' || return 1
    if printf '%s' "${output}" | grep -Eq 'sea-holly|ice-cream'; then
        return 1
    fi

    output=$(printf 'car-park' | "${YAP_LINK}" --dry-run 2>&1)
    printf '%s' "${output}" | grep -q 'text:   car park' || return 1
    if printf '%s' "${output}" | grep -q 'car-park'; then
        return 1
    fi
}
run_test "RT-39.3" "speak and yap dry-run normalize intra-word hyphens" test_release_speak_hyphen_preprocessing

test_release_convert_hyphen_preprocessing() {
    local dir input output
    dir=$(mktemp -d)
    input="${dir}/hyphen.md"
    printf 'The sea-holly met the car-park.' > "${input}"
    output=$("${YAPPER}" convert "${input}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'The sea holly met the car park.' || return 1
    if printf '%s' "${output}" | grep -Eq 'sea-holly|car-park'; then
        return 1
    fi
}
run_test "RT-39.4" "convert dry-run normalizes intra-word hyphens" test_release_convert_hyphen_preprocessing

test_release_convert_chunk_diagnostics() {
    local dir input output
    dir=$(mktemp -d)
    input="${dir}/paragraphs.md"
    printf 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.' > "${input}"
    output=$("${YAPPER}" convert "${input}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Chunks: 1 (policy: natural-prose)' || return 1
    printf '%s' "${output}" | grep -q 'Chunk 1: boundary=none, paragraphs=yes' || return 1
}
run_test "RT-40.7" "convert dry-run exposes natural prose chunk diagnostics" test_release_convert_chunk_diagnostics

test_release_script_dry_run_structure() {
    local dir input output
    dir=$(mktemp -d)
    input="${dir}/script.md"
    cat > "${input}" <<'EOF'
# Test Script

## Scene One

ALICE
Hello there.

BOB
General Kenobi.

A door closes.
EOF
    output=$("${YAPPER}" convert "${input}" --script --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Script mode: Test Script' || return 1
    printf '%s' "${output}" | grep -q 'ALICE' || return 1
    printf '%s' "${output}" | grep -q 'BOB' || return 1
    printf '%s' "${output}" | grep -q '\\[stage\\]' || return 1
}
run_test "RT-40.4" "script dry-run keeps character and stage structure" test_release_script_dry_run_structure

test_release_invalid_voice() {
    local output
    if output=$("${YAPPER}" speak --voice nonexistent_voice --dry-run "hello" 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -qi 'nonexistent_voice'
}
run_test "FAST-CLI.3" "speak dry-run rejects invalid voice" test_release_invalid_voice

test_release_voices_list() {
    local output
    output=$("${YAPPER}" voices -1 2>&1)
    printf '%s' "${output}" | grep -q '^af_heart$' || return 1
    local count
    count=$(printf '%s\n' "${output}" | wc -l | tr -d ' ')
    [[ ${count} -ge 3 ]]
}
run_test "FAST-CLI.4" "voices list reports installed voices" test_release_voices_list

test_release_yap_dispatch() {
    local output
    output=$("${YAP_LINK}" --voice af_heart --dry-run "shortcut smoke" 2>&1)
    printf '%s' "${output}" | grep -q '^voice:.*af_heart' || return 1
    printf '%s' "${output}" | grep -q 'text:.*shortcut smoke' || return 1
}
run_test "FAST-CLI.5" "yap dispatch routes to speak dry-run" test_release_yap_dispatch

summarise "release-safe CLI smoke"
