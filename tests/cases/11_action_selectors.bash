#!/usr/bin/env bash
# Forgejo UI run/job URLs resolve to REST database identifiers.

run() {
    local run_url="https://forgejo.test/acme/widgets/actions/runs/157"
    local job_url="${run_url}/jobs/3/attempt/1"

    # Explicit UI run number resolves through the filtered list endpoint.
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"total_count":1,"workflow_runs":[{"id":3493,"index_in_repo":157,"status":"failure","title":"ci","html_url":"https://forgejo.test/acme/widgets/actions/runs/157"}]}'
EOF
    out="$("$FGH" actions view --run-number 157 --json id,run_number,status)"
    assert_eq "run number resolves REST id" "3493" "$(jq -r .id <<<"$out")"
    assert_eq "resolved run exposes run_number" "157" "$(jq -r .run_number <<<"$out")"
    assert_url_contains "run-number lookup query" 1 "run_number=157"

    # Full run URL is unambiguous and derives its repository from the URL.
    reset_log
    out="$(env -u FGH_REPO "$FGH" actions view "$run_url" --json id,run_number)"
    assert_eq "run URL resolves REST id" "3493" "$(jq -r .id <<<"$out")"
    assert_url_contains "run URL repository" 1 "/repos/acme/widgets/actions/runs?run_number=157"

    # Bare integers retain the historical REST-ID meaning.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":157,"index_in_repo":8,"status":"success","title":"old run"}'
EOF
    out="$("$FGH" actions view 157 --json id,index_in_repo)"
    assert_eq "bare run selector stays REST id" "157" "$(jq -r .id <<<"$out")"
    assert_url_call "bare run selector detail endpoint" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/runs/157"

    # Job index in the UI URL maps to the fourth id-sorted REST job.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  *run_number=157*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":3493,"index_in_repo":157,"status":"failure","title":"ci"}]}' ;;
  */runs/3493/jobs*) Serve 200 '[{"id":8542,"name":"fourth","status":"failure","attempt":1},{"id":8539,"name":"first","status":"success","attempt":1},{"id":8541,"name":"third","status":"failure","attempt":1},{"id":8540,"name":"second","status":"failure","attempt":1}]' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    out="$(env -u FGH_REPO "$FGH" actions jobs "$run_url" --json job_index,id,name)"
    assert_eq "jobs expose UI index" "3" "$(jq -r 'map(select(.id == 8542))[0].job_index' <<<"$out")"
    assert_eq "jobs are UI id order" "first" "$(jq -r '.[0].name' <<<"$out")"

    # Passing the complete job URL selects REST job 8542 and attempt 1.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  *run_number=157*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":3493,"index_in_repo":157,"status":"failure","title":"ci"}]}' ;;
  */runs/3493/jobs*) Serve 200 '[{"id":8539,"name":"first","status":"success","attempt":1},{"id":8540,"name":"second","status":"failure","attempt":1},{"id":8541,"name":"third","status":"failure","attempt":1},{"id":8542,"name":"fourth","status":"failure","attempt":1}]' ;;
  */actions/jobs/8542/logs?attempt=1) Serve 200 'selected job log' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    out="$(env -u FGH_REPO "$FGH" actions logs "$job_url")"
    assert_eq "job URL returns selected log" "selected job log" "$out"
    assert_url_call "job URL maps to REST log endpoint" 3 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/8542/logs?attempt=1"

    # A bad UI index is rejected instead of silently selecting job zero.
    reset_log
    bad_url="${run_url}/jobs/9/attempt/1"
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  *run_number=157*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":3493,"index_in_repo":157}]}' ;;
  */runs/3493/jobs*) Serve 200 '[{"id":8539},{"id":8540}]' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    rc=0
    err="$(env -u FGH_REPO "$FGH" actions logs "$bad_url" 2>&1 >/dev/null)" || rc=$?
    assert_exit "out-of-range job index fails" 1 "$rc"
    assert_contains "out-of-range job index explains count" "out of range" "$err"

    # Artifact run-number selectors also resolve before using the REST run ID.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  *run_number=157*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":3493,"index_in_repo":157}]}' ;;
  */runs/3493/artifacts*) Serve 200 '[]' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    "$FGH" actions artifact list --run-number 157 --json >/dev/null
    assert_url_contains "artifact selector uses REST run id" 2 "/runs/3493/artifacts"

    # Direct job view is one GET by REST ID, preserving the complete API object.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve_file 200 "$TESTS_DIR/fixtures/direct_job.json"
