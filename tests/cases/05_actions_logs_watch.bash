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

    # ── filtered job logs: Forgejo 17 gate and query contract ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
else
  Serve 200 'filtered logs'
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --step 0 2>/dev/null)"
    assert_success "step zero accepted" "$?"
    assert_eq "version probe plus step request" "2" "$(Log_count)"
    assert_url_contains "step zero query" 2 "?step=0"

    reset_log
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --grep 'a b+c#?雪' 2>/dev/null)"
    assert_success "substring filter succeeds" "$?"
    assert_url_contains "grep substring URL encoded" 2 "q=a%20b%2Bc%23%3F%E9%9B%AA"

    reset_log
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --grep '' 2>/dev/null)"
    assert_success "explicit empty grep accepted" "$?"
    assert_url_contains "empty grep sent as q empty" 2 "?q="

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
else
  Serve 200 'filtered logs'
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --attempt 2 --step 0 --grep 'a b+c#?雪' --ignore-case --ndjson 2>/dev/null)"
    assert_success "combined filters succeed" "$?"
    assert_url_call "combined filter query order" 2 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/778/logs?attempt=2&step=0&q=a%20b%2Bc%23%3F%E9%9B%AA&qi=true&format=ndjson"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
else
  Serve 200 ' {"time":"2026-01-02T03:04:05Z","content":"line one"}
{"time":"2026-01-02T03:04:06Z","content":"line two"}  
'
fi
EOF
    (cd /tmp && "$FGH" actions logs 123 --job 778 --ndjson > "$TEST_TMP/ndjson.out" 2>/dev/null)
    rc=$?
    assert_success "NDJSON request succeeds" "$rc"
    printf ' {"time":"2026-01-02T03:04:05Z","content":"line one"}\n{"time":"2026-01-02T03:04:06Z","content":"line two"}  \n' > "$TEST_TMP/ndjson.expected"
    cmp -s "$TEST_TMP/ndjson.expected" "$TEST_TMP/ndjson.out"
    assert_exit "NDJSON preserves raw bytes and trailing newline" 0 "$?"
    assert_url_contains "NDJSON format query" 2 "?format=ndjson"

    # A valid job UI URL resolves the UI index through the run's sorted jobs list.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/repos/acme/widgets/actions/runs?run_number=5\&page=1\&limit=2 ]]; then
  Serve 200 '{"workflow_runs":[{"id":123,"run_number":5}]}'
elif [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
elif [[ "$_url" == */api/v1/repos/acme/widgets/actions/runs/123/jobs?page=1\&limit=50 ]]; then
  Serve 200 '[{"id":779},{"id":778}]'
elif [[ "$_url" == */actions/jobs/778/logs* ]]; then
  Serve 200 'filtered logs'
else
  Serve 404 '{}'
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 'https://forgejo.test/acme/widgets/actions/runs/5/jobs/0/attempt/3' --step 4 2>/dev/null)"
    assert_success "UI job URL filtered request succeeds" "$?"
    assert_url_call "UI job resolver lookup, list, version, logs" 4 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/778/logs?attempt=3&step=4"

    # A run UI URL remains usable when an explicit job selector supplies the job.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */actions/runs?run_number=5\&page=1\&limit=2 ]]; then
  Serve 200 '{"workflow_runs":[{"id":123,"run_number":5}]}'
elif [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
elif [[ "$_url" == */actions/runs/123/jobs?page=1\&limit=50 ]]; then
  Serve 200 '[{"id":778}]'
else
  Serve 200 'filtered logs'
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 'https://forgejo.test/acme/widgets/actions/runs/5' --job 778 --step 5 2>/dev/null)"
    assert_success "run UI URL with explicit job succeeds" "$?"
    assert_url_call "run UI URL explicit job log query" 3 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/778/logs?step=5"

    reset_log
    out="$(cd /tmp && "$FGH" actions logs 'https://forgejo.test/acme/widgets/actions/runs/5' --job-index 0 --step 6 2>/dev/null)"
    assert_success "run UI URL with explicit job-index succeeds" "$?"
    assert_url_call "run UI URL explicit job-index log query" 4 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/778/logs?step=6"

    # Existing selector exclusivity applies with or without new filter flags.
    reset_log
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --job-index 0 2>&1 >/dev/null)"
    assert_exit "legacy job and job-index conflict exits 2" 2 "$?"
    assert_eq "legacy job and job-index conflict has no HTTP calls" "0" "$(Log_count)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
elif [[ "$_url" == */api/v1/repos/acme/widgets/actions/jobs/778/logs* ]]; then
  Serve 200 'followed logs'
elif [[ "$_url" == */api/v1/repos/acme/widgets/actions/runs/123/jobs ]]; then
  Serve 200 '[{"id":778,"status":"success"}]'
