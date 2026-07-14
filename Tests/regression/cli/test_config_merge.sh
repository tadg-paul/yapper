#!/usr/bin/env bash
# ABOUTME: Release-safe CLI tests for canonical map and sequence merge semantics.
# ABOUTME: Distinguishes explicit empty collections from absent configuration.

test_explicit_empty_substitution_map_clears_inherited_values() {
    local dir home config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}/.config/yapper"
    config="${dir}/explicit.yaml"
    cat > "${home}/.config/yapper/yapper.yaml" <<'YAML'
yapper:
  speech-substitution:
    jacket: coat
YAML
    cat > "${config}" <<'YAML'
yapper:
  speech-substitution: {}
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" speak \
        --config "${config}" --dry-run 'A jacket.' 2>&1)
    printf '%s' "${output}" | grep -q 'text:.*A jacket\.' || return 1
    if printf '%s' "${output}" | grep -q 'A coat'; then
        return 1
    fi
}
run_test "RT-47.8" "explicit empty substitution map clears inherited values" test_explicit_empty_substitution_map_clears_inherited_values

test_explicit_empty_character_map_clears_inherited_values() {
    local dir home input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}/.config/yapper"
    input="${dir}/play.md"
    config="${dir}/explicit.yaml"
    cat > "${input}" <<'MARKDOWN'
# Test Play

## Scene One

**ALICE:**
Hello, Bob.

**BOB:**
Hello, Alice.
MARKDOWN
    cat > "${home}/.config/yapper/yapper.yaml" <<'YAML'
yapper:
  script:
    voices:
      openai:
        characters:
          ALICE: coral
          BOB: ash
YAML
    cat > "${config}" <<'YAML'
yapper:
  engine: openai
  script:
    voices:
      openai:
        characters: {}
YAML
    if output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert \
        "${input}" --config "${config}" --dry-run --non-interactive 2>&1); then
        return 1
    fi
    printf '%s' "${output}" | grep -q 'no script voice mapping for: ALICE, BOB' || return 1
}
run_test "RT-47.8b" "explicit empty character map clears inherited values" test_explicit_empty_character_map_clears_inherited_values

test_voice_pool_sequence_replaces_instead_of_concatenating() {
    local dir home input config output
    dir=$(mktemp -d)
    home="${dir}/home"
    mkdir -p "${home}/.config/yapper"
    input="${dir}/play.md"
    config="${dir}/explicit.yaml"
    cat > "${input}" <<'MARKDOWN'
# Test Play

## Scene One

**ALICE:**
Hello, Bob.

**BOB:**
Hello, Alice.
MARKDOWN
    cat > "${home}/.config/yapper/yapper.yaml" <<'YAML'
yapper:
  script:
    voices:
      openai:
        auto-assign: true
        pool: [alloy, ash]
YAML
    cat > "${config}" <<'YAML'
yapper:
  engine: openai
  script:
    voices:
      openai:
        pool: [coral]
YAML
    output=$(CFFIXED_USER_HOME="${home}" HOME="${home}" "${YAPPER}" convert \
        "${input}" --config "${config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q 'ALICE: coral' || return 1
    printf '%s' "${output}" | grep -q 'BOB: coral' || return 1
    if printf '%s' "${output}" | grep -Eq 'ALICE: (alloy|ash)|BOB: (alloy|ash)'; then
        return 1
    fi
}
run_test "RT-47.7" "voice pool sequences replace lower-precedence values" test_voice_pool_sequence_replaces_instead_of_concatenating
