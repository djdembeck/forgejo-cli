#!/usr/bin/env bash
# tests/run.sh — deterministic regression test entry point for fgh.
#
#.Usage:
#   tests/run.sh             # run all cases in tests/cases/*.bash
#   tests/run.sh <substring> # run only case files whose name contains it
#
#.Requirements: bash, curl (shadowed), jq, column, (unzip only if a fixture
# archive must be re-expanded — fixtures ship pre-expanded).
#
#.How it works:
#  - Tests/bin/curl is prepended to PATH. fgh's curl calls are recorded
#    (argv + body) to a temp log and served canned fixture responses from a
#    per-test response script. No network access, no credentials.
#  - FORGEJO_TOKEN is a sentinel (test-token); FGH_TOKEN/issue tokens are
#    distinct sentinels so tests can prove token precedence.
#  - Each case file is sourced; it defines a run() function and asserts via
#    tests/lib/assert.sh. Failures accumulate; exit status is nonzero if any
#    assertion fails.
#
#.Layout:
#   tests/run.sh          this entry point
#   tests/bin/curl        fake curl (records + serves)
#   tests/lib/*.sh        assertion + log helpers
#   tests/cases/*.bash    one file per feature area, defining run()
#   tests/fixtures/       canned response payloads

set -u
set -o pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"
FGH="$REPO_DIR/fgh"
export TESTS_DIR

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

FAKE_CURL_LOG="$TEST_TMP/curl.log"
export FAKE_CURL_LOG FAKE_CURL_SCRIPT="$TEST_TMP/response.sh"

PASS=0
FAIL=0
FAILED_TESTS=""
FILTER="${1:-}"

# shellcheck source=lib/assert.sh
source "$TESTS_DIR/lib/assert.sh"
# shellcheck source=lib/log.sh
source "$TESTS_DIR/lib/log.sh"

# ───────────────────────────────────────────────────────── environment
export FORGEJO_URL="https://forgejo.test"
export FORGEJO_TOKEN="test-repo-token"
export FORGEJO_ISSUE_TOKEN="test-issue-token"
export FGH_TOKEN=""
unset FGH_REPO FGH_DEFAULT_ASSIGNEE 2>/dev/null || true

# PATH: fake curl first, real jq/column/git still reachable.
export PATH="$TESTS_DIR/bin:$PATH"

# run_case FILE — source a case file in a fresh recording context.
run_case() {
    local case_file="$1"
    local case_name
    case_name="$(basename "$case_file")"
    : > "$FAKE_CURL_LOG"
    : > "$FAKE_CURL_LOG.bodies"
    : > "${FAKE_CURL_LOG}.hdrs"
    : > "$FAKE_CURL_SCRIPT"
    export FGH_REPO="acme/widgets"
    # shellcheck disable=SC1090
    source "$case_file"
    if declare -F run >/dev/null 2>&1; then
        run
        unset -f run 2>/dev/null || true
    else
        echo "SKIP $case_name (no run() defined)" >&2
    fi
}

echo "fgh regression tests"
echo "  fgh:      $FGH"
echo "  fake log: $FAKE_CURL_LOG"
echo

shopt -s nullglob
CASES=()
for f in "$TESTS_DIR"/cases/*.bash; do
    [ -n "$FILTER" ] && [[ "$(basename "$f")" != *"$FILTER"* ]] && continue
    CASES+=("$f")
done

for f in "${CASES[@]}"; do
    before_pass=$PASS; before_fail=$FAIL
    run_case "$f"
    dp=$((PASS - before_pass)); df=$((FAIL - before_fail))
    printf '  %-38s %s pass, %s fail\n' "$(basename "$f")" "$dp" "$df"
done

if [ "$FAIL" -eq 0 ]; then
    printf '\nOK: %s assertions passed.\n' "$PASS"
    exit 0
else
    printf '\nFAILED: %s assertion(s) failed out of %s.\n  failing: %s\n' \
        "$FAIL" "$((PASS + FAIL))" "$FAILED_TESTS"
    exit 1
fi
