# tests/cases/00_repo_token.bash — repo override + token scoping.

case_repo() {
    FGH_REPO="acme/widgets"
}

run() {
    # ── repo override: FGH_REPO determines the URL, no git remote needed ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"full_name":"acme/widgets","description":"","language":null,"stars_count":0,"forks_count":0,"open_issues_count":0,"default_branch":"main","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","html_url":"https://forgejo.test/acme/widgets","private":false}'
EOF
    out="$(cd /tmp && FGH_REPO=acme/widgets "$FGH" repo view 2>/dev/null)"
    assert_contains "repo view uses FGH_REPO" "acme/widgets" "$out"
    assert_url_call "repo view URL from FGH_REPO" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets"

    # ── -R/--repo global override wins anywhere on the command line ──
    # (cd outside any git clone so only the flag can supply the repo)
    reset_log
    out="$(cd /tmp && "$FGH" -R other/thing repo view 2>/dev/null)"
    assert_url_call "-R flag before subcommand sets repo path" 1 \
        "https://forgejo.test/api/v1/repos/other/thing"

    reset_log
    out="$(cd /tmp && "$FGH" repo view -R other/thing 2>/dev/null)"
    assert_url_call "-R flag after subcommand sets repo path" 1 \
        "https://forgejo.test/api/v1/repos/other/thing"

    # documented inline form --repo=VALUE must be honored, not ignored
    reset_log
    out="$(cd /tmp && "$FGH" repo view --repo=other/thing 2>/dev/null)"
    assert_url_call "--repo=VALUE inline form sets repo path" 1 \
        "https://forgejo.test/api/v1/repos/other/thing"

    # ── missing repo: clear failure, not a bogus URL ──
    reset_log
    rc=0; out="$(cd /tmp && env -u FGH_REPO "$FGH" repo view 2>&1 >/dev/null)" || rc=$?; out="$out~rc=$rc"
    assert_contains "no repo dies with message naming FGH_REPO" "FGH_REPO" "${out%%rc=*}"
    assert_contains "no repo exits nonzero" "rc=1" "$out"

    # ── token scoping: issue commands prefer FORGEJO_ISSUE_TOKEN ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[]'
EOF
    out="$(cd /tmp && FGH_REPO=acme/widgets FORGEJO_ISSUE_TOKEN=issue-tok FORGEJO_TOKEN=repo-tok "$FGH" issue list 2>/dev/null)"
    assert_auth_token "issue list uses issue token" 1 "issue-tok"

    reset_log
    out="$(cd /tmp && FGH_REPO=acme/widgets FORGEJO_ISSUE_TOKEN=issue-tok FORGEJO_TOKEN=repo-tok "$FGH" actions runner list 2>/dev/null)"
    assert_auth_token "actions uses repo token not issue token" 1 "repo-tok"

    # ── FGH_TOKEN overrides everything, in both groups ──
    reset_log
    out="$(cd /tmp && FGH_REPO=acme/widgets FGH_TOKEN=override-tok FORGEJO_ISSUE_TOKEN=issue-tok FORGEJO_TOKEN=repo-tok "$FGH" issue list 2>/dev/null)"
    assert_auth_token "FGH_TOKEN beats issue token" 1 "override-tok"

    reset_log
    out="$(cd /tmp && FGH_REPO=acme/widgets FGH_TOKEN=override-tok FORGEJO_TOKEN=repo-tok "$FGH" package list 2>/dev/null)"
    assert_auth_token "FGH_TOKEN wins outside issue group" 1 "override-tok"

    # ── actions/label/milestone also accept the issue-scoped token only for
    #    label and milestone; actions must NOT ──
    reset_log
    out="$(cd /tmp && FGH_REPO=acme/widgets FORGEJO_ISSUE_TOKEN=issue-tok FORGEJO_TOKEN=repo-tok "$FGH" label list 2>/dev/null)"
    assert_auth_token "label commands use issue token" 1 "issue-tok"

    # ── repo view does not inherit issue token ──
    reset_log
    out="$(cd /tmp && FGH_REPO=acme/widgets FORGEJO_ISSUE_TOKEN=issue-tok FORGEJO_TOKEN=repo-tok "$FGH" repo view 2>/dev/null)"
    assert_auth_token "repo view uses repo token" 1 "repo-tok"
}
