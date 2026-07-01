#!/usr/bin/env bash
# ABOUTME: One-off CLI test harness wrapper.
# ABOUTME: Reuses the shared CLI harness from the release-safe one-off tests.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../regression/cli/harness.sh"
