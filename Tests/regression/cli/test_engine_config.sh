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
