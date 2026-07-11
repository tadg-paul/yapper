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

test_release_convert_fal_dry_run_plan() {
    local dir home input output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/remote.md"
    printf 'that is a lovely *jacket*\n\n--- I would like cheese, he said.' > "${input}"
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --engine fal --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Remote conversion plan:' || return 1
    printf '%s' "${output}" | grep -q 'Engine: fal' || return 1
    printf '%s' "${output}" | grep -q 'Endpoint: fal-ai/elevenlabs/tts/multilingual-v2' || return 1
    printf '%s' "${output}" | grep -q 'Chunk policy: remote-sentence-2500' || return 1
    printf '%s' "${output}" | grep -q 'Chunks: 1' || return 1
    printf '%s' "${output}" | grep -q 'Text: that is a lovely "jacket" "I would like cheese, he said."' || return 1
    printf '%s' "${output}" | grep -q '(dry run' || return 1
    if [[ -e "${dir}/remote.m4a" ]]; then
        return 1
    fi
}
run_test "RT-41.3" "FAL convert dry-run shows transformed provider chunk plan" test_release_convert_fal_dry_run_plan

test_release_convert_openai_dry_run_plan() {
    local dir home input output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/remote.md"
    printf 'A small _quoted_ phrase.' > "${input}"
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --engine openai --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Remote conversion plan:' || return 1
    printf '%s' "${output}" | grep -q 'Engine: openai' || return 1
    printf '%s' "${output}" | grep -q 'Model: gpt-4o-mini-tts' || return 1
    printf '%s' "${output}" | grep -q 'Chunk policy: remote-sentence-4096' || return 1
    printf '%s' "${output}" | grep -q 'Text: A small "quoted" phrase.' || return 1
    printf '%s' "${output}" | grep -q '(dry run' || return 1
    if [[ -e "${dir}/remote.m4a" ]]; then
        return 1
    fi
}
run_test "RT-41.4" "OpenAI convert dry-run shows transformed provider chunk plan" test_release_convert_openai_dry_run_plan

test_release_convert_remote_credentials_nested_config() {
    local dir home input helper output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/remote.md"
    helper="${dir}/print-key"
    printf 'A small phrase.' > "${input}"
    printf '#!/usr/bin/env bash\nprintf test-key\n' > "${helper}"
    chmod +x "${helper}"
    cat > "${dir}/yapper.yaml" <<EOF
yapper:
  remote-speech:
    openai:
      api-key: ./print-key
EOF
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --engine openai --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Generation credential: helper:' || return 1
    printf '%s' "${output}" | grep -q 'print-key' || return 1
    if printf '%s' "${output}" | grep -q 'test-key'; then
        return 1
    fi
}
run_test "RT-41.25" "remote credentials resolve from nested yapper config helper" test_release_convert_remote_credentials_nested_config

test_release_remote_generation_helper_errors_are_contextual() {
    local dir home input helper output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/remote.md"
    helper="${dir}/bad-helper"
    printf 'A small phrase.' > "${input}"
    printf 'not a script\n' > "${helper}"
    chmod +x "${helper}"
    cat > "${dir}/yapper.yaml" <<EOF
yapper:
  remote-speech:
    fal:
      api-key: ./bad-helper
EOF
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --engine fal --dry-run --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'Credential helper for yapper.remote-speech.fal.api-key failed to execute' || return 1
    printf '%s' "${output}" | grep -q 'bad-helper' || return 1
    printf '%s' "${output}" | grep -q 'Exec format error' || return 1

    cat > "${dir}/yapper.yaml" <<EOF
yapper:
  remote-speech:
    openai:
      api-key: ./bad-helper
EOF
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --engine openai --dry-run --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'Credential helper for yapper.remote-speech.openai.api-key failed to execute' || return 1
    printf '%s' "${output}" | grep -q 'bad-helper' || return 1
    printf '%s' "${output}" | grep -q 'Exec format error' || return 1
}
run_test "RT-44.1" "remote generation helper execution errors name slot and path" test_release_remote_generation_helper_errors_are_contextual

