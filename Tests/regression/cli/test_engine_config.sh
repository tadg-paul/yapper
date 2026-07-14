#!/usr/bin/env bash
# ABOUTME: Release-safe CLI tests for canonical engine configuration and precedence.
# ABOUTME: Exercises built commands with dry-run paths and no real synthesis.

test_canonical_speak_config() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    config="${dir}/explicit.yaml"
    cat > "${config}" <<'YAML'
yapper:
  engine: yapper
  speech-substitution:
    jacket: coat
  engines:
    yapper:
      voice: bf_emma
      speed: 1.2
      concurrency: 1
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${config}" --dry-run 'A jacket.' 2>&1)
    printf '%s' "${output}" | grep -q '^engine: yapper$' || return 1
    printf '%s' "${output}" | grep -q '^voice:.*bf_emma' || return 1
    printf '%s' "${output}" | grep -q '^speed:.*1.2' || return 1
    printf '%s' "${output}" | grep -q 'text:.*A coat.' || return 1
}
run_test "RT-47.1" "speak resolves canonical engine configuration" test_canonical_speak_config

test_config_precedence_and_canonical_warning() {
    local dir home input explicit output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}/.config/yapper"
    input="${dir}/chapter.md"
    explicit="${dir}/explicit.yaml"
    printf 'Text.' > "${input}"
    cat > "${home}/.config/yapper/yapper.yaml" <<'YAML'
yapper:
  engines:
    openai:
      voice: alloy
YAML
    cat > "${dir}/yapper.yaml" <<'YAML'
yapper:
  engines:
    openai:
      voice: ash
YAML
    cat > "${explicit}" <<'YAML'
yapper:
  engines:
    openai:
      voice: coral
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" \
        --engine openai --config "${explicit}" --voice sage --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Voice: sage' || return 1
}
run_test "RT-47.5" "CLI overrides explicit, project, and global engine settings" test_config_precedence_and_canonical_warning

test_explicit_builtin_value_beats_config() {
    local dir home input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/chapter.md"
    config="${dir}/config.yaml"
    printf 'Text.' > "${input}"
    cat > "${config}" <<'YAML'
yapper:
  engines:
    openai:
      speed: 1.3
      model: tts-1-hd
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" \
        --engine openai --config "${config}" --speed 1.0 --openai-model gpt-4o-mini-tts \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Speed: 1.0' || return 1
    printf '%s' "${output}" | grep -q 'Model: gpt-4o-mini-tts' || return 1
}
run_test "RT-47.5b" "explicit built-in values still override config" test_explicit_builtin_value_beats_config

test_unselected_future_engine_config() {
    local dir home input output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/chapter.md"
    printf 'Text.' > "${input}"
    cat > "${dir}/yapper.yaml" <<'YAML'
yapper:
  engine: yapper
  engines:
    future-local:
      model: future-v1
      reference-profile: narrator
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" \
        --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Engine: yapper' || return 1
    if printf '%s' "${output}" | grep -q 'future-local'; then
        return 1
    fi
}
run_test "RT-47.42" "unselected future engine config does not block native conversion" test_unselected_future_engine_config

test_selected_unknown_engine_fails() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    config="${dir}/explicit.yaml"
    cat > "${config}" <<'YAML'
yapper:
  engine: future-local
  engines:
    future-local:
      model: future-v1
YAML
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${config}" --dry-run 'Text.' 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q "Unsupported engine 'future-local'" || return 1
    printf '%s' "${output}" | grep -q 'yapper, fal, openai' || return 1
}
run_test "RT-47.24" "selected unknown engine names registered engines" test_selected_unknown_engine_fails

test_malformed_explicit_config_fails() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    config="${dir}/broken.yaml"
    printf 'yapper: [broken' > "${config}"
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${config}" --dry-run 'Text.' 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q "${config}" || return 1
}
run_test "RT-47.35" "malformed explicit config stops before synthesis" test_malformed_explicit_config_fails

test_remote_speak_dry_run() {
    local dir home output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --engine openai --voice coral --dry-run 'Remote speech.' 2>&1)
    printf '%s' "${output}" | grep -q '^engine: openai$' || return 1
    printf '%s' "${output}" | grep -q '^voice:.*coral' || return 1
    printf '%s' "${output}" | grep -q 'text:.*Remote speech.' || return 1
}
run_test "RT-46.5" "speak dry-run uses selected remote engine" test_remote_speak_dry_run

