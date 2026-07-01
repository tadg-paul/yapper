#!/usr/bin/env bash
# ABOUTME: Shared test harness for bash CLI tests.
# ABOUTME: Discovers the built yapper binary and provides pass/fail reporting.

set -euo pipefail
IFS=$'\n\t'

PASS=0
FAIL=0
TOTAL=0
FAILURES=()

# Discover the yapper binary from DerivedData
discover_binary() {
    local derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
    local binary
    binary=$(find "${derived_data}"/yapper-*/Build/Products/Debug -name yapper -type f 2>/dev/null | head -1)
    if [[ -z "${binary}" ]]; then
        printf 'ERROR: yapper binary not found in DerivedData. Run make build first.\n' >&2
        exit 1
    fi
    printf '%s' "${binary}"
}

YAPPER=$(discover_binary)
export YAPPER

# Run a single test. Usage: run_test "RT-4.1" "description" test_function_name
run_test() {
    local id="$1" description="$2" func="$3"
    TOTAL=$((TOTAL + 1))
    local output
    if output=$("${func}" 2>&1); then
        printf '  ✅ %s: %s\n' "${id}" "${description}"
        PASS=$((PASS + 1))
    else
        printf '  ❌ %s: %s\n' "${id}" "${description}"
        if [[ -n "${output}" ]]; then
            printf '     %s\n' "${output}" | head -5
        fi
        FAIL=$((FAIL + 1))
        FAILURES+=("${id}")
    fi
}

# Print summary and exit with appropriate code
summarise() {
    local suite="$1"
    printf '\n%s: %d passed, %d failed, %d total\n' "${suite}" "${PASS}" "${FAIL}" "${TOTAL}"
    if [[ ${FAIL} -gt 0 ]]; then
        printf 'Failures: %s\n' "${FAILURES[*]}"
        exit 1
    fi
}