test_release_remote_account_helper_errors_are_contextual() {
    local dir home input helper output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/remote.md"
    helper="${dir}/bad-helper"
    printf 'A small phrase.' > "${input}"
    printf 'not a script\n' > "${helper}"
    chmod +x "${helper}"
    cat > "${dir}/yapper.yaml" <<EOF
yapper:
  remote-speech:
    fal:
      api-key: config-fal-generation-key
      account-api-key: ./bad-helper
EOF
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --engine fal --dry-run --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'Credential helper for yapper.remote-speech.fal.account-api-key failed to execute' || return 1
    printf '%s' "${output}" | grep -q 'bad-helper' || return 1
    printf '%s' "${output}" | grep -q 'Exec format error' || return 1

    cat > "${dir}/yapper.yaml" <<EOF
yapper:
  remote-speech:
    openai:
      api-key: config-openai-generation-key
      admin-api-key: ./bad-helper
EOF
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --engine openai --dry-run --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'Credential helper for yapper.remote-speech.openai.admin-api-key failed to execute' || return 1
    printf '%s' "${output}" | grep -q 'bad-helper' || return 1
    printf '%s' "${output}" | grep -q 'Exec format error' || return 1
}
run_test "RT-44.2" "remote account helper execution errors name slot and path" test_release_remote_account_helper_errors_are_contextual

