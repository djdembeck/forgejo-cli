# tests/cases/02_api.bash — fgh api: methods, normalization, fields, input, jq.

run() {
    FGH_REPO=acme/widgets

    # ── endpoint normalization: leading slash optional ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"version":"16.0.3"}'
EOF
    out="$(cd /tmp && "$FGH" api /version 2>/dev/null)"
    assert_contains "api /version returned" "16.0.3" "$out"
    assert_url_call "leading slash stripped" 1 "https://forgejo.test/api/v1/version"

    # ── api/v1/ prefix never duplicated ──
    reset_log
    out="$(cd /tmp && "$FGH" api api/v1/version 2>/dev/null)"
    assert_url_call "api/v1 prefix not duplicated" 1 "https://forgejo.test/api/v1/version"

    # ── -X method passthrough ──
    reset_log
    out="$(cd /tmp && "$FGH" api -X DELETE repos/acme/widgets/issues/5 2>/dev/null)"
    assert_method_call "-X DELETE recorded" 1 "DELETE"
    assert_url_call "delete URL exact" 1 "https://forgejo.test/api/v1/repos/acme/widgets/issues/5"

    # ── -f key=value builds a JSON object and promotes GET to POST ──
    reset_log
    out="$(cd /tmp && "$FGH" api -f name=alpha -f color=#00aabb repos/acme/widgets/labels 2>/dev/null)"
    assert_method_call "-f bumps GET to POST" 1 "POST"
    body="$(Log_body 1)"
    assert_contains "field name in payload" '"name":"alpha"' "$(printf '%s' "$body" | jq -c .)"
    assert_contains "field color in payload" '"color":"#00aabb"' "$(printf '%s' "$body" | jq -c .)"

    # ── explicit -X POST with -f stays POST and merges ──
    reset_log
    out="$(cd /tmp && "$FGH" api -X POST -f title=hello repos/acme/widgets/issues 2>/dev/null)"
    assert_method_call "explicit POST kept" 1 "POST"
    assert_contains "explicit POST payload has title" '"title":"hello"' "$(printf '%s' "$(Log_body 1)" | jq -c .)"

    # ── --input FILE sends the file's exact bytes ──
    reset_log
    printf '{"body":"from file"}' > "$TEST_TMP/payload.json"
    out="$(cd /tmp && "$FGH" api -X PATCH --input "$TEST_TMP/payload.json" repos/acme/widgets/issues/5 2>/dev/null)"
    body="$(Log_body 1)"
    assert_eq "input file body byte-identical" '{"body":"from file"}' "$(printf '%s' "$body" | jq -c .)" || \
        assert_eq "input file body parses as file content" '{"body":"from file"}' "$(printf '%s' "$body" | jq -c .)"
    assert_method_call "--input method PATCH" 1 "PATCH"

    # ── --input - reads stdin ──
    reset_log
    out="$(printf '{"title":"stdin title"}' | (cd /tmp && "$FGH" api -X POST --input - repos/acme/widgets/labels 2>/dev/null))"
    assert_eq "stdin input payload" '{"title":"stdin title"}' "$(printf '%s' "$(Log_body 1)" | jq -c .)"

    # ── --jq applies a filter to the response ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"number":5,"title":"a"},{"number":6,"title":"b"}]'
EOF
    out="$(cd /tmp && "$FGH" api --jq '.[].number' repos/acme/widgets/issues 2>/dev/null)"
    assert_eq "api --jq extraction" "5
6" "$out"

    # ── -H headers reach curl verbatim ──
    reset_log
    out="$(cd /tmp && "$FGH" api -H 'X-Custom: probe' version 2>/dev/null)"
    assert_contains "custom header forwarded" "X-Custom: probe" "$(Log_line 1)"

    # ── raw-field building: values with = survive ──
    reset_log
    out="$(cd /tmp && "$FGH" api -f q=a=b version 2>/dev/null)"
    assert_contains "-f value containing = kept whole" '"q":"a=b"' "$(printf '%s' "$(Log_body 1)" | jq -c .)"

    # ── non-2xx on api keeps the exit + body contract ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 500 '{"message":"boom"}'
EOF
    out="$(cd /tmp && "$FGH" api version 2>/dev/null)"
    assert_exit "api 500 exits 1" 1 "$?"
    assert_empty "api 500 stdout empty" "$out"
}
