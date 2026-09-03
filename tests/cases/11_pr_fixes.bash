# tests/cases/11_pr_fixes.bash — regression coverage for the 8 PR-review fixes.
# shellcheck disable=SC2034  # FGH_REPO mirrors the other case files
# FIX 1  invalid jq quoting in 4 human-output filters (comment-attach,
#        pr review-comments, actions runner view/register)
# FIX 2  _follow_job_logs fail-fast when the jobs-status call fails
# FIX 3  -R/FGH_REPO slug validation (exactly owner/repo)
# FIX 4  release edit --draft/--prerelease reversible (clearing a draft)
# FIX 5  FORGEJO_URL missing → die() error, not bash unbound variable
# FIX 6  token never in curl argv; Authorization via -H @headerfile
# FIX 7  issue edit --body '' / --title '' transmitted; --milestone '' clears
# FIX 8  no predictable ${TMPDIR:-/tmp}/fgh-fatal.$$ marker outside a
#        0700 mktemp -d private dir; dir removed on exit
# G1/G4  actions logs --follow: no token in curl argv (last raw-curl site)
# G2     unknown command reported before any repo resolution
# G3     follow stream buffer created inside the private 0700 temp dir
# G5     actions watch fails fast on unknown run status
# G6     release edit usage documents --no-prerelease

run() {
    FGH_REPO=acme/widgets

    # ── FIX 1a: issue comment-attach human output (valid jq, prints URL) ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/attachment.json")"
EOF
    printf 'PNG' > "$TEST_TMP/ca.png"
    out="$(cd /tmp && "$FGH" issue comment-attach 42 "$TEST_TMP/ca.png" 2>/dev/null)"
    assert_contains "FIX1 comment-attach human renders name" "Attached screenshot.png (id 9)" "$out"
    assert_contains "FIX1 comment-attach human renders URL" "Embed URL: https://forgjo.test/attachments/9" "$out"

    # ── FIX 1b: pr review-comments human output ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":91,"body":"inline note","user":{"login":"rev"},"path":"a.go","position":4}]'
EOF
    out="$(cd /tmp && FGH_REPO=acme/widgets "$FGH" pr review-comments 9 90 2>/dev/null)"
    assert_contains "FIX1 review-comments human renders id+author" "#91 rev" "$out"
    assert_contains "FIX1 review-comments human renders path:pos" "a.go:4" "$out"
    assert_contains "FIX1 review-comments human renders body" "inline note" "$out"

    # ── FIX 1c: actions runner view human output ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":11,"name":"shell-1","status":"idle","labels":["linux"],"version":"6.0.0","description":"box"}'
EOF
    out="$(cd /tmp && FGH_REPO=acme/widgets "$FGH" actions runner view 11 2>/dev/null)"
    assert_contains "FIX1 runner view human header" "#11 shell-1 [idle]" "$out"
    assert_contains "FIX1 runner view human labels" "Labels: linux" "$out"
    assert_contains "FIX1 runner view human version" "Version: 6.0.0" "$out"
    assert_contains "FIX1 runner view human description" "Description: box" "$out"

    # ── FIX 1d: actions runner register human output ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 201 '{"id":12,"name":"shell-2","uuid":"uuid-12","token":"tok-12"}'
EOF
    out="$(cd /tmp && FGH_REPO=acme/widgets "$FGH" actions runner register --name shell-2 2>/dev/null)"
    assert_contains "FIX1 runner register human header" "Registered runner #12 shell-2" "$out"
    assert_contains "FIX1 runner register human uuid" "UUID: uuid-12" "$out"
    assert_contains "FIX1 runner register human token" "Token: tok-12" "$out"

    # ── FIX 2: --follow must fail fast (nonzero, bounded) when the jobs
    #    status endpoint errors, not spin until an unrelated timeout ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<EOF
case "\$_url" in
  */jobs/778/logs*) Serve 200 "log line" ;;
  *) Serve 500 '{"message":"jobs backend down"}' ;;
