#!/usr/bin/env bash
# Rerun API support is gated to Forgejo 17+ and deliberately write-only.

run() {
    local out err rc base="https://forgejo.test/api/v1/repos/acme/widgets"

    # A bare REST ID is rerun directly: bodyless POST, exactly 204, confirmation.
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  */actions/runs/4242/rerun) Serve 204 '' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
    out="$("$FGH" actions rerun 4242 2>/dev/null)"; rc=$?
    assert_exit "bare run rerun succeeds" 0 "$rc"
    assert_contains "rerun confirms REST run ID" "4242" "$out"
    assert_eq "version probe then mutation only" 2 "$(Log_count)"
    assert_url_call "version endpoint" 1 "https://forgejo.test/api/v1/version"
    assert_method_call "run rerun POST" 2 POST
    assert_url_call "run rerun exact endpoint" 2 "$base/actions/runs/4242/rerun"
    assert_empty "run rerun request has no body" "$(Log_body 2)"

    # UI run-number and run:N resolve a potentially different REST database ID.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"17.1.0"}' ;;
  *run_number=12*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":9876,"index_in_repo":12}]}' ;;
  */actions/runs/9876/rerun) Serve 204 '' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
    out="$("$FGH" actions rerun --run-number 12 2>/dev/null)"; rc=$?
    assert_exit "run-number rerun succeeds" 0 "$rc"
    assert_contains "run-number confirmation names resolved ID" "9876" "$out"
    assert_url_call "run-number uses REST rerun endpoint" 3 "$base/actions/runs/9876/rerun"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  *run_number=12*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":9876,"index_in_repo":12}]}' ;;
  */actions/runs/9876/rerun) Serve 204 '' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
    out="$("$FGH" actions rerun run:12 2>/dev/null)"; rc=$?
    assert_exit "run:N rerun succeeds" 0 "$rc"
    assert_url_call "run:N uses resolved REST endpoint" 3 "$base/actions/runs/9876/rerun"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  *run_number=12*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":9876,"index_in_repo":12}]}' ;;
  */actions/runs/9876/rerun) Serve 204 '' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
    out="$(env -u FGH_REPO "$FGH" actions rerun 'https://forgejo.test/acme/widgets/actions/runs/12' 2>/dev/null)"; rc=$?
    assert_exit "full run URL rerun succeeds" 0 "$rc"
    assert_url_call "full run URL uses resolved REST endpoint" 3 "$base/actions/runs/9876/rerun"

    # Full UI job URL maps its zero-based job position through ID-sorted jobs.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  *run_number=12*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":9876,"index_in_repo":12}]}' ;;
  */runs/9876/jobs*) Serve 200 '[{"id":4243},{"id":4242}]' ;;
  */actions/jobs/4243/rerun) Serve 204 '' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
    out="$(env -u FGH_REPO "$FGH" actions rerun 'https://forgejo.test/acme/widgets/actions/runs/12/jobs/1/attempt/2' 2>/dev/null)"; rc=$?
    assert_exit "full job URL rerun succeeds" 0 "$rc"
    assert_url_call "job URL resolves sorted index" 4 "$base/actions/jobs/4243/rerun"
    assert_contains "job URL confirmation names job ID" "4243" "$out"

    # A full job URL already selects a job; explicit job selectors conflict
    # and must be rejected before probing the server, with or without attempt.
    for url in \
        'https://forgejo.test/acme/widgets/actions/runs/12/jobs/1' \
        'https://forgejo.test/acme/widgets/actions/runs/12/jobs/1/attempt/2'; do
        for selector in '--job 4242' '--job-index 0'; do
            reset_log
            rc=0
            read -r -a argv <<< "$selector"
            env -u FGH_REPO "$FGH" actions rerun "$url" "${argv[@]}" >/dev/null 2>&1 || rc=$?
            assert_exit "job URL with $selector rejected by usage" 2 "$rc"
            assert_eq "job URL with $selector makes no requests" 0 "$(Log_count)"
        done
    done

    # Explicit REST job ID does not require a jobs listing; --job-index does.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  */actions/jobs/4242/rerun) Serve 204 '' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
    out="$("$FGH" actions rerun 123 --job 4242 2>/dev/null)"; rc=$?
    assert_exit "REST job rerun succeeds" 0 "$rc"
    assert_url_call "REST job endpoint selected without jobs list" 2 "$base/actions/jobs/4242/rerun"
    assert_eq "REST job rerun makes only probe and POST" 2 "$(Log_count)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  */runs/123/jobs*) Serve 200 '[{"id":4243},{"id":4242}]' ;;
  */actions/jobs/4242/rerun) Serve 204 '' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
    out="$("$FGH" actions rerun 123 --job-index 0 2>/dev/null)"; rc=$?
    assert_exit "job-index rerun succeeds" 0 "$rc"
    assert_url_call "job-index resolves sorted REST job ID" 3 "$base/actions/jobs/4242/rerun"

    # Conflicting and malformed options fail before any request.
    for args in '12 --run-number 13' '12 --job 1 --job-index 0' '12 --attempt 2' '12 --job 0 --json' '12 --jq .id' '12 --unknown' '12 --job' '--run-number' '' 'not-an-id' '12 --job-index nope' '12 --limit 1'; do
        reset_log
        rc=0
        # Deliberately split a controlled option fixture as argv.
        read -r -a argv <<< "$args"
        "$FGH" actions rerun "${argv[@]}" >/dev/null 2>&1 || rc=$?
        assert_exit "invalid rerun args ($args) use usage status" 2 "$rc"
        assert_eq "invalid rerun args ($args) make no requests" 0 "$(Log_count)"
    done

    for flag in --json --jq; do
        reset_log
        rc=0
        "$FGH" actions rerun 12 "$flag" >/dev/null 2>&1 || rc=$?
        assert_exit "$flag rejected by rerun" 2 "$rc"
        assert_eq "$flag rejection makes no request" 0 "$(Log_count)"
    done

    # Every server error keeps its message and suppresses success confirmation,
    # for both run and job rerun resources.
    for code in 400 403 404; do
        for route in run job; do
            reset_log
            if [[ "$route" == run ]]; then endpoint="$base/actions/runs/4242/rerun"; selector='4242'; else endpoint="$base/actions/jobs/4242/rerun"; selector='4242 --job 4242'; fi
            cat > "$FAKE_CURL_SCRIPT" <<EOF
