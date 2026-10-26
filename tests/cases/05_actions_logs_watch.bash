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

    # Forgejo 17 legitimately returns an empty body when a filter matches no
    # lines; preserve the legacy empty-log error for unfiltered job logs.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 ''
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 2>&1 >/dev/null)"
    assert_exit "unfiltered empty job log still fails" 1 "$?"
    assert_contains "unfiltered empty job log error preserved" "job #778 logs are empty" "$out"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
else
  Serve 200 ''
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --grep no-match 2>/dev/null)"
    assert_success "filtered empty job log succeeds" "$?"
    assert_empty "filtered empty job log prints no bytes" "$out"
    assert_url_call "filtered empty job log reaches endpoint" 2 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/778/logs?q=no-match"

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

    # Invalid combinations must be rejected with a usage error.
    # Each case is "flags|expected validation message": the flags are split into a
    # word array so every flag arrives as its own argument, and the message proves
    # the case reached fgh's validation logic — a combined string as one argument
    # would instead be rejected at argv parsing ("unknown argument" / "run
    # selector must be ..."). Flag-syntax cases never touch the network; cases
    # with a run selector (run number / run URL) resolve first, so their
    # job-requirement check follows exactly one run-lookup call. Both loops
    # resolve run number 5, so a lookup-successful fake server is armed; the
    # count distinguishes "used, then died" from "local rejection".
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/repos/acme/widgets/actions/runs?run_number=5\&page=1\&limit=2 ]]; then
  Serve 200 '{"workflow_runs":[{"id":123,"run_number":5}]}'
else
  Serve 404 '{}'
