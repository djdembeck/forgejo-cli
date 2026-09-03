# tests/cases/05_actions_logs_watch.bash — run/job logs, watch, dispatch, tasks.

run() {
    FGH_REPO=acme/widgets
    local zip_b64 zip_path
    zip_b64="$(cat "$TESTS_DIR/fixtures/run_logs.zip.b64")"
    printf '%s' "$zip_b64" | base64 -d > "$TEST_TMP/run_logs.zip"

    # ── run logs: ZIP fetched from /runs/{id}/logs to a temp file (binary safe) ──
    cat > "$FAKE_CURL_SCRIPT" <<EOF
Serve_file 200 "$TEST_TMP/run_logs.zip"
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 2>/dev/null)"
    assert_contains "run logs unzip member header" "build-777-attempt-1.log" "$out"
    assert_contains "run logs unzip content" "build finished" "$out"
    assert_url_call "run logs hits runs/N/logs" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/runs/123/logs"

    # run logs must NOT hit the jobs path
    assert_not_contains "run logs never uses jobs path" "actions/jobs/" "$(Url_of 1)"

    # ── job logs: plaintext from /actions/jobs/{id}/logs ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/job_logs.txt")"
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 2>/dev/null)"
    assert_contains "job logs plaintext" "starting build" "$out"
    assert_url_call "job logs URL exact" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/778/logs"

    # --attempt goes as ?attempt=N query on the job URL only
    reset_log
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --attempt 2 2>/dev/null)"
    assert_url_contains "attempt query on job logs" "attempt=2" "$(Url_of 1)"
    assert_url_contains "attempt URL still job-scoped" "actions/jobs/778/logs" "$(Url_of 1)"

    # --follow without --job is a usage error (run archives are static)
    reset_log
    out="$(cd /tmp && "$FGH" actions logs 123 --follow 2>&1 >/dev/null)"
    assert_exit "logs --follow without --job exits 2" 2 "$?"
    assert_contains "follow usage error text" "--job" "$out"

    # ── watch: terminal statuses and exit codes, no real sleeping ──
    # success at first poll → exit 0
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":123,"status":"success","title":"ci on main"}'
EOF
    out="$(cd /tmp && interval="$(date +%s)" "$FGH" actions watch 123 --interval 0 2>/dev/null)"
    rc=$?
    assert_success "watch success exits 0" "$rc"
    assert_contains "watch success notice" "success" "$out"

    # failure → exit 1
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":123,"status":"failure","title":"ci on main"}'
EOF
    out="$(cd /tmp && "$FGH" actions watch 123 --interval 0 2>/dev/null)"
    assert_exit "watch failure exits 1" 1 "$?"

    # cancelled → exit 1 (not 2)
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":123,"status":"cancelled","title":"ci on main"}'
EOF
    out="$(cd /tmp && "$FGH" actions watch 123 --interval 0 2>/dev/null)"
    assert_exit "watch cancelled exits 1" 1 "$?"

    # skipped → exit 1
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":123,"status":"skipped","title":"ci on main"}'
EOF
    out="$(cd /tmp && "$FGH" actions watch 123 --interval 0 2>/dev/null)"
    assert_exit "watch skipped exits 1" 1 "$?"

    # in_progress then success: exactly two polls (Seq consumes in order)
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<EOF
Serve 200 '{"id":123,"status":"running","title":"ci"}'
EOF
    # two-entry queue: first call running, second success
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
calls=$(( $(cat "$FAKE_CURL_LOG" | wc -l) ))
if [ "$calls" -le 1 ]; then
  Serve 200 '{"id":123,"status":"running","title":"ci"}'
else
  Serve 200 '{"id":123,"status":"success","title":"ci"}'
fi
EOF
    rc=0
    out="$(cd /tmp && FORGEJO_FAKE_SLEEP=1 "$FGH" actions watch 123 2>/dev/null)" || rc=$?
    assert_success "watch running-then-success exits 0" "$rc"
    log_count="$(Log_count)"
    assert_eq "watch polled run endpoint twice" "2" "$log_count"

    # --timeout with a never-finishing run: nonzero, timeout message, no hang
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":123,"status":"running","title":"ci"}'
EOF
    out="$(cd /tmp && "$FGH" actions watch 123 --timeout 1 --interval 0 2>&1 >/dev/null)"
    rc=$?
    assert_contains "watch timeout reported" "timeout" "$out"

    # ── dispatch ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    out="$(cd /tmp && "$FGH" actions dispatch ci.yml --ref main --input verbose=true 2>/dev/null)"
    assert_contains "dispatch confirmation" "ci.yml" "$out"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "dispatch ref" "main" "$(printf '%s' "$payload" | jq -r .ref)"
    assert_eq "dispatch inputs object" '{"verbose":"true"}' "$(printf '%s' "$payload" | jq -c .inputs)"
    assert_url_call "dispatch URL exact" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/workflows/ci.yml/dispatches"
    assert_method_call "dispatch POST" 1 "POST"

    # ── tasks queue listing ({total_count, workflow_runs} envelope) ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"total_count":1,"workflow_runs":[{"id":130,"name":"queued build","status":"waiting","head_branch":"main","run_number":5}]}'
EOF
    out="$(cd /tmp && "$FGH" actions tasks --json 2>/dev/null)"
    assert_contains "tasks queue via --json" "queued build" "$out"
    assert_url_contains "tasks hits actions/tasks" "/actions/tasks?" "$(Url_of 1)"
}