case "\$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  *"$endpoint") Serve $code '{"message":"server-${route}-${code}"}' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
            rc=0
            # selector contains controlled argv fragments and is intentionally split.
            # shellcheck disable=SC2086
            out="$("$FGH" actions rerun $selector 2>&1)" || rc=$?
            assert_exit "$route rerun HTTP $code fails" 1 "$rc"
            assert_contains "$route HTTP $code preserves server message" "server-${route}-${code}" "$out"
            assert_not_contains "$route HTTP $code has no confirmation" "Reran" "$out"
        done
    done

    # Version gate reports both required and detected versions without mutation.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */version) Serve 200 '{"version":"16.0.3"}' ;;
  *) Serve 204 '' ;;
esac
EOF
    rc=0; err="$("$FGH" actions rerun 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "pre-17 instance refused" 1 "$rc"
    assert_contains "version gate states Forgejo 17" "17" "$err"
    assert_contains "version gate reports detected version" "16.0.3" "$err"
    assert_eq "pre-17 gate makes no mutation" 1 "$(Log_count)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"version":"not-a-version"}'
EOF
    rc=0; err="$("$FGH" actions rerun 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "unparseable version refused" 1 "$rc"
    assert_eq "unparseable version makes no mutation" 1 "$(Log_count)"

    # Any unexpected 2xx (not 204) is an error, never a success confirmation.
    for code in 200 202; do
        reset_log
        cat > "$FAKE_CURL_SCRIPT" <<EOF
case "\$_url" in
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  */actions/runs/4242/rerun) Serve $code '{"message":"not complete"}' ;;
  *) Serve 404 '{"message":"unexpected request"}' ;;
esac
EOF
        rc=0; out="$("$FGH" actions rerun 4242 2>&1)" || rc=$?
        assert_exit "HTTP $code rerun is not accepted" 1 "$rc"
        assert_not_contains "HTTP $code has no confirmation" "Reran" "$out"
    done

    # Help is discoverable and describes the new command form.
    reset_log
    out="$("$FGH" actions rerun --help 2>&1)"; rc=$?
    assert_exit "rerun help succeeds" 0 "$rc"
    assert_contains "help lists rerun command" "rerun" "$out"
    assert_contains "help documents job selector" "--job" "$out"
    assert_eq "help makes no API calls" 0 "$(Log_count)"
}