fi
EOF
    invalid_filter_cases=(
        "123 --ignore-case|--ignore-case requires --grep TEXT"
        "123 --step nope|--step must be a nonnegative integer"
        "123 --step|--step requires N"
        "123 --grep|--grep requires TEXT"
        "123 --ignore-case --grep text --follow|--grep and --ndjson cannot be used with --follow"
        "123 --ndjson --follow|--grep and --ndjson cannot be used with --follow"
        "https://forgejo.test/acme/widgets/actions/runs/5 --step 1|--step, --grep, and --ndjson require --job, --job-index, or a job UI URL"
        "https://forgejo.test/acme/widgets/actions/runs/5 --grep text|--step, --grep, and --ndjson require --job, --job-index, or a job UI URL"
        "https://forgejo.test/acme/widgets/actions/runs/5 --ignore-case|--ignore-case requires --grep TEXT"
        "https://forgejo.test/acme/widgets/actions/runs/5 --ndjson|--step, --grep, and --ndjson require --job, --job-index, or a job UI URL"
        "https://forgejo.test/acme/widgets/actions/runs/5 --step nope|--step must be a nonnegative integer"
        "https://forgejo.test/acme/widgets/actions/runs/5 --step|--step requires N"
        "https://forgejo.test/acme/widgets/actions/runs/5 --grep|--grep requires TEXT"
        "https://forgejo.test/acme/widgets/actions/runs/5 --ignore-case --grep text --follow|--grep and --ndjson cannot be used with --follow"
        "https://forgejo.test/acme/widgets/actions/runs/5 --ndjson --follow|--grep and --ndjson cannot be used with --follow"
        "--run-number 5 --step 1|--step, --grep, and --ndjson require --job, --job-index, or a job UI URL"
        "--run-number 5 --grep text|--step, --grep, and --ndjson require --job, --job-index, or a job UI URL"
        "--run-number 5 --ignore-case|--ignore-case requires --grep TEXT"
        "--run-number 5 --ndjson|--step, --grep, and --ndjson require --job, --job-index, or a job UI URL"
        "--run-number 5 --step nope|--step must be a nonnegative integer"
        "--run-number 5 --step|--step requires N"
        "--run-number 5 --grep|--grep requires TEXT"
        "--run-number 5 --ignore-case --grep text --follow|--grep and --ndjson cannot be used with --follow"
        "--run-number 5 --ndjson --follow|--grep and --ndjson cannot be used with --follow"
    )
    for spec in "${invalid_filter_cases[@]}"; do
        expected_msg="${spec##*|}"; spec="${spec%%|*}"
        selector=()
        read -r -a selector <<<"$spec"
        reset_log
        out="$(cd /tmp && "$FGH" actions logs "${selector[@]}" 2>&1 >/dev/null)"
        rc=$?
        label="$(printf '%s' "${selector[*]}")"
        assert_exit "invalid filter usage exits 2: $label" 2 "$rc"
        assert_contains "flags parsed separately, not one string: $label" "$expected_msg" "$out"
        # Local rejections (bad flag value, bare REST ID with no job selector)
        # never touch the network. Run-URL / --run-number selectors with valid
        # flags resolve the run — one lookup call — before the job-requirement
        # check fires.
        if [[ ( "$spec" == https://* || "$spec" == "--run-number 5 "* ) && ( "$spec" == *"--step 1" || "$spec" == *"--grep text" || ( "$spec" == *"--ndjson" && "$spec" != *"--follow"* ) ) ]]; then
            assert_eq "invalid filter resolves run first: $label" "1" "$(Log_count)"
        else
            assert_eq "invalid filter has no HTTP calls: $label" "0" "$(Log_count)"
        fi
    done
    # UI URL loop: the proper UI job URL is the selector prefix, passed as its own
    # argument; each flag word arrives separately.
    ui_url_cases=(
        "--ignore-case|--ignore-case requires --grep TEXT"
        "--step nope|--step must be a nonnegative integer"
        "--step|--step requires N"
        "--ignore-case --grep text --follow|--grep and --ndjson cannot be used with --follow"
        "--ndjson --follow|--grep and --ndjson cannot be used with --follow"
        "--step -1|--step requires N"
        "--step 1x|--step must be a nonnegative integer"
        "--attempt nope|--attempt must be a positive integer"
        "--attempt 0|--attempt must be a positive integer"
        "--job nope|--job requires a REST job ID"
        "--job 0|job URL already selects a job"
        "--job-index nope|--job-index must be a nonnegative integer"
        "--job-index -1|--job-index requires a value"
        "--attempt 2 --job 778|job URL already selects a job"
        "--attempt 2 --job-index 0|job URL already selects a job"
        "--job 778 --job-index 0|use --job or --job-index, not both"
        "--attempt 2|URL attempt conflicts with --attempt"
    )
    for spec in "${ui_url_cases[@]}"; do
        expected_msg="${spec##*|}"; spec="${spec%%|*}"
        selector=()
        read -r -a selector <<<"$spec"
        reset_log
        out="$(cd /tmp && "$FGH" actions logs 'https://forgejo.test/acme/widgets/actions/runs/5/jobs/778/attempt/3' "${selector[@]}" --ndjson 2>&1 >/dev/null)"
        rc=$?
        label="$(printf '%s' "${selector[*]}")"
        assert_exit "UI URL filter usage exits 2: $label" 2 "$rc"
        assert_contains "UI URL flags parsed separately, not one string: $label" "$expected_msg" "$out"
        # URL-vs-flag conflicts are checked after _resolve_action_run_selector,
        # so those cases make one run-lookup call; local rejections make none.
        if [[ "$expected_msg" == *"job URL already selects"* || "$expected_msg" == *"URL attempt conflicts"* ]]; then
            expected_calls=1
        else
            expected_calls=0
        fi
        assert_eq "UI URL invalid filter HTTP calls: $label" "$expected_calls" "$(Log_count)"
    done

    # Empty argument must remain empty through the shell invocation.
    reset_log
    out="$(cd /tmp && "$FGH" actions logs run:5 --job 778 --step '' 2>&1 >/dev/null)"
    assert_exit "empty step value exits 2" 2 "$?"
    assert_eq "empty step value has no HTTP calls" "0" "$(Log_count)"

    run_selector_cases=("--job nope|--job requires a REST job ID" "--job-index nope|--job-index must be a nonnegative integer" "--job-index -1|--job-index requires a value" "--attempt 0|--attempt must be a positive integer" "--attempt nope|--attempt must be a positive integer")
    for spec in "${run_selector_cases[@]}"; do
        expected_msg="${spec##*|}"; spec="${spec%%|*}"
        selector=()
        read -r -a selector <<<"$spec"
        reset_log
        out="$(cd /tmp && "$FGH" actions logs run:5 "${selector[@]}" --grep text 2>&1 >/dev/null)"
        rc=$?
        label="$(printf '%s' "${selector[*]}")"
        assert_exit "run:N invalid job filter exits 2: $label" 2 "$rc"
        assert_contains "run:N invalid job filter message: $label" "$expected_msg" "$out"
        assert_eq "run:N invalid job filter has no HTTP calls: $label" "0" "$(Log_count)"
    done

    # Explicit --job/--job-index is mutually exclusive and rejected locally
    # (before resolution), even with a run selector present.
    reset_log
    out="$(cd /tmp && "$FGH" actions logs run:5 --job 778 --job-index 0 --grep text 2>&1 >/dev/null)"
    rc=$?
    assert_exit "run:N job and job-index conflict exits 2" 2 "$rc"
    assert_contains "run:N conflict message preserved" "use --job or --job-index, not both" "$out"
    assert_eq "run:N conflict has no HTTP calls" "0" "$(Log_count)"

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
        if [[ "$profile" == "old" ]]; then
            assert_contains "old server check names Forgejo 17" "Forgejo 17" "$out"
        elif [[ "$profile" == "malformed" ]]; then
            assert_contains "malformed version names cause" "server version unavailable or malformed" "$out"
            assert_not_contains "malformed version hides Forgejo 17 headline" "Forgejo 17" "$out"
        else
            assert_contains "probe failure names probe failure" "version probe failed: HTTP 500" "$out"
            assert_not_contains "probe failure hides Forgejo 17 headline" "Forgejo 17" "$out"
        fi
        assert_eq "${profile} only probes version" "1" "$(Log_count)"
    done

    # ── --grep accepts dash-prefixed and --grep=TEXT values ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
else
  Serve 200 'filtered logs'
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --grep --error 2>/dev/null)"
    assert_success "dash-prefixed grep value accepted" "$?"
    assert_url_contains "dash-prefixed grep reaches q" 2 "q=--error"

    reset_log
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --grep=--enable-fix 2>/dev/null)"
    assert_success "grep=TEXT form accepted" "$?"
    assert_url_contains "grep=TEXT reaches q" 2 "q=--enable-fix"

    # Transport failure (fake curl exits nonzero): the die message must name the
    # version-probe failure, not the Forgejo 17 headline.
    reset_log
    printf '#!/usr/bin/env bash\nexit 7\n' > "$FAKE_CURL_SCRIPT"
    out="$(cd /tmp && "$FGH" actions logs 123 --job 778 --grep text 2>&1)"
    rc=$?
    assert_exit "curl transport failure exits 1" 1 "$rc"
    assert_contains "transport failure names probe failure" "version probe failed:" "$out"
    assert_not_contains "transport failure hides Forgejo 17 headline" "Forgejo 17" "$out"

    # A job UI URL ending in /attempt/0 parses through _resolve_action_run_selector
    # instead of dying at the old pre-resolution grammar check.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
if [[ "$_url" == */api/v1/repos/acme/widgets/actions/runs?run_number=5\&page=1\&limit=2 ]]; then
  Serve 200 '{"workflow_runs":[{"id":123,"run_number":5}]}'
elif [[ "$_url" == */api/v1/repos/acme/widgets/actions/runs/123/jobs?page=1\&limit=50 ]]; then
  Serve 200 '[{"id":778}]'
elif [[ "$_url" == */api/v1/version ]]; then
  Serve 200 '{"version":"17.0.0"}'
else
  Serve 404 '{}'
fi
EOF
    out="$(cd /tmp && "$FGH" actions logs 'https://forgejo.test/acme/widgets/actions/runs/5/jobs/0/attempt/0' --step 0 2>&1)"
    rc=$?
    # The URL now parses through _resolve_action_run_selector (job 0, attempt 0);
    # the old pre-resolution grammar used to die "invalid Actions job UI URL".
    # Consistent with the resolver: the URL-supplied attempt 0 reaches the
    # existing positive-integer gate instead.
    assert_not_contains "attempt/0 no longer reports invalid job URL" "invalid Actions job UI URL" "$out"
    assert_exit "attempt/0 URL attempt rejected by existing gate" 2 "$rc"
    assert_contains "attempt/0 URL attempt named as non-positive" "--attempt must be a positive integer" "$out"

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
