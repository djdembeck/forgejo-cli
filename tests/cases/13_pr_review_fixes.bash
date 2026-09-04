# shellcheck disable=SC2034  # FGH_REPO mirrors the other case files
# tests/cases/13_pr_review_fixes.bash — regression coverage for the PR #1
# review fixes (Mira 3926564314, 3926793386, 3926793392).
# PR1-F1   --limit on non-paginating commands is no longer silently
#          swallowed by the common-options pre-pass: the flag survives in
#          `rest` and the command's own parser rejects it (exit 2, zero
#          API calls). Paginating commands keep honoring --limit.
# PR1-F3   `actions view` renders jobs in REST-ID order: an out-of-order
#          jobs array from the API still shows UI index 0 for the smallest
#          .id, matching `actions jobs` and --job-index resolution.
# PR1-F4   _set_action_url_repo validates the URL-derived owner/repo slug
#          with validate_repo_slug before it is assigned to REPO_SLUG and
#          interpolated into request paths.

run() {
    FGH_REPO=acme/widgets

    # ── PR1-F1: --limit is stripped (into OPT_LIMIT) only on surfaces
    #    that paginate; everywhere else it must reach the command parser
    #    and die as an unknown argument — NOT be silently consumed.

    reset_log
    out="$(cd /tmp && "$FGH" issue edit 5 --limit 1 --title t 2>&1 >/dev/null)"; rc=$?
    assert_exit "F1 issue edit --limit exits 2" 2 "$rc"
    assert_contains "F1 issue edit names --limit" \
        "Usage: issue edit: unknown argument '--limit'" "$out"
    assert_eq "F1 issue edit makes no API call" "0" "$(Log_count)"

    reset_log
    out="$(cd /tmp && "$FGH" issue create --limit 1 2>&1 >/dev/null)"; rc=$?
    assert_exit "F1 issue create --limit exits 2" 2 "$rc"
    assert_contains "F1 issue create names --limit" \
        "Usage: issue create: unknown argument '--limit'" "$out"
    assert_eq "F1 issue create makes no API call" "0" "$(Log_count)"

    # A state-mutating command (_no_flags parser) is not paginating either,
    # so --limit must reach its parser and die as an unknown argument.
    reset_log
    out="$(cd /tmp && "$FGH" pr close 9 --limit 1 2>&1 >/dev/null)"; rc=$?
    assert_exit "F1 pr close --limit exits 2" 2 "$rc"
    assert_contains "F1 pr close names --limit" \
        "Usage: pr close: unknown argument '--limit'" "$out"
    assert_eq "F1 pr close makes no API call" "0" "$(Log_count)"

    # `pr review` is a MUTATION (single POST of the review payload) — its
    # parser has no --limit, so the pre-pass must not strip it. The review
    # LIST that paginates is the separate read command `pr review-comments`.
    reset_log
    out="$(cd /tmp && "$FGH" pr review 5 --approve --limit 1 2>&1 >/dev/null)"; rc=$?
    assert_exit "F1 pr review --limit exits 2" 2 "$rc"
    assert_contains "F1 pr review names --limit" \
        "Usage: pr review: unknown argument '--limit'" "$out"
    assert_eq "F1 pr review --limit makes no API call" "0" "$(Log_count)"

    # Without --limit the mutation still works end to end (single POST).
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":92,"state":"APPROVED"}'
EOF
    out="$(cd /tmp && "$FGH" pr review 5 --approve >/dev/null 2>&1)"; rc=$?
    assert_exit "F1 pr review (no --limit) succeeds" 0 "$rc"
    assert_method_call "F1 pr review posts the review" 1 POST
    assert_url_contains "F1 pr review targets /pulls/5/reviews" 1 "/pulls/5/reviews"
    assert_eq "F1 pr review posts the approval event" "APPROVED" "$(Log_body 1 | jq -r .event)"

    # A genuinely paginating command still honors --limit end to end.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"number":5,"title":"one"}]'
EOF
    out="$(cd /tmp && "$FGH" issue list --limit 1 --json number)"; rc=$?
    assert_exit "F1 issue list --limit succeeds" 0 "$rc"
    assert_eq "F1 issue list --limit returns the row" '[5]' "$(jq -c 'map(.number)' <<<"$out")"
    assert_url_contains "F1 issue list sends capped page" 1 "limit=1"

    # The paginating READ `pr review-comments` (no review id) walks
    # /pulls/N/reviews and MUST honor --limit: the reviews-list fetch is
    # capped and only review #90's comments are fetched even though the
    # fixture serves two reviews.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */pulls/9/reviews/90/comments*) Serve 200 '[{"id":910,"body":"c90","user":{"login":"r1"},"path":"a.go","position":2}]' ;;
  */pulls/9/reviews*) Serve 200 '[{"id":90,"user":{"login":"r1"},"state":"COMMENT"},{"id":91,"user":{"login":"r2"},"state":"APPROVED"}]' ;;
  *) Serve 200 '[]' ;;
