# tests/cases/08_repo_view_json.bash — repo view and --jq/--json plumbing.

run() {
    FGH_REPO=acme/widgets

    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/repo.json")"
EOF
    # ── repo view human output ──
    out="$(cd /tmp && "$FGH" repo view 2>/dev/null)"
    assert_contains "repo view name" "acme/widgets" "$out"
    assert_contains "repo view description" "Anvil-grade widgets" "$out"
    assert_contains "repo view stars" "3" "$out"

    # ── repo view --json with field projection ──
    reset_log
    out="$(cd /tmp && "$FGH" repo view --json full_name,stars_count 2>/dev/null)"
    assert_eq "repo view --json projection" \
        '{"full_name":"acme/widgets","stars_count":3}' \
        "$(printf '%s' "$out" | jq -c .)"

    # ── repo view --jq ──
    reset_log
    out="$(cd /tmp && "$FGH" repo view --jq .default_branch 2>/dev/null)"
    assert_eq "repo view -- jq branch" "main" "$out"

    # ── --jq implies JSON (works without --json) on lists too ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/issues_list.json")"
EOF
    out="$(cd /tmp && "$FGH" issue list --jq '[.[].number] | add' 2>/dev/null)"
    assert_eq "--jq works on list command without --json" "11" "$out"

    # ── --jq with fields still wins over --json projection ──
    reset_log
    out="$(cd /tmp && "$FGH" issue list --json number --jq 'length' 2>/dev/null)"
    assert_eq "--jq precedence over field projection" "2" "$out"
}