EOF
    out="$("$FGH" actions job view 4242)"
    assert_success "direct job view exits successfully" "$?"
    assert_url_call "direct job view exact endpoint" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/actions/jobs/4242"
    assert_method_call "direct job view uses GET" 1 GET
    assert_eq "direct job view issues one request" 1 "$(Log_count)"
    assert_not_contains "direct job view avoids run jobs" "actions/runs/" "$(cat "$FAKE_CURL_LOG")"
    assert_not_contains "direct job view avoids logs" "/logs" "$(cat "$FAKE_CURL_LOG")"
    assert_not_contains "direct job view avoids version probe" "/version" "$(cat "$FAKE_CURL_LOG")"
    for value in "Build and test" "4242" "812" "success" "2" "ubuntu-latest" "x64" "https://forgejo.test/acme/widgets/actions/runs/812/jobs/4242" "lint" "prepare"; do
        assert_contains "human output shows $value" "$value" "$out"
    done
    # The table follows numeric step order, not API order.
    header_line="$(grep -E 'NUMBER[[:space:]]+NAME[[:space:]]+STATUS[[:space:]]+STARTED[[:space:]]+STOPPED' <<<"$out" || true)"
    assert_eq "step table contains requested columns" true "$([[ -n "$header_line" ]] && echo true || echo false)"
    step_numbers="$(grep -E 'Set up job|Install|Test|Complete job' <<<"$out" | sed -E 's/^[[:space:]]*([0-9]+).*/\1/')"
    assert_eq "steps sorted and include setup/completion" $'0\n2\n3\n4' "$step_numbers"
    assert_not_contains "human output does not invent conclusion" "conclusion" "$out"
    assert_not_contains "human output does not invent runner identity" "Runner:" "$out"
    assert_not_contains "human output does not invent top-level times" "Started:" "$out"
    assert_not_contains "human output does not invent top-level times stopped" "Stopped:" "$out"

    reset_log
    out="$("$FGH" actions job view 4242 --json)"
    expected="$(jq -S . "$TESTS_DIR/fixtures/direct_job.json")"
    assert_eq "raw direct job JSON preserves API object" "$expected" "$(jq -S . <<<"$out")"
    for field in handle task_id html_url steps; do
        assert_eq "raw JSON retains $field" true "$(jq -e "has(\"$field\")" <<<"$out" >/dev/null && echo true)"
    done
    reset_log
    out="$("$FGH" actions job view 4242 --jq '.steps[].number')"
    assert_eq "jq projects step numbers" $'3\n0\n4\n2' "$out"
    reset_log
    out="$("$FGH" actions job view 4242 --json id,status,attempt)"
    assert_eq "field projection returns requested metadata" "$(jq -ncS '{id:4242,status:"success",attempt:2}')" "$(jq -cS . <<<"$out")"

    # No step array is a valid pre-runner state and has no empty table.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve_file 200 "$TESTS_DIR/fixtures/direct_job_no_steps.json"
EOF
    rc=0
    out="$("$FGH" actions job view 4300)" || rc=$?
    assert_contains "missing steps explains not picked up" "not been picked up by a runner" "$out"
    assert_not_contains "missing steps has no empty table" "NUMBER NAME STATUS STARTED STOPPED" "$out"
    assert_exit "missing steps succeeds" 0 "$rc"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":4300,"run_id":813,"name":"Queued build","status":"queued","attempt":1,"runs_on":["ubuntu-latest"],"steps":[]}'
