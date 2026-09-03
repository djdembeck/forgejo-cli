#!/usr/bin/env bash
# Extended first-class command coverage not exercised by the core cases.

run() {
    # Complete issue filters.
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[]'
EOF
    "$FGH" issue list --mentioned alice --since 2026-01-01T00:00:00Z \
        --before 2026-09-01T00:00:00Z --sort recentupdate --json >/dev/null
    assert_url_contains "issue mentioned filter" 1 "mentioned_by=alice"
    assert_url_contains "issue since filter" 1 "since=2026-01-01T00%3A00%3A00Z"
    assert_url_contains "issue before filter" 1 "before=2026-09-01T00%3A00%3A00Z"
    assert_url_contains "issue sort filter" 1 "sort=recentupdate"

    # Comment attachment lifecycle.
    reset_log
    printf 'image' > "$TEST_TMP/comment.png"
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 201 '{"id":71,"name":"comment.png","browser_download_url":"https://forgejo.test/attachments/uuid"}'
EOF
    out="$("$FGH" issue comment-attach 42 "$TEST_TMP/comment.png" --name comment.png --jq .browser_download_url)"
    assert_eq "comment attachment URL" "https://forgejo.test/attachments/uuid" "$out"
    assert_url_contains "comment attachment endpoint" 1 "/issues/comments/42/assets?name=comment.png"
    assert_contains "comment attachment multipart" "attachment=@$TEST_TMP/comment.png" "$(Log_line 1)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":71,"name":"comment.png","size":5,"browser_download_url":"u"}]'
EOF
    out="$("$FGH" issue comment-attachments 42 --json)"
    assert_contains "comment attachment listing" "comment.png" "$out"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    "$FGH" issue comment-detach 42 71 >/dev/null
    assert_method_call "comment attachment delete method" 1 DELETE
    assert_url_call "comment attachment delete endpoint" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/issues/comments/42/assets/71"

    # PR create returns only the canonical URL in human mode.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 201 '{"number":9,"title":"Add widget","html_url":"https://forgejo.test/acme/widgets/pulls/9"}'
EOF
    out="$("$FGH" pr create --head feature --base main --title "Add widget")"
    assert_eq "pr create canonical URL" "https://forgejo.test/acme/widgets/pulls/9" "$out"

    # Diff is emitted exactly once.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 'diff --git a/a b/a'
EOF
    out="$("$FGH" pr diff 9)"
    assert_eq "pr diff emitted once" "diff --git a/a b/a" "$out"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"filename":"a.go","status":"modified","additions":2,"deletions":1}]'
EOF
    out="$("$FGH" pr files 9 --json filename)"
    assert_eq "pr files structured" "a.go" "$(jq -r '.[0].filename' <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"sha":"abcdef123456","commit":{"message":"change"},"author":{"login":"alice"}}]'
EOF
    out="$("$FGH" pr commits 9 --json sha)"
    assert_eq "pr commits structured" "abcdef123456" "$(jq -r '.[0].sha' <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
calls=$(wc -l < "$FAKE_CURL_LOG")
if [ "$calls" -eq 1 ]; then
  Serve 200 '{"number":9,"head":{"sha":"abcdef123456"}}'
else
  Serve 200 '{"state":"success","statuses":[{"status":"success","context":"ci","description":"ok"}]}'
fi
EOF
    out="$("$FGH" pr checks 9 --json)"
    assert_eq "pr checks combined state" "success" "$(jq -r .state <<<"$out")"
    assert_url_contains "pr checks head status endpoint" 2 "/commits/abcdef123456/status"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
calls=$(wc -l < "$FAKE_CURL_LOG")
if [ "$calls" -eq 1 ]; then
  Serve 200 '{"number":9,"state":"open","title":"Add widget","mergeable":true}'
else
  Serve 404 '{"message":"not merged"}'
fi
EOF
    out="$("$FGH" pr status 9)"
    assert_contains "unmerged PR status" "merged: no" "$out"
    assert_url_contains "authoritative merge status endpoint" 2 "/pulls/9/merge"

    # Review read/write surfaces.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":90,"user":{"login":"reviewer"},"state":"COMMENT","body":"review body","comments_count":1}]'
EOF
    out="$("$FGH" pr reviews 9 --json)"
    assert_eq "review body preserved" "review body" "$(jq -r '.[0].body' <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":91,"body":"inline","user":{"login":"reviewer"},"path":"a.go","position":4}]'
EOF
    out="$("$FGH" pr review-comments 9 90 --json)"
    assert_eq "inline review comments" "inline" "$(jq -r '.[0].body' <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":92,"state":"APPROVED"}'
EOF
    "$FGH" pr review 9 --approve --body lgtm >/dev/null
    assert_eq "review approval event" "APPROVED" "$(Log_body 1 | jq -r .event)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":93,"path":"a.go"}'