else
  Serve 404 '{}'
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --step 2 --follow 2>/dev/null)"
    assert_success "follow plus step succeeds" "$?"
    assert_url_call "follow plus step log request" 2 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/778/logs?step=2"
    assert_url_call "follow status checks parent run jobs" 3 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/runs/123/jobs"
    assert_contains "follow sends Range header" "Range: bytes=0-" "$(Log_headers 2)"

    # Local-only invalid combinations must be rejected before selector resolution/network.
    for selector in "123 --ignore-case" "123 --step nope" "123 --step" "123 --grep" "123 --ignore-case --grep text --follow" "123 --ndjson --follow"; do
        reset_log
        out="$(cd /tmp && "$FGH" actions logs "$selector" 2>&1 >/dev/null)"
        rc=$?
        assert_exit "invalid filter usage exits 2: $selector" 2 "$rc"
        assert_eq "invalid filter has no HTTP calls: $selector" "0" "$(Log_count)"
    done
    for selector in "https://forgejo.test/acme/widgets/actions/runs/5 --step 1" "https://forgejo.test/acme/widgets/actions/runs/5 --grep text" "https://forgejo.test/acme/widgets/actions/runs/5 --ignore-case" "https://forgejo.test/acme/widgets/actions/runs/5 --ndjson" "https://forgejo.test/acme/widgets/actions/runs/5 --step nope" "https://forgejo.test/acme/widgets/actions/runs/5 --step" "https://forgejo.test/acme/widgets/actions/runs/5 --grep" "https://forgejo.test/acme/widgets/actions/runs/5 --ignore-case --grep text --follow" "https://forgejo.test/acme/widgets/actions/runs/5 --ndjson --follow"; do
        reset_log
        out="$(cd /tmp && "$FGH" actions logs "$selector" 2>&1 >/dev/null)"
        rc=$?
        assert_exit "run selector filter usage exits 2: $selector" 2 "$rc"
        assert_eq "run selector invalid filter has no HTTP calls: $selector" "0" "$(Log_count)"
    done
    for selector in "--run-number 5 --step 1" "--run-number 5 --grep text" "--run-number 5 --ignore-case" "--run-number 5 --ndjson" "--run-number 5 --step nope" "--run-number 5 --step" "--run-number 5 --grep" "--run-number 5 --ignore-case --grep text --follow" "--run-number 5 --ndjson --follow"; do
        reset_log
        out="$(cd /tmp && "$FGH" actions logs "$selector" 2>&1 >/dev/null)"
        rc=$?
        assert_exit "run-number filter usage exits 2: $selector" 2 "$rc"
        assert_eq "run-number invalid filter has no HTTP calls: $selector" "0" "$(Log_count)"
    done
    for selector in "--ignore-case" "--step nope" "--step" "--grep" "--ignore-case --grep text --follow" "--ndjson --follow" "--step -1" "--step 1x" "--attempt nope" "--attempt 0" "--job nope" "--job 0" "--job-index nope" "--job-index -1" "--attempt 2 --job 778" "--attempt 2 --job-index 0" "--job 778 --job-index 0" "--attempt 2"; do
        reset_log
        out="$(cd /tmp && "$FGH" actions logs 'https://forgejo.test/acme/widgets/actions/runs/5/jobs/778/attempt/3' "$selector" --ndjson 2>&1 >/dev/null)"
        rc=$?
        assert_exit "UI URL filter usage exits 2: $selector" 2 "$rc"
        assert_eq "UI URL invalid filter has no HTTP calls: $selector" "0" "$(Log_count)"
    done

    # Empty argument must remain empty through the shell invocation.
    reset_log
    out="$(cd /tmp && "$FGH" actions logs run:5 --job 778 --step '' 2>&1 >/dev/null)"
    assert_exit "empty step value exits 2" 2 "$?"
    assert_eq "empty step value has no HTTP calls" "0" "$(Log_count)"

    # Explicit invalid job/index/attempt options on a run:N selector.
    for selector in "--job nope" "--job-index nope" "--job-index -1" "--attempt 0" "--attempt nope" "--job 778 --job-index 0"; do
        reset_log
        out="$(cd /tmp && "$FGH" actions logs run:5 "$selector" --grep text 2>&1 >/dev/null)"
        rc=$?
        assert_exit "run:N invalid job filter exits 2: $selector" 2 "$rc"
        assert_eq "run:N invalid job filter has no HTTP calls: $selector" "0" "$(Log_count)"
    done

    # Unsupported/unknown/malformed versions and probe failure fail closed.
    for profile in old malformed failure; do
        reset_log
        case "$profile" in
            old) cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then Serve 200 '{"version":"16.0.0"}'; else Serve 200 'must not fetch'; fi
EOF
                ;;
            malformed) cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then Serve 200 '{"version":"unknown"}'; else Serve 200 'must not fetch'; fi
EOF
                ;;
            failure) cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 500 'probe failed'
EOF
                ;;
        esac
        out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --grep text 2>&1)"
        rc=$?
        assert_exit "${profile} version blocks filters" 1 "$rc"
        assert_contains "${profile} error names Forgejo 17" "Forgejo 17" "$out"
        assert_eq "${profile} only probes version" "1" "$(Log_count)"
    done

    # Unfiltered logs and attempt remain compatible without version probes.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/job_logs.txt")"
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --attempt 2 2>/dev/null)"
    assert_contains "legacy attempt log output" "starting build" "$out"
    assert_eq "legacy attempt does not probe version" "1" "$(Log_count)"

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
