#!/usr/bin/env bash
# ABOUTME: Release-safe CLI tests for selected-engine configuration validation.
# ABOUTME: Ensures invalid canonical values fail before synthesis and name their paths.

test_selected_engine_values_name_canonical_paths() {
    local dir home input config output fixture expected
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/chapter.md"
    config="${dir}/config.yaml"
    printf 'Text.' > "${input}"

    while IFS='|' read -r fixture expected; do
        printf '%b' "${fixture}" > "${config}"
        if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert \
            "${input}" --config "${config}" --dry-run --non-interactive 2>&1); then
            return 1
        fi
        printf '%s' "${output}" | grep -q "${expected}" || {
            printf 'missing path %s in: %s\n' "${expected}" "${output}"
            return 1
        }
    done <<'CASES'
yapper:\n  engine: fal\n  engines:\n    fal:\n      speed: 0.1\n|yapper.engines.fal.speed
yapper:\n  engine: fal\n  engines:\n    fal:\n      concurrency: 0\n|yapper.engines.fal.concurrency
yapper:\n  engine: fal\n  engines:\n    fal:\n      stability: 2.0\n|yapper.engines.fal.stability
yapper:\n  engine: fal\n  engines:\n    fal:\n      output-format: invalid\n|yapper.engines.fal.output-format
yapper:\n  engine: fal\n  engines:\n    fal:\n      text-normalization: sometimes\n|yapper.engines.fal.text-normalization
yapper:\n  engine: openai\n  engines:\n    openai:\n      speed: 9.0\n|yapper.engines.openai.speed
yapper:\n  engine: openai\n  engines:\n    openai:\n      output-format: invalid\n|yapper.engines.openai.output-format
CASES
}
run_test "RT-47.25" "selected invalid engine values name canonical paths" test_selected_engine_values_name_canonical_paths

test_remote_script_empty_pool_names_selected_path() {
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
        auto-assign: true
        pool: []
YAML
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert \
        "${input}" --config "${config}" --dry-run --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'yapper.script.voices.openai.pool' || return 1
}
run_test "RT-47.26" "empty remote auto-assignment pool names selected path" test_remote_script_empty_pool_names_selected_path

test_credentials_never_fall_back_across_engines() {
    local dir home input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}"
    input="${dir}/chapter.md"
    config="${dir}/config.yaml"
    printf 'Text.' > "${input}"
    cat > "${config}" <<'YAML'
yapper:
  engine: fal
  engines:
    openai:
      credentials:
        generation:
          literal: OPENAI_SENTINEL_MUST_NOT_LEAK
YAML
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" \
        FAL_KEY= OPENAI_API_KEY= "${YAPPER}" convert "${input}" --config "${config}" \
        --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'yapper.engines.fal.credentials.generation' || return 1
    if printf '%s' "${output}" | grep -q 'OPENAI_SENTINEL'; then
        return 1
    fi
}
run_test "RT-47.27" "missing credentials do not fall back across engines" test_credentials_never_fall_back_across_engines
