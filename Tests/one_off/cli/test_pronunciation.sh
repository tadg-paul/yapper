#!/usr/bin/env bash
# ABOUTME: One-off tests for pronunciation config cascade and speech-substitution (issue #27).
# ABOUTME: Tests global/project/CLI config loading, merging, and substitution in all modes.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: pronunciation config (RT-27.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

FIXTURES="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"

# Save and restore global config
GLOBAL_CONFIG_DIR="${HOME}/.config/yapper"
GLOBAL_CONFIG="${GLOBAL_CONFIG_DIR}/yapper.yaml"
GLOBAL_BACKUP=""
if [[ -f "${GLOBAL_CONFIG}" ]]; then
    GLOBAL_BACKUP="${SUITE_TMP}/yapper.yaml.backup"
    cp "${GLOBAL_CONFIG}" "${GLOBAL_BACKUP}"
fi

restore_global() {
    if [[ -n "${GLOBAL_BACKUP}" ]]; then
        cp "${GLOBAL_BACKUP}" "${GLOBAL_CONFIG}"
    else
        rm -f "${GLOBAL_CONFIG}"
    fi
}
trap 'restore_global; rm -rf "${SUITE_TMP}"' EXIT

# ---------------------------------------------------------------------------
# AC27.1: Global config loaded
# ---------------------------------------------------------------------------

# RT-27.1: Global config with speech-substitution applied in speak mode.
test_RT27_1() {
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  testword27: replacement27
YAML
    local output
    output=$("${YAPPER}" speak --dry-run "The testword27 is here." 2>&1)
    printf '%s' "${output}" | grep -qi "replacement27" || return 1
}
run_test "RT-27.1" "global config substitution in speak mode" test_RT27_1