EOF
    rc=0
    out="$("$FGH" actions job view 4300)" || rc=$?
    assert_contains "empty steps explains not picked up" "not been picked up by a runner" "$out"
    assert_not_contains "empty steps has no table" "NUMBER" "$out"
    assert_exit "empty steps succeeds" 0 "$rc"

    # 404 fallback distinguishes old servers, preserves errors, and never probes on other statuses.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */actions/jobs/4242) Serve 404 '{"message":"job endpoint not found"}' ;;
  */version) Serve 200 '{"version":"16.0.3"}' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    rc=0
    err="$("$FGH" actions job view 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "pre-v17 direct job lookup fails" 1 "$rc"
    assert_contains "pre-v17 error names required version" "Forgejo 17" "$err"
    assert_contains "pre-v17 error reports found version" "16.0.3" "$err"
    assert_eq "pre-v17 probes once after job 404" 2 "$(Log_count)"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */actions/jobs/4242) Serve 404 '{"message":"job endpoint not found"}' ;;
  */version) Serve 200 '{"version":"not-a-version"}' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    rc=0
    err="$("$FGH" actions job view 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "unparseable version probe preserves failure" 1 "$rc"
    assert_contains "unparseable probe preserves original error" "job endpoint not found" "$err"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */actions/jobs/4242) Serve 404 '{"message":"job endpoint not found"}' ;;
  */version) Serve 500 '{"message":"version probe failed"}' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    rc=0
    err="$("$FGH" actions job view 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "failed version probe preserves failure" 1 "$rc"
    assert_contains "failed probe preserves original job error" "job endpoint not found" "$err"

    # A transport failure during the probe must not hide or replace the job error.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */actions/jobs/4242) Serve 404 '{"message":"job endpoint not found"}' ;;
  */version) exit 7 ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    rc=0
    err="$("$FGH" actions job view 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "probe transport failure exits nonzero" 1 "$rc"
    assert_contains "probe transport failure preserves original error" "job endpoint not found" "$err"
    assert_not_contains "probe transport failure hides curl error" "curl failed" "$err"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */actions/jobs/4242) Serve 404 '{"message":"job endpoint not found"}' ;;
  */version) Serve 200 '{"version":"17.0.0"}' ;;
  *) Serve 404 '{"message":"unexpected"}' ;;
esac
EOF
    rc=0
    err="$("$FGH" actions job view 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "v17 direct job 404 remains failure" 1 "$rc"
    assert_contains "v17 direct job 404 preserves Forgejo error" "job endpoint not found" "$err"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 500 '{"message":"server exploded"}'
EOF
    rc=0
    err="$("$FGH" actions job view 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "non-404 direct job error fails" 1 "$rc"
    assert_contains "non-404 direct job error retained" "server exploded" "$err"
    assert_eq "non-404 response does not probe version" 1 "$(Log_count)"

    # Invalid selectors and argument shapes fail before making any requests.
    for args in 'abc' 'jobs/3' '-1' '' '4242 extra'; do
        reset_log
        rc=0
        # Intentional word splitting mirrors the CLI's positional invocation.
        err="$(# shellcheck disable=SC2086
            "$FGH" actions job view $args 2>&1 >/dev/null)" || rc=$?
        assert_exit "invalid direct job selector '$args' is usage error" 2 "$rc"
        assert_eq "invalid direct job selector '$args' makes no request" 0 "$(Log_count)"
    done

    # Invalid explicit repository fails before the direct job request.
    reset_log
    rc=0
    err="$("$FGH" -R invalid actions job view 4242 2>&1 >/dev/null)" || rc=$?
    assert_exit "invalid repository direct job lookup fails" 2 "$rc"
    assert_contains "invalid repository direct job lookup explains repository" "repository" "$err"
    assert_eq "invalid repository direct job lookup makes no request" 0 "$(Log_count)"
}