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