esac
EOF
    out="$(cd /tmp && timeout 15 "$FGH" actions logs 123 --job 778 --follow --timeout 5 2>&1 >/dev/null)"; rc=$?
    assert_exit "FIX2 follow exits nonzero on jobs status failure" 1 "$rc"
    assert_contains "FIX2 follow reports status failure" "could not determine status of job #778" "$out"
    # ── FIX 3: malformed -R/--repo and FGH_REPO are usage errors ──
    reset_log
    for bad in owner a/b/c /x a/ "a//b"; do
        out="$(cd /tmp && "$FGH" -R "$bad" repo view 2>&1 >/dev/null)"; rc=$?
        assert_exit "FIX3 -R '$bad' exits 2" 2 "$rc"
        assert_contains "FIX3 -R '$bad' message" "invalid repository '$bad'" "$out"
        assert_not_contains "FIX3 -R '$bad' builds no URL" "forgejo.test" "$(Url_of 1)"
    done
    reset_log
    for bad in owner a/b/c /x a/; do
        out="$(cd /tmp && FGH_REPO="$bad" "$FGH" repo view 2>&1 >/dev/null)"; rc=$?
        assert_exit "FIX3 FGH_REPO='$bad' exits 2" 2 "$rc"
        assert_contains "FIX3 FGH_REPO='$bad' message" "invalid repository '$bad'" "$out"
    done
    reset_log
    out="$(cd /tmp && FGH_REPO=ok/slug "$FGH" repo view 2>/dev/null)"
    assert_url_call "FIX3 valid slug still resolves" 1 "https://forgejo.test/api/v1/repos/ok/slug"

    # ── FIX 4: release edit can clear --draft / --prerelease ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":22,"tag_name":"v1.0","name":"v1.0","draft":false,"prerelease":false}'
EOF
    "$FGH" release edit 22 --draft=false --no-prerelease >/dev/null 2>&1
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "FIX4 --draft=false transmitted" "false" "$(printf '%s' "$payload" | jq -r .draft)"
    assert_eq "FIX4 --no-prerelease transmitted" "false" "$(printf '%s' "$payload" | jq -r .prerelease)"
    # promote a draft: both flags in one call
    reset_log
    "$FGH" release edit 22 --no-draft --prerelease=true >/dev/null 2>&1
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "FIX4 --no-draft transmitted" "false" "$(printf '%s' "$payload" | jq -r .draft)"
    assert_eq "FIX4 --prerelease=true transmitted" "true" "$(printf '%s' "$payload" | jq -r .prerelease)"
    # bare --draft still sets true
    reset_log
    "$FGH" release edit 22 --draft --prerelease >/dev/null 2>&1
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "FIX4 bare --draft still true" "true" "$(printf '%s' "$payload" | jq -r .draft)"
    assert_eq "FIX4 bare --prerelease still true" "true" "$(printf '%s' "$payload" | jq -r .prerelease)"
    # no flag → no lifecycle key in payload
    reset_log
    "$FGH" release edit 22 --title renamed >/dev/null 2>&1
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "FIX4 no draft key without flag" "null" "$(printf '%s' "$payload" | jq -r '.draft // null')"
    assert_eq "FIX4 no prerelease key without flag" "null" "$(printf '%s' "$payload" | jq -r '.prerelease // null')"

    # ── FIX 5: unset/nonempty FORGEJO_URL → actionable die(), offline cmds work ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"version":"16.0.3"}'
