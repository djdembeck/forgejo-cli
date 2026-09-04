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
}
