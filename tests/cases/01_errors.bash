# tests/cases/01_errors.bash — non-2xx responses surface body and exit nonzero.

run() {
    FGH_REPO=acme/widgets

    # ── 404 on a JSON error body ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 404 '{"message":"Not Found","url":"https://forgejo.test/api/swagger"}'
EOF
    err="$(cd /tmp && "$FGH" issue view 999 2>&1 >/dev/null)"
    rc=$?
    assert_exit "issue view 404 exits 1" 1 "$rc"
    assert_contains "404 message on stderr" "404" "$err"
    assert_contains "404 body .message on stderr" "Not Found" "$err"

    # ── 403 forbidden with a non-.message payload ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 403 '{"message":"token does not include required scope","url":"x"}'
EOF
    err="$(cd /tmp && "$FGH" actions secret list 2>&1 >/dev/null)"
    assert_exit "secret list 403 exits 1" 1 "$?"
    assert_contains "403 scope error visible" "token does not include required scope" "$err"

    # ── 500 with a plain-text (non-JSON) body ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 500 'internal error: database unavailable'
EOF
    err="$(cd /tmp && "$FGH" issue list 2>&1 >/dev/null)"
    assert_exit "500 exits 1" 1 "$?"
    assert_contains "raw non-JSON body surfaces" "database unavailable" "$err"

    # ── 422 on create with field-level error detail preserved ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 422 '{"message":"validation error","errors":[{"field":"title","detail":"is required"}]}'
EOF
    err="$(cd /tmp && "$FGH" issue create "bad issue" 2>&1 >/dev/null)"
    assert_exit "422 create exits 1" 1 "$?"
    assert_contains "422 body preserved" "validation" "$err"

    # ── failure must not emit success-shaped stdout noise ──
    reset_log
    out="$(cd /tmp && "$FGH" issue view 999 2>/dev/null)"
    assert_exit "no stdout on failure path" 1 "$?"
    assert_empty "stdout silent on HTTP error" "$out"
}