EOF
    out="$(cd /tmp && env -u FORGEJO_URL "$FGH" repo view 2>&1 >/dev/null)"; rc=$?
    assert_exit "FIX5 missing FORGEJO_URL exits 1" 1 "$rc"
    assert_contains "FIX5 missing FORGEJO_URL message" "FORGEJO_URL is not set" "$out"
    assert_not_contains "FIX5 no unbound-variable leak" "unbound variable" "$out"
    reset_log
    out="$(cd /tmp && env FORGEJO_URL= "$FGH" repo view 2>&1 >/dev/null)"; rc=$?
    assert_exit "FIX5 empty FORGEJO_URL exits 1" 1 "$rc"
    assert_contains "FIX5 empty FORGEJO_URL message" "FORGEJO_URL is not set" "$out"
    # offline commands unaffected
    reset_log
    out="$(cd /tmp && env -u FORGEJO_URL "$FGH" version 2>/dev/null)"; rc=$?
    assert_success "FIX5 version works offline" "$rc"
    assert_contains "FIX5 version output intact" "fgh 2.0.0" "$out"
    out="$(cd /tmp && env -u FORGEJO_URL "$FGH" --help 2>/dev/null)"; rc=$?
    assert_success "FIX5 help works offline" "$rc"
    assert_contains "FIX5 help output intact" "Usage: fgh" "$out"

    # ── FIX 6: token never in curl argv; header file carries it ──
    reset_log
    out="$(cd /tmp && FORGEJO_ISSUE_TOKEN=issue-tok FORGEJO_TOKEN=repo-tok "$FGH" issue list 2>/dev/null)"
    assert_auth_token "FIX6 header carries issue token" 1 "issue-tok"
    argv="$(Log_line 1)"
    assert_not_contains "FIX6 argv omits Authorization" "Authorization" "$argv"
    assert_not_contains "FIX6 argv omits token" "issue-tok" "$argv"
    # raw api + multipart + artifact download paths too
    reset_log
    "$FGH" api version >/dev/null 2>&1
    assert_auth_token "FIX6 raw api header carries token" 1 "test-repo-token"
    assert_not_contains "FIX6 raw api argv omits token" "test-repo-token" "$(Log_line 1)"

    reset_log
    printf 'ZIPDATA' > "$TEST_TMP/dl.zip"
    "$FGH" release upload 22 "$TEST_TMP/dl.zip" >/dev/null 2>&1
    assert_auth_token "FIX6 multipart header carries token" 1 "test-repo-token"
    assert_not_contains "FIX6 multipart argv omits token" "test-repo-token" "$(Log_line 1)"

    reset_log
    "$FGH" actions artifact download 55 "$TEST_TMP/dl.zip" >/dev/null 2>&1
    assert_auth_token "FIX6 artifact download header carries token" 1 "test-repo-token"
    assert_not_contains "FIX6 artifact argv omits token" "test-repo-token" "$(Log_line 1)"

    # ── FIX 7: empty values are transmitted, presence beats emptiness ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"number":5,"title":"t","state":"open"}'
EOF
    "$FGH" issue edit 5 --body '' >/dev/null 2>&1
    rc=$?
    assert_success "FIX7 empty body accepted" "$rc"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "FIX7 empty body transmitted" '""' "$(printf '%s' "$payload" | jq -r '.body | @json')"
    assert_eq "FIX7 title not injected by empty body" "null" "$(printf '%s' "$payload" | jq -r '.title // null')"

    reset_log
    "$FGH" issue edit 5 --title '' >/dev/null 2>&1
    rc=$?
    assert_success "FIX7 empty title accepted" "$rc"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "FIX7 empty title transmitted" '""' "$(printf '%s' "$payload" | jq -r '.title | @json')"

    reset_log
    "$FGH" issue edit 5 --milestone '' >/dev/null 2>&1
    rc=$?
    assert_success "FIX7 empty milestone accepted" "$rc"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_contains "FIX7 milestone-clearing null transmitted" '"milestone":null' "$payload"
    # numeric milestone keeps working
    reset_log
    "$FGH" issue edit 5 --milestone 3 >/dev/null 2>&1
    assert_eq "FIX7 numeric milestone unchanged" "3" "$(Log_body 1 | jq -r .milestone)"

    # ── FIX 8: no predictable fatal marker; private temp dir cleaned up ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 404 '{"message":"missing"}'
EOF
    # Isolate from other concurrent fgh processes: run each probe with a
    # dedicated TMPDIR so the directory census below only sees our process.
    FIX8_TMP="$(mktemp -d)"
    before=0
    for d in "$FIX8_TMP"/fgh-fatal.*; do [[ -e "$d" ]] && before=$(( before + 1 )); done
    out="$(cd /tmp && TMPDIR="$FIX8_TMP" "$FGH" issue view 999 2>/dev/null)"; rc=$?
    assert_exit "FIX8 failing command exits 1" 1 "$rc"
    after=0
    for d in "$FIX8_TMP"/fgh-fatal.*; do [[ -e "$d" ]] && after=$(( after + 1 )); done
    assert_eq "FIX8 no fgh-fatal.* marker created" "$before" "$after"
    # no leftover private dirs from this run: mktemp -d template fgh.XXXXXX
    # (count via glob expansion — `ls -d` with no matches lists ".")
    left=0; lnames=""
    for d in "$FIX8_TMP"/fgh.??????; do [[ -d "$d" ]] && left=$(( left + 1 )) && lnames="$lnames $d"; done
    assert_eq "FIX8 private temp dir removed on exit (dirs:$lnames)" "0" "$left"
    # usage-die path cleans up too
    out="$(cd /tmp && TMPDIR="$FIX8_TMP" "$FGH" -R bogus repo view 2>/dev/null)"; rc=$?
    assert_exit "FIX8 usage-die exits 2" 2 "$rc"
    left=0; lnames=""
    for d in "$FIX8_TMP"/fgh.??????; do [[ -d "$d" ]] && left=$(( left + 1 )) && lnames="$lnames $d"; done
    assert_eq "FIX8 private temp dir removed after usage-die (dirs:$lnames)" "0" "$left"
    rm -rf "$FIX8_TMP"

    # ── G1/G4 (FIX 6 gap): actions logs --follow must keep the token out of
    #    curl argv too — this was the last raw-curl site using an inline
    #    "Authorization: token ..." header. The follow request's header side
    #    log carries the token; the argv log must contain neither the
    #    Authorization header nor the token string.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<EOF