EOF
    "$FGH" pr review-comment 9 90 --path a.go --line 4 --body inline >/dev/null
    assert_url_contains "inline review creation endpoint" 1 "/pulls/9/reviews/90/comments"
    assert_eq "inline review line" "4" "$(Log_body 1 | jq -r .new_position)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":90,"state":"COMMENT"}'
EOF
    "$FGH" pr review-reply 9 90 --body done >/dev/null
    assert_url_call "pending review submission endpoint" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/pulls/9/reviews/90"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    "$FGH" pr reviewer add 9 alice --team backend >/dev/null
    assert_eq "requested reviewer users" '["alice"]' "$(Log_body 1 | jq -c .reviewers)"
    assert_eq "requested reviewer teams" '["backend"]' "$(Log_body 1 | jq -c .team_reviewers)"

    reset_log
    "$FGH" pr reviewer remove 9 alice >/dev/null
    assert_method_call "reviewer removal method" 1 DELETE

    reset_log
    "$FGH" pr merge 9 --manually-merged --commit-id deadbeef >/dev/null
    assert_eq "manual merge commit id" "deadbeef" "$(Log_body 1 | jq -r .MergeCommitID)"

    reset_log
    "$FGH" pr update-branch 9 --style rebase >/dev/null
    assert_url_contains "update branch style" 1 "/pulls/9/update?style=rebase"

    # Actions run filters and current runner lifecycle.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"version":"16.0.3+gitea-1.22.0"}'
EOF
    out="$(env -u FGH_REPO "$FGH" instance version --jq .version)"
    assert_eq "instance version" "16.0.3+gitea-1.22.0" "$out"
    assert_url_call "instance version endpoint" 1 "https://forgejo.test/api/v1/version"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"total_count":1,"workflow_runs":[{"id":5,"status":"failure","title":"ci"}]}'
EOF
    "$FGH" actions list --status failure --event pull_request --ref refs/heads/main \
        --workflow ci.yml --run-number 7 --limit 1 --json >/dev/null
    assert_url_contains "run status filter" 1 "status=failure"
    assert_url_contains "run event filter" 1 "event=pull_request"
    assert_url_contains "run ref filter" 1 "ref=refs%2Fheads%2Fmain"
    assert_url_contains "run workflow filter" 1 "workflow_id=ci.yml"
    assert_url_contains "run number filter" 1 "run_number=7"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":21,"name":"org-runner","labels":["linux"]}]'
EOF
    out="$("$FGH" actions runner list --org acme --limit 1 --json)"
    assert_eq "organization runner list" "org-runner" "$(jq -r '.[0].name' <<<"$out")"
    assert_url_contains "organization runner endpoint" 1 "/orgs/acme/actions/runners?page=1&limit=1"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":11,"name":"shell-1","status":"idle","labels":["linux"]}'
EOF
    out="$("$FGH" actions runner view 11 --json)"
    assert_eq "runner view" "shell-1" "$(jq -r .name <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 201 '{"id":12,"uuid":"runner-uuid","token":"runner-token","name":"shell-2"}'
EOF
    out="$("$FGH" actions runner register --name shell-2 --description Linux --ephemeral --json)"
    assert_eq "runner registration token" "runner-token" "$(jq -r .token <<<"$out")"
    assert_eq "runner registration ephemeral" "true" "$(Log_body 1 | jq -r .ephemeral)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":13,"name":"queued","status":"waiting","runs_on":["linux"]}]'
EOF
    out="$("$FGH" actions runner jobs --labels linux --json)"
    assert_eq "runner jobs" "queued" "$(jq -r '.[0].name' <<<"$out")"
    assert_url_contains "runner job labels" 1 "labels=linux"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 'artifact-bytes'
EOF
    "$FGH" actions artifact download 55 "$TEST_TMP/artifact.zip" >/dev/null
    assert_eq "artifact download bytes" "artifact-bytes" "$(cat "$TEST_TMP/artifact.zip")"
    assert_auth_token "artifact download authentication" 1 "test-repo-token"

    # Existing variables update with PUT; absent variables create with POST is
    # covered by 06_actions_config.bash.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
calls=$(wc -l < "$FAKE_CURL_LOG")
if [ "$calls" -eq 1 ]; then Serve 200 '{"name":"ENV","data":"old"}'; else Serve 204 ''; fi
EOF
    "$FGH" actions variable set ENV production >/dev/null
    assert_method_call "existing variable update method" 2 PUT

    # Release asset read/delete.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":91,"name":"dist.zip","size":10,"browser_download_url":"u"}]'
EOF
    out="$("$FGH" release assets 22 --json)"
    assert_eq "release assets" "dist.zip" "$(jq -r '.[0].name' <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    "$FGH" release delete-asset 22 91 >/dev/null
    assert_method_call "release asset delete" 1 DELETE
    assert_url_contains "release asset delete endpoint" 1 "/releases/22/assets/91"
}
