# tests/cases/03_issue.bash — issue list/view/create/edit/comments/attach.

run() {
    FGH_REPO=acme/widgets

    # ── list: human output + URL shape ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/issues_list.json")"
EOF
    out="$(cd /tmp && "$FGH" issue list 2>/dev/null)"
    assert_contains "issue list table header" "STATE" "$out"
    assert_contains "issue list rows" "Broken thing" "$out"
    assert_url_contains "list default state open" "state=open" "$(Url_of 1)"
    assert_url_contains "list type=issues (excludes PRs)" "type=issues" "$(Url_of 1)"
    assert_url_contains "list limit=50 page=1" "limit=50" "$(Url_of 1)"

    # ── list --json + field projection ──
    reset_log
    out="$(cd /tmp && "$FGH" issue list --json number,title 2>/dev/null)"
    assert_eq "list --json projects fields" \
        '[{"number":5,"title":"Broken thing"},{"number":6,"title":"Feature ask"}]' \
        "$(printf '%s' "$out" | jq -c .)"
    out="$(cd /tmp && "$FGH" issue list --json 2>/dev/null)"
    assert_contains "bare --json returns full array" "Broken thing" "$out"

    # ── list --search maps to q= ──
    reset_log
    out="$(cd /tmp && "$FGH" issue list --state open --search 'broken thing' --limit 10 --json number 2>/dev/null)"
    assert_url_contains "search q encoded" "q=broken%20thing" "$(Url_of 1)"
    assert_url_contains "search limit capped" "limit=10" "$(Url_of 1)"

    # ── positional state ──
    reset_log
    out="$(cd /tmp && "$FGH" issue list closed 2>/dev/null)"
    assert_url_contains "positional closed state" "state=closed" "$(Url_of 1)"

    # ── view --json ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/issue.json")"
EOF
    reset_log
    out="$(cd /tmp && "$FGH" issue view 5 --json 2>/dev/null)"
    assert_eq "view --json returns issue object" "5" "$(printf '%s' "$out" | jq -r .number)"
    assert_eq "view --json state" "open" "$(printf '%s' "$out" | jq -r .state)"

    # ── view --jq ──
    reset_log
    out="$(cd /tmp && "$FGH" issue view 5 --jq .title 2>/dev/null)"
    assert_eq "view --jq title" "Broken thing" "$out"

    # ── view URL exact ──
    assert_url_call "issue view URL" 1 "https://forgejo.test/api/v1/repos/acme/widgets/issues/5"

    # ── create: argument-based (non-interactive) payload ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
calls=$(wc -l < "$FAKE_CURL_LOG")
if [ "$calls" -eq 1 ]; then
  Serve 200 "$(cat "$TESTS_DIR/fixtures/labels.json")"
else
  Serve 200 "$(cat "$TESTS_DIR/fixtures/created_issue.json")"
fi
EOF
    printf 'Full body from file\nline two\n' > "$TEST_TMP/body.md"
    out="$(cd /tmp && "$FGH" issue create "New bug" --body-file "$TEST_TMP/body.md" --assignee bob --label bug --json number,title 2>&1)"
    assert_eq "create returns number" "7" "$(printf '%s' "$out" | jq -r .number)"
    assert_method_call "create is POST" 2 "POST"
    payload="$(printf '%s' "$(Log_body 2)" | jq -c .)"
    assert_eq "create payload title" "New bug" "$(printf '%s' "$payload" | jq -r .title)"
    assert_eq "create payload body from file" "Full body from file
line two" "$(printf '%s' "$payload" | jq -r .body)"
    assert_eq "create payload assignee" '["bob"]' "$(printf '%s' "$payload" | jq -c .assignees)"
    # labels arrive as resolved int ids (label list GET happens first)
    assert_eq "create payload labels numeric" '[3]' "$(printf '%s' "$payload" | jq -c .labels)"

    # ── issue token used by create (issue-scope command) ──
    reset_log
    out="$(cd /tmp && FORGEJO_ISSUE_TOKEN=issue-tok FORGEJO_TOKEN=repo-tok "$FGH" issue create "T2" --body x >/dev/null 2>&1)"
    assert_auth_token "create uses issue token" 1 "issue-tok"

    # ── TTY-safe parsing: title from argv, not stdin, when args present ──
    reset_log
    out="$(cd /tmp && "$FGH" issue create "Argv title" --body stdin-less </dev/null 2>/dev/null)"
    assert_contains "argv title wins with closed stdin" '"title":"Argv title"' "$(printf '%s' "$(Log_body 1)" | jq -c .)"

    # ── edit: PATCH with only changed fields ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/issue.json")"
EOF
    out="$(cd /tmp && "$FGH" issue edit 5 --body-file "$TEST_TMP/body.md" 2>/dev/null)"
    assert_method_call "edit is PATCH" 1 "PATCH"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "edit payload body" "Full body from file
line two" "$(printf '%s' "$payload" | jq -r .body)"
    assert_eq "edit payload nulls dropped" "null" "$(printf '%s' "$payload" | jq '.state')"
    assert_url_call "edit URL" 1 "https://forgejo.test/api/v1/repos/acme/widgets/issues/5"

    # ── comments list + post ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":42,"body":"looks fixed","user":{"login":"dave"},"created_at":"2026-08-05T12:00:00Z"}]'
EOF
    out="$(cd /tmp && "$FGH" issue comments 5 --json 2>/dev/null)"
    assert_contains "comments list via --json" "looks fixed" "$out"
    if ! printf '%s' "$(Url_of 1)" | grep -q '/comments'; then
        assert_url_contains "comments URL" "/issues/5/comments" "$(Url_of 1)"
    fi

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/comment.json")"
EOF
    out="$(cd /tmp && "$FGH" issue comment 5 "looks fixed to me" >/dev/null 2>&1)"
    assert_method_call "comment is POST" 1 "POST"
    assert_eq "comment payload body" "looks fixed to me" "$(printf '%s' "$(Log_body 1)" | jq -r .body)" || \
        assert_contains "comment payload has body field" '"body"' "$(printf '%s' "$(Log_body 1)")"

    # comment routed to issues/{n}/comments, not pulls
    assert_url_call "comment posts to issues comments" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/issues/5/comments"

    # ── attach: multipart invocation exactness ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/attachment.json")"
EOF
    printf 'PNGDATA' > "$TEST_TMP/screenshot.png"
    out="$(cd /tmp && "$FGH" issue attach 5 "$TEST_TMP/screenshot.png" --name screenshot.png --json browser_download_url 2>/dev/null)"
    line1="$(Log_line 1)"
    assert_contains "attach uses -F attachment=@file" "attachment=@" "$line1"
    assert_contains "attach -F flag form" "-F attachment=@$TEST_TMP/screenshot.png" "$line1"
    assert_url_contains "attach posts to issues/N/assets" "/issues/5/assets" "$(Url_of 1)"
    assert_url_contains "attach name query param" "name=screenshot.png" "$(Url_of 1)"

    # custom name goes in the query string, not the part filename
    reset_log
    printf 'PNGDATA' > "$TEST_TMP/shot.png"
    out="$(cd /tmp && "$FGH" issue attach 5 "$TEST_TMP/shot.png" --name renamed.png 2>/dev/null)"
    assert_url_contains "attach --name in query" "name=renamed.png" "$(Url_of 1)"
    assert_contains "attach part uses file path" "attachment=@$TEST_TMP/shot.png" "$(Log_line 1)"
}