case "\$_url" in
  */jobs/779/logs*) Serve 200 "followed log line" ;;
  *) Serve 200 '[{"id":779,"status":"success"}]' ;;
esac
EOF
    out="$(cd /tmp && FORGEJO_TOKEN=repo-tok timeout 15 "$FGH" actions logs 124 --job 779 --follow --timeout 5 >/dev/null 2>&1)"; rc=$?
    assert_success "G1 follow run completes" "$rc"
    follow_call=0
    for ((k=1; k<=$(Log_count); k++)); do
        case "$(Url_of "$k")" in */actions/jobs/779/logs*) follow_call=$k ;; esac
    done
    assert_contains "G1 follow requests the logs endpoint" "/actions/jobs/779/logs" "$(Url_of "$follow_call")"
    assert_auth_token "G1 header side log carries token" "$follow_call" "repo-tok"
    argv="$(Log_line "$follow_call")"
    assert_not_contains "G1 follow argv omits Authorization" "Authorization" "$argv"
    assert_not_contains "G1 follow argv omits token" "repo-tok" "$argv"

    # ── G3: the streamed log buffer must be created inside the private 0700
    #    temp dir, never as a regular file directly under ${TMPDIR:-/tmp}.
    #    The buffer is rm'd on every exit branch, so a post-run census cannot
    #    distinguish the bug from the fix: the fake curl script takes the
    #    census DURING the follow loop instead (per-probe TMPDIR isolates it
    #    from concurrent fgh processes — FIX 8 approach). With the fix, the
    #    only fgh.* entry under the probe TMPDIR is the private directory;
    #    with the bug there is also a regular fgh.XXXXXX file.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<EOF
case "\$_url" in
  */jobs/781/logs*)
    _c=0
    for _f in "\$G3_TMPDIR"/fgh.*; do [ -f "\$_f" ] && _c=\$((_c+1)); done
    echo "\$_c" >> "\$G3_CENSUS"
    Serve 200 "census probe log" ;;
  *) Serve 200 '[{"id":781,"status":"running"}]' ;;
esac
EOF
    G3_TMP="$(mktemp -d)" && G3_CENSUS="$(mktemp)"
    out="$(cd /tmp && TMPDIR="$G3_TMP" G3_TMPDIR="$G3_TMP" G3_CENSUS="$G3_CENSUS" timeout 20 "$FGH" actions logs 126 --job 781 --follow --timeout 5 >/dev/null 2>&1)"; rc=$?
    assert_exit "G3 follow run bounded (times out on never-ending run)" 1 "$rc"
    assert_contains "G3 follow loop actually polled logs" "/actions/jobs/781/logs" "$(Url_of 1)"
    assert_contains "G3 census ran during the follow loop" "0" "$(head -n 1 "$G3_CENSUS")"
    assert_eq "G3 no fgh.* regular file directly under TMPDIR during follow" "0" "$(grep -vc '^0$' "$G3_CENSUS" || true)"
    # cleanup rode the EXIT trap: private dir (and its stream buffer) gone
    left=0
    for d in "$G3_TMP"/fgh.??????; do [[ -e "$d" ]] && left=$(( left + 1 )); done
    assert_eq "G3 private temp dir removed after follow (dirs:$left)" "0" "$left"
    rm -rf "$G3_TMP" "$G3_CENSUS"

    # ── A2b: issue edit --label must surface API failures, not print
    #    'Labels updated' and exit 0. The label block runs inside an if
    #    where set -e cannot abort a failing $(api_get)/api_send, so every
    #    API call there needs a check_fatal before its result is used.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */issues/5/labels) Serve 500 '{"message":"labels backend down"}' ;;
  *) Serve 404 '{"message":"unexpected call"}' ;;
