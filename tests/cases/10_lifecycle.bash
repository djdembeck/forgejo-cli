#!/usr/bin/env bash
# Remaining lifecycle and pagination contracts.

run() {
    # Generic pagination fetches a second page and honors the caller limit.
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
calls=$(wc -l < "$FAKE_CURL_LOG")
if [ "$calls" -eq 1 ]; then
  Serve 200 "$(jq -n '[range(1;51) | {number:.,state:"open",title:("issue-" + (.|tostring)),labels:[]}]')"
else
  Serve 200 "$(jq -n '[range(51;56) | {number:.,state:"open",title:("issue-" + (.|tostring)),labels:[]}]')"
fi
EOF
    out="$("$FGH" issue list --limit 55 --json number)"
    assert_eq "pagination result count" "55" "$(jq length <<<"$out")"
    assert_eq "pagination request count" "2" "$(Log_count)"
    assert_url_contains "pagination second page" 2 "page=2"
    assert_url_contains "pagination remaining limit" 2 "limit=5"

    # Issue state and attachment lifecycle.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"number":5,"title":"issue","state":"closed"}'
EOF
    out="$("$FGH" issue close 5)"
    assert_contains "issue close output" "Closed #5" "$out"
    assert_eq "issue close state payload" "closed" "$(Log_body 1 | jq -r .state)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"number":5,"title":"issue","state":"open"}'
EOF
    "$FGH" issue open 5 >/dev/null
    assert_eq "issue open state payload" "open" "$(Log_body 1 | jq -r .state)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":71,"name":"a.png","size":5,"browser_download_url":"u"}]'
EOF
    out="$("$FGH" issue attach-list 5 --json)"
    assert_eq "issue attachment list" "a.png" "$(jq -r '.[0].name' <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    "$FGH" issue detach 5 71 >/dev/null
    assert_method_call "issue detach method" 1 DELETE

    # Label mutation and ensure-noop behavior.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":3,"name":"bug","color":"d73a4a","exclusive":false}'
EOF
    "$FGH" label edit 3 --no-exclusive >/dev/null
    assert_eq "label exclusive false" "false" "$(Log_body 1 | jq -r .exclusive)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    "$FGH" label delete 3 >/dev/null
    assert_method_call "label delete method" 1 DELETE

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"name":"bug"},{"name":"enhancement"},{"name":"documentation"},{"name":"security"},{"name":"performance"}]'
EOF
    out="$("$FGH" label ensure)"
    assert_contains "label ensure skips existing" "5 already existed" "$out"
    assert_eq "label ensure no writes" "1" "$(Log_count)"

    # PR view and state transitions.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"number":9,"title":"PR","state":"open","user":{"login":"alice"},"head":{"ref":"feature"},"base":{"ref":"main"}}'
EOF
    out="$("$FGH" pr view 9 --json number,title)"
    assert_eq "pr view title" "PR" "$(jq -r .title <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"number":9,"title":"PR","state":"closed"}'
EOF
    "$FGH" pr close 9 >/dev/null
    assert_eq "pr close payload" "closed" "$(Log_body 1 | jq -r .state)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"number":9,"title":"PR","state":"open"}'
EOF
    "$FGH" pr open 9 >/dev/null
    assert_eq "pr open payload" "open" "$(Log_body 1 | jq -r .state)"

    # Actions view/jobs and run lifecycle.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */jobs) Serve 200 '[{"id":778,"name":"build","status":"success","attempt":1}]' ;;
  *) Serve 200 '{"id":123,"status":"success","title":"ci","prettyref":"main","commit_sha":"abcdef123456","trigger_user":{"login":"alice"}}' ;;
esac
EOF
    out="$("$FGH" actions view 123)"
    assert_contains "actions view run" "Run #123" "$out"
    assert_contains "actions view jobs" "build" "$out"
    assert_eq "actions view request count" "2" "$(Log_count)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":778,"name":"build","status":"success","runs_on":["linux"],"attempt":1}]'
EOF
    out="$("$FGH" actions jobs 123 --json id,name,status)"
    assert_eq "actions jobs name" "build" "$(jq -r '.[0].name' <<<"$out")"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    "$FGH" actions cancel 123 >/dev/null
    assert_method_call "actions cancel method" 1 POST

    reset_log
    "$FGH" actions delete 123 >/dev/null
    assert_method_call "actions delete method" 1 DELETE

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */actions/jobs/778/logs*) Serve 200 'complete log' ;;
  */actions/runs/123/jobs*) Serve 200 '[{"id":778,"status":"success"}]' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    out="$("$FGH" actions logs 123 --job 778 --follow --timeout 1)"
    assert_eq "followed job log" "complete log" "$out"
    assert_eq "follow requests log and status" "2" "$(Log_count)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":123,"status":"blocked","title":"ci"}'
EOF
    rc=0
    "$FGH" actions watch 123 --interval 0 >/dev/null 2>&1 || rc=$?
    assert_exit "blocked run exits nonzero" 1 "$rc"
}
