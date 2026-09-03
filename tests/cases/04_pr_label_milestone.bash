# tests/cases/04_pr_label_milestone.bash — PR surface, labels, milestones.

run() {
    FGH_REPO=acme/widgets

    # ── pr list: filters and shape ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(jq '[.[] | select(.head.ref == "feature" and .base.ref == "main")]' "$TESTS_DIR/fixtures/prs_list.json")"
EOF
    out="$(cd /tmp && "$FGH" pr list --state open --head feature --base main --limit 5 --json number,title 2>/dev/null)"
    assert_eq "pr list projection" '[{"number":9,"title":"Add widget"}]' \
        "$(printf '%s' "$out" | jq -c '[ .[] | {number, title} ]')"
    assert_url_contains "pr list state" "state=open" "$(Url_of 1)"
    assert_url_contains "pr list head filter" "head=feature" "$(Url_of 1)"
    assert_url_contains "pr list base filter" "base=main" "$(Url_of 1)"
    assert_url_contains "pr list limit" "limit=5" "$(Url_of 1)"
    assert_url_contains "pr targets pulls endpoint" "/pulls?" "$(Url_of 1)"

    # ── pr create payload ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"number":9,"title":"Add widget","html_url":"https://forgejo.test/o/r/pulls/9"}'
EOF
    printf 'PR description\n' > "$TEST_TMP/pr_body.md"
    out="$(cd /tmp && "$FGH" pr create --head feature --base main --title "Add widget" --body-file "$TEST_TMP/pr_body.md" --json number 2>/dev/null)"
    assert_eq "pr create returns number" "9" "$(printf '%s' "$out" | jq -r .number)"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "pr create head" "feature" "$(printf '%s' "$payload" | jq -r .head)"
    assert_eq "pr create base" "main" "$(printf '%s' "$payload" | jq -r .base)"
    assert_eq "pr create title" "Add widget" "$(printf '%s' "$payload" | jq -r .title)"
    assert_eq "pr create body from file" "PR description" "$(printf '%s' "$payload" | jq -r .body)"
    assert_url_call "pr create POSTs /pulls" 1 "https://forgejo.test/api/v1/repos/acme/widgets/pulls"

    # ── pr edit PATCH ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/pr.json")"
EOF
    out="$(cd /tmp && "$FGH" pr edit 9 --body-file "$TEST_TMP/pr_body.md" 2>/dev/null)"
    assert_method_call "pr edit PATCH" 1 "PATCH"
    assert_url_call "pr edit URL" 1 "https://forgejo.test/api/v1/repos/acme/widgets/pulls/9"
    assert_eq "pr edit body" "PR description" "$(printf '%s' "$(Log_body 1)" | jq -r .body)"

    # ── pr comments use the issue-scoped endpoint ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":42,"body":"LGTM","user":{"login":"cov"},"created_at":"2026-08-01T00:00:00Z"}]'
EOF
    out="$(cd /tmp && "$FGH" pr comments 9 --json 2>/dev/null)"
    assert_contains "pr comments body" "LGTM" "$out"
    assert_url_contains "pr comments URL goes to issues/N/comments" "/issues/9/comments" "$(Url_of 1)"

    # ── pr comment posts {"body": ...} ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":43,"html_url":"u"}'
EOF
    out="$(cd /tmp && "$FGH" pr comment 9 "reviewed" >/dev/null 2>&1)"
    assert_method_call "pr comment POST" 1 "POST"
    assert_url_call "pr comment posts to issues comments" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/issues/9/comments"
    assert_contains "pr comment payload body" '"body":"reviewed"' "$(printf '%s' "$(Log_body 1)" | jq -c .)"

    # ── pr attach mirrors issue attach with ?name= ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/attachment.json")"
EOF
    printf 'data' > "$TEST_TMP/patch.diff"
    out="$(cd /tmp && "$FGH" pr attach 9 "$TEST_TMP/patch.diff" --name patch.diff 2>/dev/null)"
    assert_contains "pr attach multipart field" "attachment=@$TEST_TMP/patch.diff" "$(Log_line 1)"
    assert_url_contains "pr attach URL issues/N/assets" "/issues/9/assets?" "$(Url_of 1)"
    assert_url_contains "pr attach name query" "name=patch.diff" "$(Url_of 1)"

    # ── label list + create ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/labels.json")"
EOF
    out="$(cd /tmp && "$FGH" label list --json name,id 2>/dev/null)"
    assert_contains "label list names" "bug" "$out"
    assert_url_contains "label list URL" "/labels?" "$(Url_of 1)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/label_created.json")"
EOF
    out="$(cd /tmp && "$FGH" label create docs --color 0075ca --description "Documentation" 2>/dev/null)"
    assert_contains "label create output" "docs" "$out"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "label create color normalized" "0075ca" "$(printf '%s' "$payload" | jq -r .color)"
    assert_eq "label create description" "Documentation" "$(printf '%s' "$payload" | jq -r .description)"
    assert_not_contains "label create omits hash prefix" '"color":"#0075ca"' "$payload"

    # ── milestone lifecycle ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/milestones.json")"
EOF
    out="$(cd /tmp && "$FGH" milestone list --json title,due_on 2>/dev/null)"
    assert_contains "milestone list titles" "v1.1" "$out"
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":3,"title":"v1.2","state":"open","due_on":"2026-12-01T00:00:00Z"}'
EOF
    out="$(cd /tmp && "$FGH" milestone create "v1.2" --description "next" --due-on 2026-12-01T00:00:00Z 2>/dev/null)"
    assert_contains "milestone create output" "v1.2" "$out"
    payload="$(Log_body 1)"
    assert_eq "milestone create title" "v1.2" "$(printf '%s' "$payload" | jq -r .title)"
    assert_eq "milestone create due_on" "2026-12-01T00:00:00Z" "$(printf '%s' "$payload" | jq -r .due_on)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":2,"title":"v1.1","state":"closed"}'
EOF
    out="$(cd /tmp && "$FGH" milestone edit 2 --state closed 2>/dev/null)"
    assert_method_call "milestone edit PATCH" 1 "PATCH"
    assert_url_call "milestone edit URL" 1 "https://forgejo.test/api/v1/repos/acme/widgets/milestones/2"
    assert_eq "milestone edit state" "closed" "$(printf '%s' "$(Log_body 1)" | jq -r .state)"

    reset_log
    out="$(cd /tmp && "$FGH" milestone delete 2 2>/dev/null)"
    assert_method_call "milestone delete DELETE" 1 "DELETE"
    assert_url_call "milestone delete URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/milestones/2"
}