esac
EOF
    out="$(cd /tmp && FGH_REPO=acme/widgets "$FGH" issue edit 5 --label bug 2>&1 >/dev/null)"; rc=$?
    assert_exit "A2b label GET failure exits nonzero" 1 "$rc"
    assert_contains "A2b label GET failure reported" "HTTP 500" "$out"
    assert_not_contains "A2b no success echo on GET failure" "Labels updated" "$out"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */issues/5/labels)
    if [ -f "$FAKE_CURL_LOG" ] && [ "$(grep -c '' "$FAKE_CURL_LOG")" -ge 2 ]; then
      Serve 500 '{"message":"labels write failed"}'
    else
      Serve 200 "$(cat "$TESTS_DIR/fixtures/labels.json")"
    fi ;;
  */labels?limit=*) Serve 200 "$(cat "$TESTS_DIR/fixtures/labels.json")" ;;
  *) Serve 404 '{"message":"unexpected call"}' ;;
esac
EOF
    out="$(cd /tmp && FGH_REPO=acme/widgets "$FGH" issue edit 5 --label bug 2>&1 >/dev/null)"; rc=$?
    assert_exit "A2b label PUT failure exits nonzero" 1 "$rc"
    assert_contains "A2b label PUT failure reported" "HTTP 500" "$out"
    assert_not_contains "A2b no success echo on PUT failure" "Labels updated" "$out"

    # happy path still intact: existing label resolves, PUT sends id 3
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */issues/5/labels)
    if [ "$(grep -c '' "$FAKE_CURL_LOG")" -ge 2 ]; then
      Serve 200 '[{"id":3,"name":"bug"},{"id":4,"name":"enhancement"}]'
    else
      Serve 200 "$(cat "$TESTS_DIR/fixtures/labels.json")"
    fi ;;
  */labels?limit=*) Serve 200 "$(cat "$TESTS_DIR/fixtures/labels.json")" ;;
  *) Serve 404 '{"message":"unexpected call"}' ;;
esac
EOF
    "$FGH" issue edit 5 --label bug >/dev/null 2>&1
    assert_success "A2b label happy path succeeds" "$?"
    assert_contains "A2b label happy path PUT sends resolved id" '"labels":[3' "$(Log_body 3 | jq -c .)"

    # ── G2: unknown command reports 'Unknown command: X' + help regardless
    #    of repo availability; known commands keep the repo-resolution error.
    reset_log
    out="$(cd /tmp && env -u FGH_REPO "$FGH" bogus 2>&1 >/dev/null)"; rc=$?
    assert_exit "G2 unknown command with no repo exits 1" 1 "$rc"
    assert_contains "G2 unknown command names the command" "Unknown command: bogus" "$out"
    assert_contains "G2 unknown command shows help" "Usage: fgh" "$out"
    assert_not_contains "G2 unknown command not swallowed by repo error" "no repository" "$out"
    # known command with no repo still fails with the repo resolution error
    reset_log
    out="$(cd /tmp && env -u FGH_REPO "$FGH" issue list 2>&1 >/dev/null)"; rc=$?
    assert_exit "G2 known command with no repo exits 1" 1 "$rc"
    assert_contains "G2 known command repo error unchanged" "no repository: set FGH_REPO=owner/repo" "$out"

    # ── G5: actions watch fails fast (bounded, nonzero) on an unrecognized
    #    status instead of polling until --timeout.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":"125","status":"weird-status","title":"mystery"}'
EOF
    out="$(cd /tmp && timeout 15 "$FGH" actions watch 125 --timeout 10 2>&1 >/dev/null)"; rc=$?
    assert_exit "G5 watch unknown status exits nonzero" 1 "$rc"
    assert_contains "G5 watch names the unknown status" 'unknown run status "weird-status" for run 125' "$out"
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":"126","status":"success","title":"ok"}'
EOF
    out="$(cd /tmp && "$FGH" actions watch 126 2>&1 >/dev/null)"; rc=$?
    assert_success "G5 watch terminal statuses still work" "$rc"
    assert_contains "G5 watch success output intact" "Run #126: success" "$out"

    # ── G6: release edit usage documents the --no-prerelease form. Full
    #    release_usage() fires on an unknown release subcommand.
    out="$("$FGH" release not-a-subcommand 2>&1 >/dev/null)"; rc=$?
    assert_exit "G6 unknown release subcommand is a usage error" 2 "$rc"
    assert_contains "G6 release usage documents --no-prerelease" "--no-prerelease" "$out"
    assert_contains "G6 release usage documents --prerelease form" "--prerelease [true|false] | --no-prerelease" "$out"
}
