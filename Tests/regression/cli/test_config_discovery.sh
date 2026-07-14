#!/usr/bin/env bash
# ABOUTME: Release-safe CLI tests for config discovery, defaults, and namespace isolation.
# ABOUTME: Covers global/project/explicit paths without reading the developer's real config.

test_minimal_config_uses_established_defaults() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    config="${dir}/config.yaml"
    printf 'yapper: {}\n' > "${config}"

    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${config}" --dry-run 'Text.' 2>&1)
    printf '%s' "${output}" | grep -q '^engine: yapper$' || return 1
    printf '%s' "${output}" | grep -q '^voice:.*af_heart' || return 1
    printf '%s' "${output}" | grep -q '^speed:.*1.0' || return 1

    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --engine fal --config "${config}" --dry-run 'Text.' 2>&1)
    printf '%s' "${output}" | grep -q '^voice:.*Rachel' || return 1
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --engine openai --config "${config}" --dry-run 'Text.' 2>&1)
    printf '%s' "${output}" | grep -q '^voice:.*alloy' || return 1
}
run_test "RT-47.2" "minimal canonical config preserves built-in defaults" test_minimal_config_uses_established_defaults

test_companion_namespace_and_global_config_are_isolated() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}/.config/first-folio"
    config="${dir}/config.yaml"
    cat > "${home}/.config/first-folio/script.yaml" <<'YAML'
yapper:
  engine: openai
YAML
    cat > "${config}" <<'YAML'
folio:
  style: british
  page: a4
yapper:
  speech-substitution:
    jacket: coat
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${config}" --dry-run 'A jacket.' 2>&1)
    printf '%s' "${output}" | grep -q '^engine: yapper$' || return 1
    printf '%s' "${output}" | grep -q 'text:.*A coat\.' || return 1
    if printf '%s' "${output}" | grep -Eq 'folio|british|openai'; then
        return 1
    fi
}
run_test "RT-47.4, RT-47.18, and RT-47.33" "companion namespace and global config remain isolated" test_companion_namespace_and_global_config_are_isolated

test_project_yapper_precedes_script_and_explicit_precedes_both() {
    local dir home explicit output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    explicit="${dir}/explicit.yaml"
    cat > "${dir}/script.yaml" <<'YAML'
yapper:
  speech-substitution:
    jacket: script
YAML
    cat > "${dir}/yapper.yaml" <<'YAML'
yapper:
  speech-substitution:
    jacket: project
YAML
    cat > "${explicit}" <<'YAML'
yapper:
  speech-substitution:
    jacket: explicit
YAML
    output=$(cd "${dir}" && CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --dry-run 'A jacket.' 2>&1)
    printf '%s' "${output}" | grep -q 'text:.*A project\.' || return 1
    output=$(cd "${dir}" && CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${explicit}" --dry-run 'A jacket.' 2>&1)
    printf '%s' "${output}" | grep -q 'text:.*A explicit\.' || return 1
}
run_test "RT-47.34" "project yapper config and explicit config use documented precedence" test_project_yapper_precedes_script_and_explicit_precedes_both

test_script_config_option_remains_compatibility_alias() {
    local dir home input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/play.md"
    config="${dir}/legacy-name.yaml"
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
  script:
    voices:
      yapper:
        characters:
          ALICE: af_heart
          BOB: bm_daniel
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert "${input}" \
        --script-config "${config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q "deprecated option '--script-config'" || return 1
    printf '%s' "${output}" | grep -q 'ALICE: af_heart' || return 1
    printf '%s' "${output}" | grep -q 'BOB: bm_daniel' || return 1
}
run_test "RT-47.41" "script-config remains a warned compatibility alias" test_script_config_option_remains_compatibility_alias