test_release_namespaced_speech_substitution() {
    local dir input output
    dir=$(mktemp -d)
    input="${dir}/namespaced.md"
    printf 'That is a lovely jacket.' > "${input}"
    cat > "${dir}/yapper.yaml" <<EOF
yapper:
  speech-substitution:
    JACKET: coat
EOF
    output=$("${YAPPER}" convert "${input}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Text: That is a lovely coat.' || return 1
}
run_test "RT-43.1" "namespaced speech substitution applies case-insensitively" test_release_namespaced_speech_substitution

test_release_legacy_speech_substitution_warns() {
    local dir input output
    dir=$(mktemp -d)
    input="${dir}/legacy.md"
    printf 'That is a lovely jacket.' > "${input}"
    cat > "${dir}/yapper.yaml" <<EOF
speech-substitution:
  jacket: coat
EOF
    output=$("${YAPPER}" convert "${input}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q "WARNING: deprecated Yapper config key 'speech-substitution'" || return 1
    printf '%s' "${output}" | grep -q 'Text: That is a lovely coat.' || return 1
}
run_test "RT-43.3" "legacy speech substitution applies and warns" test_release_legacy_speech_substitution_warns

test_release_namespaced_substitution_overrides_legacy() {
    local dir input output
    dir=$(mktemp -d)
    input="${dir}/override.md"
    printf 'That is a lovely jacket.' > "${input}"
    cat > "${dir}/yapper.yaml" <<EOF
speech-substitution:
  jacket: coat
yapper:
  speech-substitution:
    jacket: jumper
EOF
    output=$("${YAPPER}" convert "${input}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Text: That is a lovely jumper.' || return 1
    if printf '%s' "${output}" | grep -q 'Text: That is a lovely coat.'; then
        return 1
    fi
}
run_test "RT-43.5" "namespaced speech substitution overrides legacy value" test_release_namespaced_substitution_overrides_legacy

test_release_legacy_script_config_warns() {
    local dir fixtures input config output
    dir=$(mktemp -d)
    fixtures="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
    input="${fixtures}/test_script.md"
    config="${dir}/script.yaml"
    cat > "${config}" <<EOF
auto-assign-voices: false
narrator-voice: bf_lily
intro-voice: bf_lily
character-voices:
  ALICE: bf_emma
dialogue-speed: 0.8
threads: 1
EOF
    output=$("${YAPPER}" convert "${input}" --script-config "${config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q "WARNING: deprecated Yapper config key 'auto-assign-voices'" || return 1
    printf '%s' "${output}" | grep -q "WARNING: deprecated Yapper config key 'narrator-voice'" || return 1
    printf '%s' "${output}" | grep -q "WARNING: deprecated Yapper config key 'character-voices'" || return 1
    printf '%s' "${output}" | grep -q "WARNING: deprecated Yapper config key 'dialogue-speed'" || return 1
    printf '%s' "${output}" | grep -q "WARNING: deprecated Yapper config key 'threads'" || return 1
    printf '%s' "${output}" | grep -q 'ALICE: bf_emma' || return 1
}
run_test "RT-43.4" "legacy script voice and pacing config applies and warns" test_release_legacy_script_config_warns

test_release_script_namespaced_voice_config() {
    local dir fixtures input config output
    dir=$(mktemp -d)
    fixtures="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
    input="${fixtures}/test_script.md"
    config="${dir}/script.yaml"
    cat > "${config}" <<EOF
yapper:
  voices:
    auto-assign: false
    narrator: bf_lily
    intro: bf_lily
    characters:
      ALICE: bf_emma
EOF
    output=$("${YAPPER}" convert "${input}" --script-config "${config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'ALICE: bf_emma' || return 1
    printf '%s' "${output}" | grep -q 'Narrator (stage directions): bf_lily' || return 1
    printf '%s' "${output}" | grep -q 'Introduction: bf_lily' || return 1
}
run_test "RT-43.2" "script dry-run applies namespaced voice config" test_release_script_namespaced_voice_config

test_release_script_namespaced_voice_overrides_legacy() {
    local dir fixtures input config output
    dir=$(mktemp -d)
    fixtures="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
    input="${fixtures}/test_script.md"
    config="${dir}/script.yaml"
    cat > "${config}" <<EOF
narrator-voice: af_heart
character-voices:
  ALICE: af_heart
yapper:
  voices:
    narrator: bf_lily
    characters:
      ALICE: bf_emma
EOF
    output=$("${YAPPER}" convert "${input}" --script-config "${config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'ALICE: bf_emma' || return 1
    printf '%s' "${output}" | grep -q 'Narrator (stage directions): bf_lily' || return 1
    if printf '%s' "${output}" | grep -q 'ALICE: af_heart'; then
        return 1
    fi
}
run_test "RT-43.6" "namespaced script voice config overrides legacy value" test_release_script_namespaced_voice_overrides_legacy

test_release_shared_top_level_config_does_not_warn() {
    local dir home fixtures input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    fixtures="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
    input="${fixtures}/test_script.md"
    config="${dir}/script.yaml"
    cat > "${config}" <<EOF
title: Shared Config
author: Example Author
render:
  stage-directions: true
  frontmatter: true
EOF
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" --script-config "${config}" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q 'WARNING: deprecated Yapper config key'; then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'Script mode: Shared Config' || return 1
}
run_test "RT-43.7" "shared top-level config does not emit Yapper deprecation warning" test_release_shared_top_level_config_does_not_warn

test_release_script_dry_run_structure() {
    local fixtures output
    fixtures="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
    output=$("${YAPPER}" convert "${fixtures}/test_script.md" \
        --script-config "${fixtures}/test_script.yaml" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Script mode: The Test Play' || return 1
    printf '%s' "${output}" | grep -q 'ALICE' || return 1
    printf '%s' "${output}" | grep -q 'BOB' || return 1
    printf '%s' "${output}" | grep -Fq '[stage]' || return 1
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

test_release_public_help_hides_poc_commands() {
    local output
    output=$("${YAPPER}" --help 2>&1)
    printf '%s' "${output}" | grep -q '^SUBCOMMANDS:' || return 1
    if printf '%s' "${output}" | grep -q 'context-poc'; then
        return 1
    fi
}
run_test "FAST-CLI.6" "top-level help hides deprecated POC commands" test_release_public_help_hides_poc_commands

summarise "release-safe CLI smoke"
