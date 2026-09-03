# tests/cases/12_test_gaps.bash — regression coverage for the 10 untested
# validation/error branches from the Test Gaps audit.
# shellcheck disable=SC2034  # FGH_REPO mirrors the other case files
# TG1 (P1)  option rejection on non-supporting commands (--json on issue
#           close, --limit on pr merge) — usage_die, exit 2, zero API calls
# TG2       --limit non-numeric → "Usage: --limit N", exit 2, no API call
# TG3       --state merged → "Error: --state must be open, closed, or all",
#           exit 2, no API call
# TG4       --json field-name injection guard (_project_filter)
# TG5       label create/edit --color non-hex → usage_die, exit 2, no API call
# TG6       pr status merge-probe HTTP 500 → die, exit 1
# TG7       actions variable set inspect-probe HTTP 500 → die, exit 1, no PUT
# TG8       empty secret (stdin and --body '') → die, exit 1, no PUT
# TG9       fgh api with failing curl (exit 7) → "Error: curl failed", exit 1
# TG10      pr merge --manually-merged without --commit-id → usage_die, exit 2

run() {
    FGH_REPO=acme/widgets

    # ── TG1 (P1): common-option trio is rejected by the non-supporting
    #    commands' own parsers (A5 passthrough pre-pass + _no_flags), NOT
    #    silently stripped. Both probes must exit 2 naming the flag and must
    #    make zero API calls.
    reset_log
    out="$(cd /tmp && "$FGH" issue close 5 --json 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG1 issue close --json exits 2" 2 "$rc"
    assert_contains "TG1 issue close names the flag" \
        "Usage: issue close: unknown argument '--json'" "$out"
    assert_eq "TG1 issue close makes no API call" "0" "$(Log_count)"
    # stdout empty (the usage error must be the only output)
    stdout="$(cd /tmp && "$FGH" issue close 5 --json 2>/dev/null)"; rc=$?
    assert_exit "TG1 issue close stdout probe still exits 2" 2 "$rc"
    assert_eq "TG1 issue close writes nothing to stdout" "" "$stdout"

    reset_log
    out="$(cd /tmp && "$FGH" pr merge 9 --limit 5 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG1 pr merge --limit exits 2" 2 "$rc"
    assert_contains "TG1 pr merge names --limit" \
        "Usage: pr merge: unknown argument '--limit'" "$out"
    assert_eq "TG1 pr merge makes no API call" "0" "$(Log_count)"

    # ── TG2: --limit abc fails numeric validation in the shared pre-pass
    #    (usage_die "--limit N", exit 2) before any command parser runs.
    reset_log
    out="$(cd /tmp && "$FGH" issue list --limit abc 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG2 --limit abc exits 2" 2 "$rc"
    assert_contains "TG2 --limit abc message" "Usage: --limit N" "$out"
    assert_eq "TG2 --limit abc makes no API call" "0" "$(Log_count)"

    # ── TG3: --state merged fails the open|closed|all whitelist inside
    #    _common_opt. Note the asymmetry: --state is validated by echo+exit 2
    #    (no "Usage:" prefix), not usage_die.
    reset_log
    out="$(cd /tmp && "$FGH" issue list --state merged 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG3 --state merged exits 2" 2 "$rc"
    assert_contains "TG3 --state merged message" \
        "Error: --state must be open, closed, or all" "$out"
    assert_eq "TG3 --state merged makes no API call" "0" "$(Log_count)"

    # ── TG4: injection guard in _project_filter — field names not matching
    #    ^[A-Za-z_][A-Za-z0-9_]*$ die before the jq filter is ever built.
    #    The list request itself runs first (it must succeed), so the fake
    #    curl serves a valid body; the guard fires afterward during
    #    structured output. Assert stdout stayed empty so the crafted-but-
    #    unvalidated field list never produced output.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"number":1,"title":"one"}]'
EOF
    out="$(cd /tmp && "$FGH" issue list --json 'number;bad' 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG4 invalid --json field exits 1" 1 "$rc"
    assert_contains "TG4 names the invalid field" \
        "Error: invalid --json field name: 'number;bad'" "$out"
    stdout="$(cd /tmp && "$FGH" issue list --json 'number;bad' 2>/dev/null)"; rc=$?
    assert_exit "TG4 stdout probe still exits 1" 1 "$rc"
    assert_eq "TG4 stdout stays empty" "" "$stdout"
    # the guard is not format-dependent: semicolon, quotes and spaces all die
    reset_log
    for bad in 'a;b' '"drop"' 'two words'; do
        out="$(cd /tmp && "$FGH" issue list --json "$bad" 2>&1 >/dev/null)"; rc=$?
        assert_exit "TG4 field '$bad' exits 1" 1 "$rc"
        assert_contains "TG4 field '$bad' named" "invalid --json field name" "$out"
    done

    # ── TG5: --color must be 6-digit hex on BOTH label create and edit,
    #    rejected before any API call.
    reset_log
    out="$(cd /tmp && "$FGH" label create bad --color red 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG5 label create --color red exits 2" 2 "$rc"
    assert_contains "TG5 label create color message" \
        "Usage: label create --color must be a 6-digit hex like 00aabb (got 'red')" "$out"
    assert_eq "TG5 label create makes no API call" "0" "$(Log_count)"

    reset_log
    out="$(cd /tmp && "$FGH" label edit 3 --color blue 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG5 label edit --color blue exits 2" 2 "$rc"
    assert_contains "TG5 label edit color message" \
        "Usage: label edit --color must be 6-digit hex" "$out"
    assert_eq "TG5 label edit makes no API call" "0" "$(Log_count)"

    # ── TG6: pr status — first GET /pulls/9 serves the PR fixture (200),
    #    the merge-probe GET /pulls/9/merge returns 500. Anything but
    #    204/404 must die with the exact die() message (exit 1). The 404→
    #    unmerged / 204→merged happy mappings are covered elsewhere.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */pulls/9/merge) Serve 500 '{"message":"merge backend down"}' ;;
  */pulls/9)       Serve 200 "$(cat "$TESTS_DIR/fixtures/pr.json")" ;;
  *)               Serve 404 '{"message":"unexpected call"}' ;;
