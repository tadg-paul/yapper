#!/usr/bin/env bash
# ABOUTME: One-off tests for `yap` shorthand command (issue #14).
# ABOUTME: Each test invokes the built yapper binary via its yap argv[0] dispatch.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: yap shorthand (RT-14.x)\n'

# The yap shorthand works via argv[0] dispatch in the binary itself.
# To test it without make install, we create a symlink named "yap"
# pointing at the built binary — same as what the install wrapper does,
# but without the exec indirection. The binary sees argv[0]="yap" and
# routes to the speak subcommand.
#
# NOTE: This tests the argv[0] dispatch only. The install-wrapper topology
# (exec -a yap through bin/yap → libexec/yapper for Bundle.main resolution)
# is tested by release.sh's runtime smoke test, which constructs the full
# bin/libexec layout.

YAP_LINK=$(mktemp -d)/yap
ln -s "${YAPPER}" "${YAP_LINK}"
trap 'rm -rf "$(dirname "${YAP_LINK}")"' EXIT

# ---------------------------------------------------------------------------
# Issue #14: yap shorthand
# Specs from: https://github.com/tigger04/yapper/issues/14
# ---------------------------------------------------------------------------

# RT-14.1: yap --dry-run routes to the speak subcommand.
# User action: yap --dry-run "hello"
# User observes: dry-run output with voice/speed/text (speak-specific output).
test_RT14_1() {
    local output
    output=$("${YAP_LINK}" --dry-run "hello" 2>/dev/null)
    printf '%s' "${output}" | grep -q '^voice:' || return 1
    printf '%s' "${output}" | grep -q 'text:.*hello' || return 1
    printf '%s' "${output}" | grep -q '(dry run' || return 1
}
run_test "RT-14.1" "yap --dry-run routes to speak subcommand" test_RT14_1

# RT-14.2: yap passes --voice and --speed flags through to speak.
# User action: yap --voice bf_emma --speed 1.25 --dry-run "test"
# User observes: voice: bf_emma, speed: 1.25 in output.
test_RT14_2() {
    local output
    output=$("${YAP_LINK}" --voice bf_emma --speed 1.25 --dry-run "test" 2>/dev/null)
    printf '%s' "${output}" | grep -q 'bf_emma' || return 1
    printf '%s' "${output}" | grep -q '1.25' || return 1
}
run_test "RT-14.2" "yap passes --voice and --speed through to speak" test_RT14_2

# RT-14.3: yap and yapper speak produce equivalent output.
# User action: yap --voice am_adam --dry-run "test" vs yapper speak --voice am_adam --dry-run "test"
# User observes: same voice in both outputs.
test_RT14_3() {
    local yap_voice yapper_voice
    yap_voice=$("${YAP_LINK}" --voice am_adam --dry-run "equivalence test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
    yapper_voice=$("${YAPPER}" speak --voice am_adam --dry-run "equivalence test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
    [[ "${yap_voice}" == "am_adam" ]] && [[ "${yapper_voice}" == "am_adam" ]] && [[ "${yap_voice}" == "${yapper_voice}" ]]
}
run_test "RT-14.3" "yap and yapper speak produce equivalent output" test_RT14_3

summarise "yap shorthand"