esac
EOF
    out="$(cd /tmp && "$FGH" pr review-comments 9 --limit 1)"; rc=$?
    assert_exit "F1 review-comments --limit succeeds" 0 "$rc"
    assert_url_contains "F1 review list fetch is capped" 1 "limit=1"
    # Cap is observable: 1 reviews-list fetch + 1 comments fetch (review
    # #90 only) = exactly 2 calls; an uncapped run would also fetch #91's.
    assert_eq "F1 review limit caps the comments fetch" "2" "$(Log_count)"
    assert_url_contains "F1 only first review's comments fetched" 2 "/pulls/9/reviews/90/comments"

    # Nested-group boundary: within `actions`, the paginating `artifact
    # list` honors --limit while the non-paginating `secret set` rejects it.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/artifacts.json")"
EOF
    out="$(cd /tmp && "$FGH" actions artifact list --limit 1)"; rc=$?
    assert_exit "F1 artifact list --limit succeeds" 0 "$rc"
    assert_contains "F1 artifact list --limit renders row" "dist" "$out"
    # Cap is observable: the fixture has two artifacts, --limit 1 keeps only
    # the first (an uncapped run would render both).
    assert_not_contains "F1 artifact list cap drops second row" "coverage" "$out"
    assert_url_contains "F1 artifact list sends capped page" 1 "limit=1"

    reset_log
    out="$(cd /tmp && "$FGH" actions secret set MYSEC --body v1 --limit 1 2>&1 >/dev/null)"; rc=$?
    assert_exit "F1 secret set --limit exits 2" 2 "$rc"
    assert_contains "F1 secret set names --limit" \
        "Usage: actions secret set: unknown argument '--limit'" "$out"
    assert_eq "F1 secret set makes no API call" "0" "$(Log_count)"

    # attach-list PAGES via _paginate over /issues/N/assets, so it honors
    # --limit: the page fetch is capped (limit=2) and only the first 2 of the
    # 3 served attachments survive. (Regression: an earlier fix wrongly
    # dropped attach-list from _limit_supported, turning this into exit 2.)
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":1,"name":"alpha","size":10,"browser_download_url":"u"},{"id":2,"name":"beta","size":10,"browser_download_url":"u"},{"id":3,"name":"gamma","size":10,"browser_download_url":"u"}]'
EOF
    out="$(cd /tmp && "$FGH" issue attach-list 9 --limit 2 --json)"; rc=$?
    assert_exit "F1 issue attach-list --limit succeeds" 0 "$rc"
    assert_eq "F1 issue attach-list cap returns 2 rows" 2 "$(jq 'length' <<<"$out")"
    assert_contains "F1 issue attach-list keeps first name" "alpha" "$out"
    assert_contains "F1 issue attach-list keeps second name" "beta" "$out"
    assert_not_contains "F1 issue attach-list cap drops third name" "gamma" "$out"
    assert_url_contains "F1 issue attach-list sends capped page" 1 "limit=2"

    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"id":1,"name":"delta","size":10,"browser_download_url":"u"},{"id":2,"name":"epsilon","size":10,"browser_download_url":"u"},{"id":3,"name":"zeta","size":10,"browser_download_url":"u"}]'
EOF
    out="$(cd /tmp && "$FGH" pr attach-list 9 --limit 2 --json)"; rc=$?
    assert_exit "F1 pr attach-list --limit succeeds" 0 "$rc"
    assert_eq "F1 pr attach-list cap returns 2 rows" 2 "$(jq 'length' <<<"$out")"
    assert_contains "F1 pr attach-list keeps first name" "delta" "$out"
    assert_contains "F1 pr attach-list keeps second name" "epsilon" "$out"
    assert_not_contains "F1 pr attach-list cap drops third name" "zeta" "$out"
    assert_url_contains "F1 pr attach-list sends capped page" 1 "limit=2"

    # The _no_flags guard survives the table restore: --limit is stripped by
    # the pre-pass, but OTHER unknown flags still reach the parser and die
    # (exit 2, zero API calls).
    reset_log
    out="$(cd /tmp && "$FGH" issue attach-list 9 --foo 2>&1 >/dev/null)"; rc=$?
    assert_exit "F1 issue attach-list --foo exits 2" 2 "$rc"
    assert_contains "F1 issue attach-list names --foo" \
        "Usage: issue attach-list: unknown argument '--foo'" "$out"
    assert_eq "F1 issue attach-list --foo makes no API call" "0" "$(Log_count)"

    # ── PR1-F3: actions view job table must be ordered by REST id. The
    #    fixture serves the four jobs OUT of id order (8540, 8539, 8542,
    #    8541); UI index 0 must land on the smallest id (8539) so the
    #    human table agrees with `actions jobs` and --job-index.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  */runs/55/jobs*) Serve 200 '[{"id":8540,"name":"b","status":"failure","attempt":1},{"id":8539,"name":"a","status":"success","attempt":1},{"id":8542,"name":"d","status":"failure","attempt":1},{"id":8541,"name":"c","status":"waiting","attempt":1}]' ;;
  *) Serve 200 '{"id":55,"index_in_repo":7,"status":"failure","title":"ci","event":"push","head_branch":"main","head_sha":"abcd1234","started":"2026-09-03T00:00:00Z","stopped":"2026-09-03T00:01:00Z","trigger_user":{"login":"dev"}}' ;;
