# shellcheck shell=bash
# tests/lib/assert.sh — minimal deterministic assertion helpers.
# Sourced by tests/cases/*.bash; updates PASS/FAIL counters via run.sh.

# _fmt_actual — truncate long actual values for readable failure output.
_fmt_actual() {
    local a
    a="$(printf '%s' "${1:-}" | head -c 200 | tr '\n' '~')"
    printf '%s' "$a"
}

assert_eq() { # assert_eq NAME EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+, }$1"
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' \
            "$1" "$(_fmt_actual "$2")" "$(_fmt_actual "$3")" >&2
    fi
}

assert_contains() { # assert_contains NAME NEEDLE HAYSTACK
    if printf '%s' "${3:-}" | grep -qF -- "$2"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+, }$1"
        printf 'FAIL %s\n  wanted substring: %s\n  in:              %s\n' \
            "$1" "$(_fmt_actual "$2")" "$(_fmt_actual "$3")" >&2
    fi
}


assert_not_contains() { # assert_not_contains NAME NEEDLE HAYSTACK
    if printf '%s' "${3:-}" | grep -qF -- "$2"; then
        FAIL=$((FAIL+1))
        FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+, }$1"
        printf 'FAIL %s\n  forbidden substring present: %s\n  in: %s\n' \
            "$1" "$(_fmt_actual "$2")" "$(_fmt_actual "$3")" >&2
    else
        PASS=$((PASS+1))
    fi
}

assert_exit() { # assert_exit NAME EXPECTED_STATUS ACTUAL_STATUS
    if [ "$2" -eq "$3" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+, }$1"
        printf 'FAIL %s\n  expected exit: %s\n  actual exit:   %s\n' \
            "$1" "$2" "$3" >&2
    fi
}

assert_empty() { # assert_empty NAME VALUE
    if [ -z "${2:-}" ]; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+, }$1"
        printf 'FAIL %s\n  expected empty, got: %s\n' "$1" "$(_fmt_actual "$2")" >&2
    fi
}

assert_success() { # assert_success NAME EXIT_CODE
    assert_exit "$1" 0 "${2:-1}"
}

# assert_url_call NAME CALL_N EXPECTED_URL — call N hit exactly this URL.
assert_url_call() {
    assert_eq "$1" "$3" "$(Url_of "$2")"
}

# assert_url_contains NAME CALL_N NEEDLE — URL substr match (query strings).
assert_url_contains() {
    if [[ "$2" =~ ^[0-9]+$ ]]; then
        assert_contains "$1" "$3" "$(Url_of "$2")"
    else
        assert_contains "$1" "$2" "$3"
    fi
}

# assert_method_call NAME CALL_N EXPECTED_METHOD.
assert_method_call() {
    assert_eq "$1" "$3" "$(Method_of "$2")"
}

# assert_auth_token NAME CALL_N EXPECTED_TOKEN — Authorization header carried token.
# Since FIX 6 the token is passed to curl via `-H @file` (never in argv), so
# the header line is checked from the fake curl's expanded-header records
# (Log_headers), which mirror what real curl would have put on the wire.
assert_auth_token() {
    local hdr; hdr="$(Log_headers "$2")"
    if printf '%s' "$hdr" | grep -q 'Authorization' && printf '%s' "$hdr" | grep -qF -- "$3"; then
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS="${FAILED_TESTS}${FAILED_TESTS:+, }$1"
        printf 'FAIL %s\n  expected Authorization header with token %s\n  headers: %s\n' \
            "$1" "$3" "$(printf '%s' "$hdr" | head -c 160)" >&2
    fi
}

# assert_no_network_env — guard: test must not leak credentials.
# Each case runs with FORGEJO_TOKEN set to a sentinel; production fgh must send
# the sentinel, and tests must never hard-code the real-looking value.
#
# reset_log — clear recording between calls within one case.
reset_log() {
    : > "$FAKE_CURL_LOG"
    : > "${FAKE_CURL_LOG}.bodies"
    : > "${FAKE_CURL_LOG}.hdrs"
}