test_remote_script_dry_run_uses_provider_roles() {
    local dir home input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/play.md"
    config="${dir}/config.yaml"
    cat > "${input}" <<'MARKDOWN'
# Test Play

## Scene One

**ALICE:**
Hello, Bob.

**BOB:**
Hello, Alice.
MARKDOWN
    cat > "${config}" <<'YAML'
yapper:
  engine: openai
  engines:
    openai:
      voice: alloy
  script:
    voices:
      openai:
        narrator: ash
        intro: coral
        characters:
          ALICE: nova
          BOB: sage
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" \
        --config "${config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'Engine: openai' || return 1
    printf '%s' "${output}" | grep -q 'ALICE: nova' || return 1
    printf '%s' "${output}" | grep -q 'BOB: sage' || return 1
    printf '%s' "${output}" | grep -q 'Narrator (stage directions): ash' || return 1
    printf '%s' "${output}" | grep -q 'Introduction: coral' || return 1
}
run_test "RT-46.7" "explicit config selects remote script roles" test_remote_script_dry_run_uses_provider_roles

test_provider_voice_listing_uses_configured_catalogue() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    config="${dir}/config.yaml"
    cat > "${config}" <<'YAML'
yapper:
  engine: fal
  engines:
    fal:
      voice: Rachel
  script:
    voices:
      fal:
        pool: [Aria, Roger]
        narrator: Rachel
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" voices \
        --config "${config}" --engine fal 2>&1)
    printf '%s' "${output}" | grep -q 'Configured voices for fal' || return 1
    printf '%s' "${output}" | grep -q 'Aria' || return 1
    printf '%s' "${output}" | grep -q 'Roger' || return 1
    printf '%s' "${output}" | grep -q 'provider catalogue discovery is unavailable' || return 1
}
run_test "RT-46.43" "voices describes configured-only provider catalogues" test_provider_voice_listing_uses_configured_catalogue

test_case_insensitive_substitution_merge_and_boundaries() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}/.config/yapper"
    config="${dir}/explicit.yaml"
    cat > "${home}/.config/yapper/yapper.yaml" <<'YAML'
yapper:
  speech-substitution:
    Cáit: global
YAML
    cat > "${config}" <<'YAML'
yapper:
  speech-substitution:
    CÁIT: project
YAML
    output=$(cd "${dir}" && CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${config}" --dry-run 'cáit met Cait and Caitlin.' 2>&1)
    printf '%s' "${output}" | grep -q 'text:.*project met Cait and Caitlin\.' || return 1
    if printf '%s' "${output}" | grep -q 'global'; then
        return 1
    fi
}
run_test "RT-47.44 through RT-47.46" "substitution keys merge case-insensitively at term boundaries" test_case_insensitive_substitution_merge_and_boundaries

test_engine_substitution_overlay_and_ipa_fallback() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    config="${dir}/explicit.yaml"
    cat > "${config}" <<'YAML'
yapper:
  speech-substitution:
    Cáit: Kawch
    Taḋg: "/taɪɡ/(Tigue)"
    Gda: "/ɡədɑː/"
  engines:
    openai:
      speech-substitution:
        cÁIT: Cotch
YAML
    output=$(cd "${dir}" && CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --engine openai --config "${config}" --dry-run 'Cáit met Taḋg and Gda.' 2>&1)
    printf '%s' "${output}" | grep -q 'text:.*Cotch met Tigue and Gda\.' || return 1
    printf '%s' "${output}" | grep -q 'skipped unsupported IPA substitution.*Gda' || return 1
}
run_test "RT-47.48 through RT-47.52" "selected engine overlays substitutions and resolves IPA fallback" test_engine_substitution_overlay_and_ipa_fallback

test_script_character_names_are_case_insensitive() {
    local dir home input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/play.md"
    config="${dir}/config.yaml"
    cat > "${input}" <<'MARKDOWN'
# Test Play

## Scene One

**ALICE:**
Hello, Bob.

**BOB:**
Hello, Alice.
MARKDOWN
    cat > "${config}" <<'YAML'
yapper:
  engine: openai
  script:
    voices:
      openai:
        narrator: ash
        characters:
          alice: nova
          bob: sage
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" \
        --config "${config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'ALICE: nova' || return 1
    printf '%s' "${output}" | grep -q 'BOB: sage' || return 1
}
run_test "RT-47.47" "script character mappings are case-insensitive" test_script_character_names_are_case_insensitive