esac
EOF
    out="$(cd /tmp && "$FGH" actions view 55)"; rc=$?
    assert_exit "F3 actions view renders" 0 "$rc"
    for id in 8539 8540 8541 8542; do
        assert_contains "F3 view lists job #$id" " / #${id} " "$out"
    done
    # The UI-index lines must appear in ascending id order: each job's line
    # number grows with its index, and index 0 belongs to the smallest id
    # (8539) — NOT the first-served job (8540).
    l0="$(grep -n '^  0 / #8539 ' <<<"$out" | cut -d: -f1)"
    l1="$(grep -n '^  1 / #8540 ' <<<"$out" | cut -d: -f1)"
    l2="$(grep -n '^  2 / #8541 ' <<<"$out" | cut -d: -f1)"
    l3="$(grep -n '^  3 / #8542 ' <<<"$out" | cut -d: -f1)"
    assert_eq "F3 view index 0 line precedes index 1" "0" "$([[ "$l0" =~ ^[0-9]+$ && "$l1" =~ ^[0-9]+$ && "$l0" -lt "$l1" ]] && echo 0 || echo 1)"
    assert_eq "F3 view index lines in id order" "0" "$([[ "$l1" =~ ^[0-9]+$ && "$l2" =~ ^[0-9]+$ && "$l3" =~ ^[0-9]+$ && "$l1" -lt "$l2" && "$l2" -lt "$l3" ]] && echo 0 || echo 1)"
    assert_eq "F3 view smallest id gets index 0" "0 / #8539" "$(grep -o '[0-9]* / #8539' <<<"$out" | head -1)"

    # ── PR1-F4: _set_action_url_repo now runs the URL-derived slug through
    #    validate_repo_slug before assigning REPO_SLUG (defense-in-depth,
    #    mirroring -R/FGH_REPO).
    #
    #    Reachability: the URL regex ([^/]+)/([^/]+) only ever captures two
    #    NONEMPTY, slash-free segments, so a slug that actually fails
    #    validate_repo_slug (^[^/]+/[^/]+$) is IMPOSSIBLE to reach through a
    #    URL — the guard therefore can only ever be a no-op on the happy
    #    path. The malformed case the closest the regex permits (a
    #    double-slash "//bad-repo", empty owner) is caught EARLIER by the
    #    selector regex and dies with the selector error, never reaching the
    #    slug validation. We assert that reachable behavior rather than
    #    inventing an unreachable slug.
    reset_log
    bad_url="https://forgejo.test//bad-repo/actions/runs/5"
    out="$(env -u FGH_REPO "$FGH" actions view "$bad_url" 2>&1 >/dev/null)"; rc=$?
    assert_exit "F4 empty-owner URL rejected by selector regex" 2 "$rc"
    assert_contains "F4 empty-owner URL uses selector error" \
        "Actions run selector must be a REST ID" "$out"
    assert_eq "F4 empty-owner URL makes no API call" "0" "$(Log_count)"

    # A well-formed run URL still resolves its repository from the URL
    # (same behavior as 11_action_selectors) and the slug reaches the API.
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
case "$_url" in
  *run_number=157*) Serve 200 '{"total_count":1,"workflow_runs":[{"id":3493,"index_in_repo":157,"status":"success","title":"ci"}]}' ;;
  *) Serve 200 '{"id":3493,"index_in_repo":157,"status":"success","title":"ci"}' ;;
esac
EOF
    out="$(env -u FGH_REPO "$FGH" actions view https://forgejo.test/acme/widgets/actions/runs/157 --json id,run_number)"; rc=$?
    assert_exit "F4 well-formed URL resolves" 0 "$rc"
    assert_eq "F4 well-formed URL keeps run id" "3493" "$(jq -r .id <<<"$out")"
    assert_url_contains "F4 well-formed URL repository" 1 "/repos/acme/widgets/actions/runs?run_number=157"
}
