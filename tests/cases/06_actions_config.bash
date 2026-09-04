# tests/cases/06_actions_config.bash — secrets/variables/runners packets and paths.

run() {
    FGH_REPO=acme/widgets

    # ── secret list (values never returned by API) ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/secrets.json")"
EOF
    out="$(cd /tmp && "$FGH" actions secret list --json 2>/dev/null)"
    assert_contains "secret list names" "API_KEY" "$out"
    assert_url_call "secret list URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/secrets?page=1&limit=50"

    # ── secret set via stdin (non-TTY) sends {"data": VALUE} to PUT ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    out="$(printf 's3cr3t-value' | (cd /tmp && "$FGH" actions secret set API_KEY) 2>/dev/null)"
    assert_contains "secret set confirmation" "API_KEY" "$out"
    assert_method_call "secret set is PUT" 1 "PUT"
    assert_url_call "secret set URL exact" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/secrets/API_KEY"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "secret set payload wraps value in data" '{"data":"s3cr3t-value"}' "$payload"
    # secret must never land in the URL or as a bare body without the data key
    assert_not_contains "secret value not in URL" "s3cr3t" "$(Url_of 1)"

    # ── secret delete ──
    reset_log
    out="$(cd /tmp && "$FGH" actions secret delete API_KEY 2>/dev/null)"
    assert_method_call "secret delete DELETE" 1 "DELETE"
    assert_url_call "secret delete URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/secrets/API_KEY"

    # ── variable set sends {"value": VALUE} (not {data} like secrets) ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
calls=$(wc -l < "$FAKE_CURL_LOG")
if [ "$calls" -eq 1 ]; then
  Serve 404 '{"message":"not found"}'
else
  Serve 204 ''
fi
EOF
    out="$(cd /tmp && "$FGH" actions variable set ENV production 2>/dev/null)"
    assert_contains "variable set confirms" "ENV" "$out"
    payload="$(printf '%s' "$(Log_body 2)" | jq -c .)"
    assert_eq "variable set payload value key" '{"value":"production"}' "$payload"
    assert_url_call "variable set URL" 2 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/variables/ENV"
    assert_method_call "variable create POST" 2 "POST"

    # ── variable list uses {"name","data"} shape ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/variables.json")"
EOF
    out="$(cd /tmp && "$FGH" actions variable list --json 2>/dev/null)"
    assert_contains "variable list value from data field" "production" "$out"
    assert_url_contains "variable list URL" "/actions/variables?" "$(Url_of 1)"

    reset_log
    out="$(cd /tmp && "$FGH" actions variable delete ENV 2>/dev/null)"
    assert_method_call "variable delete DELETE" 1 "DELETE"
    assert_url_call "variable delete URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/variables/ENV"

    # ── runner list: bare array fixture (16.0.3 live-observed shape) ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/runners.json")"
EOF
    out="$(cd /tmp && "$FGH" actions runner list --json 2>/dev/null)"
    assert_contains "runner list bare array works" "shell-1" "$out"
    assert_url_call "runner list URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/runners?page=1&limit=50"

    # ── runner token: GET registration-token, prints .token ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/registration_token.json")"
EOF
    out="$(cd /tmp && "$FGH" actions runner token 2>/dev/null)"
    assert_eq "runner token value printed" "reg-token-abc123" "$out"
    assert_url_call "runner token URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/runners/registration-token"
    assert_method_call "runner token GET" 1 "GET"

    # ── artifact list, scoped and unscoped ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/artifacts.json")"
EOF
    out="$(cd /tmp && "$FGH" actions artifact list 2>/dev/null)"
    assert_contains "artifact list names" "dist" "$out"
    assert_url_contains "artifact list default repo-wide" "/actions/artifacts?" "$(Url_of 1)"

    reset_log
    out="$(cd /tmp && "$FGH" actions artifact list --run 123 2>/dev/null)"
    assert_url_contains "artifact list --run path" "/actions/runs/123/artifacts" "$(Url_of 1)"

    reset_log
    out="$(cd /tmp && "$FGH" actions artifact delete 55 2>/dev/null)"
    assert_method_call "artifact delete DELETE" 1 "DELETE"
    assert_url_call "artifact delete URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/artifacts/55"
}