esac
EOF
    out="$(cd /tmp && "$FGH" pr status 9 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG6 merge-probe 500 exits 1" 1 "$rc"
    assert_contains "TG6 names the HTTP 500 merge failure" \
        "Error: could not determine merge status for PR #9 (HTTP 500)" "$out"
    # both calls were made in order: PR fetch, then merge probe
    assert_url_call "TG6 PR fetch happened first" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/pulls/9"
    assert_url_call "TG6 merge probe was sent" 2 \
        "https://forgejo.test/api/v1/repos/acme/widgets/pulls/9/merge"

    # ── TG7: actions variable set probes the variable first;
    #    a 200 → PUT and 404 → POST, anything else dies. HTTP 500 on the
    #    probe must exit 1 naming the failure AND must never issue the
    #    write: Log_count stays at 1 (the probe only).
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */actions/variables/ENV) Serve 500 '{"message":"vars backend down"}' ;;
  *)                       Serve 404 '{"message":"unexpected call"}' ;;
esac
EOF
    out="$(cd /tmp && "$FGH" actions variable set ENV production 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG7 variable-inspect 500 exits 1" 1 "$rc"
    assert_contains "TG7 names the inspect failure" \
        "Error: could not inspect variable ENV (HTTP 500)" "$out"
    assert_eq "TG7 no write after failed probe" "1" "$(Log_count)"
    assert_url_call "TG7 probe URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/variables/ENV"
    assert_not_contains "TG7 no Set-variable echo on failure" "Set variable" "$out"

    # ── TG8: empty secret is refused (die, exit 1) whether the value
    #    arrives via closed-stdin or --body ''; no PUT is issued either way.
    reset_log
    out="$(cd /tmp && printf '' | "$FGH" actions secret set API_KEY 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG8 empty stdin secret exits 1" 1 "$rc"
    assert_contains "TG8 empty stdin message" \
        "Error: refusing to set an empty secret" "$out"
    assert_eq "TG8 empty stdin makes no API call" "0" "$(Log_count)"

    reset_log
    out="$(cd /tmp && "$FGH" actions secret set API_KEY --body '' 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG8 --body '' exits 1" 1 "$rc"
    assert_contains "TG8 --body '' message" \
        "Error: refusing to set an empty secret" "$out"
    assert_eq "TG8 --body '' makes no API call" "0" "$(Log_count)"

    # ── TG9: raw api path surfaces a real curl failure (exit 7 connection
    #    refused) as "Error: curl failed" on stderr, exit 1, no stdout.
    reset_log
    printf '#!/usr/bin/env bash\nexit 7\n' > "$FAKE_CURL_SCRIPT"
    out="$(cd /tmp && "$FGH" api version 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG9 curl failure exits 1" 1 "$rc"
    assert_contains "TG9 curl failure message" "Error: curl failed" "$out"
    stdout="$(cd /tmp && "$FGH" api version 2>/dev/null)"; rc=$?
    assert_exit "TG9 stdout probe still exits 1" 1 "$rc"
    assert_eq "TG9 stdout stays empty" "" "$stdout"

    # ── TG10: --manually-merged without --commit-id is a usage error before
    #    repo resolution even matters; no API call.
    reset_log
    out="$(cd /tmp && "$FGH" pr merge 9 --manually-merged 2>&1 >/dev/null)"; rc=$?
    assert_exit "TG10 --manually-merged w/o --commit-id exits 2" 2 "$rc"
    assert_contains "TG10 message" \
        "Usage: pr merge --manually-merged requires --commit-id SHA" "$out"
    assert_eq "TG10 makes no API call" "0" "$(Log_count)"
}