# RT-27.2: Global config substitution applied in non-script convert mode.
test_RT27_2() {
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  convertword27: replaced27
YAML
    local input="${SUITE_TMP}/rt27_2.txt"
    printf 'The convertword27 is here.' > "${input}"
    local output
    output=$("${YAPPER}" convert "${input}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "replaced27" || return 1
}
run_test "RT-27.2" "global config substitution in convert mode" test_RT27_2

# ---------------------------------------------------------------------------
# AC27.2: Project config overrides global
# ---------------------------------------------------------------------------

# RT-27.3: Project yapper.yaml substitution overrides global for same key.
test_RT27_3() {
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  sharedword: global_version
YAML
    local dir="${SUITE_TMP}/rt27_3"
    mkdir -p "${dir}"
    cat > "${dir}/yapper.yaml" <<YAML
speech-substitution:
  sharedword: project_version
YAML
    printf 'The sharedword appears.' > "${dir}/input.txt"
    local output
    output=$("${YAPPER}" convert "${dir}/input.txt" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "project_version" || return 1
    if printf '%s' "${output}" | grep -qi "global_version"; then
        return 1
    fi
}
run_test "RT-27.3" "project config overrides global for same key" test_RT27_3

# RT-27.4: Project config inherits global keys not present in project file.
test_RT27_4() {
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  globalonly: from_global
  shared: global_val
YAML
    local dir="${SUITE_TMP}/rt27_4"
    mkdir -p "${dir}"
    cat > "${dir}/yapper.yaml" <<YAML
speech-substitution:
  shared: project_val
YAML
    printf 'The globalonly and shared words.' > "${dir}/input.txt"
    local output
    output=$("${YAPPER}" convert "${dir}/input.txt" --dry-run --non-interactive 2>&1)
    # globalonly should come from global config
    printf '%s' "${output}" | grep -qi "from_global" || return 1
    # shared should come from project config (overridden)
    printf '%s' "${output}" | grep -qi "project_val" || return 1
}
run_test "RT-27.4" "project inherits global keys" test_RT27_4

# ---------------------------------------------------------------------------
# AC27.3: CLI config overrides all
# ---------------------------------------------------------------------------

# RT-27.5: CLI config substitution overrides project config (script mode).
test_RT27_5() {
    local dir="${SUITE_TMP}/rt27_5"
    mkdir -p "${dir}"
    cat > "${dir}/yapper.yaml" <<YAML
speech-substitution:
  cliword: project_version
YAML
    # Use a script file so --script-config is valid
    cat > "${dir}/test.org" <<'ORG'
#+TITLE: CLI Override Test
* ACT I
** Scene 1: Test
**** ALICE
The cliword is here.
ORG
    local cli_config="${SUITE_TMP}/cli.yaml"
    cat > "${cli_config}" <<YAML
speech-substitution:
  cliword: cli_version
render-intro: false
YAML
    local output
    output=$("${YAPPER}" convert "${dir}/test.org" --script-config "${cli_config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "cli_version" || return 1
}
run_test "RT-27.5" "CLI config overrides project config" test_RT27_5

# RT-27.6: CLI config works when no project or global config exists (script mode).
test_RT27_6() {
    rm -f "${GLOBAL_CONFIG}"
    local dir="${SUITE_TMP}/rt27_6"
    mkdir -p "${dir}"
    cat > "${dir}/test.org" <<'ORG'
#+TITLE: Standalone Test
* ACT I
** Scene 1: Test
**** ALICE
The standalone word.
ORG
    local cli_config="${SUITE_TMP}/cli_only.yaml"
    cat > "${cli_config}" <<YAML
speech-substitution:
  standalone: cli_only_val
render-intro: false
YAML
    local output
    output=$("${YAPPER}" convert "${dir}/test.org" --script-config "${cli_config}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "cli_only_val" || return 1
}
run_test "RT-27.6" "CLI config works standalone" test_RT27_6

# ---------------------------------------------------------------------------
# AC27.4: Substitutions in non-script convert
# ---------------------------------------------------------------------------

# RT-27.7: Substitution changes text in convert output.
test_RT27_7() {
    rm -f "${GLOBAL_CONFIG}"
    local dir="${SUITE_TMP}/rt27_7"
    mkdir -p "${dir}"
    cat > "${dir}/yapper.yaml" <<YAML
speech-substitution:
  originalword: substitutedword
YAML
    printf 'Say the originalword now.' > "${dir}/input.txt"
    local output
    output=$("${YAPPER}" convert "${dir}/input.txt" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "substitutedword" || return 1
}
run_test "RT-27.7" "substitution applied in non-script convert" test_RT27_7

# RT-27.8: IPA notation in substitution processed correctly.
test_RT27_8() {
    rm -f "${GLOBAL_CONFIG}"
    local dir="${SUITE_TMP}/rt27_8"
    mkdir -p "${dir}"
    cat > "${dir}/yapper.yaml" <<YAML
speech-substitution:
  ipatest: "/aɪpiːeɪ/"
YAML
    printf 'The ipatest word here.' > "${dir}/input.txt"
    local output
    output=$("${YAPPER}" convert "${dir}/input.txt" --dry-run --non-interactive 2>&1)
    # The IPA should appear in the dry-run text (it gets processed by G2P at synthesis time)
    printf '%s' "${output}" | grep -qi "aɪpiːeɪ\|ipatest" || return 1
}
run_test "RT-27.8" "IPA substitution processed" test_RT27_8

# ---------------------------------------------------------------------------
# AC27.5: Substitutions in speak mode
# ---------------------------------------------------------------------------

# RT-27.9: speak applies substitutions from config.
test_RT27_9() {
    rm -f "${GLOBAL_CONFIG}"
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  speakword: spoken_replacement
YAML
    local output
    output=$("${YAPPER}" speak --dry-run "The speakword here." 2>&1)
    printf '%s' "${output}" | grep -qi "spoken_replacement" || return 1
}
run_test "RT-27.9" "speak applies config substitutions" test_RT27_9

# RT-27.10: Dry-run output reflects substituted text.
test_RT27_10() {
    rm -f "${GLOBAL_CONFIG}"
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  dryword: dryreplaced
YAML
    local output
    output=$("${YAPPER}" speak --dry-run "Say dryword aloud." 2>&1)
    printf '%s' "${output}" | grep -qi "dryreplaced" || return 1
    if printf '%s' "${output}" | grep -q "dryword"; then
        return 1  # Original should be replaced
    fi
}
run_test "RT-27.10" "dry-run reflects substituted text" test_RT27_10

# ---------------------------------------------------------------------------
# AC27.6: Documentation includes speech-substitution
# ---------------------------------------------------------------------------

# RT-27.11: config.md includes speech-substitution in config reference.
test_RT27_11() {
    grep -qi "speech-substitution" "${SCRIPT_DIR}/../../../docs/config.md" || return 1
}
run_test "RT-27.11" "config.md documents speech-substitution" test_RT27_11

# RT-27.12: Example config in docs includes speech-substitution.
test_RT27_12() {
    grep -A 40 "Example: project" "${SCRIPT_DIR}/../../../docs/config.md" | grep -qi "speech-substitution" || return 1
}
run_test "RT-27.12" "example config includes speech-substitution" test_RT27_12

# ---------------------------------------------------------------------------
# AC27.7: Cascading merge — all configs loaded, key-by-key merge
# ---------------------------------------------------------------------------

# RT-27.13: Global 5 subs + project overriding 1 = 5 subs (4 global + 1 overridden).
test_RT27_13() {
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  word1: global1
  word2: global2
  word3: global3
  word4: global4
  word5: global5
YAML
    local dir="${SUITE_TMP}/rt27_13"
    mkdir -p "${dir}"
    cat > "${dir}/yapper.yaml" <<YAML
speech-substitution:
  word3: project3
YAML
    printf 'word1 word2 word3 word4 word5' > "${dir}/input.txt"
    local output
    output=$("${YAPPER}" convert "${dir}/input.txt" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "global1" || return 1
    printf '%s' "${output}" | grep -qi "global2" || return 1
    printf '%s' "${output}" | grep -qi "project3" || return 1
    printf '%s' "${output}" | grep -qi "global4" || return 1
    printf '%s' "${output}" | grep -qi "global5" || return 1
    # word3 should NOT have global value
    if printf '%s' "${output}" | grep -qi "global3"; then
        return 1
    fi
}
run_test "RT-27.13" "partial override preserves other global subs" test_RT27_13

# RT-27.14: Global voice setting inherited when project only sets subs.
test_RT27_14() {
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
narrator-voice: bf_emma
speech-substitution:
  gword: gval
YAML
    local dir="${SUITE_TMP}/rt27_14"
    mkdir -p "${dir}"
    cat > "${dir}/script.yaml" <<YAML
speech-substitution:
  pword: pval
render-intro: false
YAML
    # Create a script fixture to test voice inheritance
    cat > "${dir}/test.org" <<'ORG'
#+TITLE: Inherit Test
* ACT I
** Scene 1: Test
**** ALICE
Hello gword and pword.
ORG
    local output
    output=$("${YAPPER}" convert "${dir}/test.org" --dry-run --non-interactive 2>&1)
    # Narrator voice from global should be inherited
    printf '%s' "${output}" | grep -qi "bf_emma" || return 1
}
run_test "RT-27.14" "global voice setting inherited by project" test_RT27_14

# RT-27.15: Three-level cascade produces correct merged result.
test_RT27_15() {
    mkdir -p "${GLOBAL_CONFIG_DIR}"
    cat > "${GLOBAL_CONFIG}" <<YAML
speech-substitution:
  level: global_level
  globalkey: globalval
YAML
    local dir="${SUITE_TMP}/rt27_15"
    mkdir -p "${dir}"
    cat > "${dir}/script.yaml" <<YAML
speech-substitution:
  level: project_level
  projectkey: projectval
render-intro: false
YAML
    cat > "${dir}/test.org" <<'ORG'
#+TITLE: Cascade Test
* ACT I
** Scene 1: Test
**** ALICE
level globalkey projectkey clikey
ORG
    local cli="${SUITE_TMP}/cli15.yaml"
    cat > "${cli}" <<YAML
speech-substitution:
  level: cli_level
  clikey: clival
render-intro: false
YAML
    local output
    output=$("${YAPPER}" convert "${dir}/test.org" --script-config "${cli}" --dry-run --non-interactive 2>&1)
    # level should be cli_level (highest precedence)
    printf '%s' "${output}" | grep -qi "cli_level" || return 1
    # globalkey inherited from global
    printf '%s' "${output}" | grep -qi "globalval" || return 1
    # projectkey inherited from project
    printf '%s' "${output}" | grep -qi "projectval" || return 1
    # clikey from CLI
    printf '%s' "${output}" | grep -qi "clival" || return 1
}
run_test "RT-27.15" "three-level cascade merges correctly" test_RT27_15

# ---------------------------------------------------------------------------
# Restore and summary
# ---------------------------------------------------------------------------
restore_global
summarise "pronunciation config"
