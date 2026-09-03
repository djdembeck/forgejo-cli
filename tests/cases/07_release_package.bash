# tests/cases/07_release_package.bash — release lifecycle and package commands.

run() {
    FGH_REPO=acme/widgets

    # ── release list ──
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/releases.json")"
EOF
    out="$(cd /tmp && "$FGH" release list --json tag_name,name 2>/dev/null)"
    assert_contains "release list tags" "v1.0.0" "$out"
    assert_url_contains "release list URL" "/releases?" "$(Url_of 1)"

    # ── release view by tag goes through releases/tags/{tag} ──
    reset_log
    out="$(cd /tmp && "$FGH" release view v1.0.0 --json tag_name 2>/dev/null)"
    assert_url_call "release view by tag URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/releases/tags/v1.0.0"
    assert_contains "release view response" "v1.0.0" "$out"

    # numeric release ID goes to releases/{id}
    reset_log
    out="$(cd /tmp && "$FGH" release view 21 --json tag_name 2>/dev/null)"
    assert_url_call "release view by id URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/releases/21"

    # ── release create payload ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/release_created.json")"
EOF
    printf 'release notes\n' > "$TEST_TMP/notes.md"
    out="$(cd /tmp && "$FGH" release create --tag v1.1.0 --title "v1.1.0" --notes-file "$TEST_TMP/notes.md" --target main --prerelease 2>/dev/null)"
    assert_contains "release create output" "v1.1.0" "$out"
    assert_method_call "release create POST" 1 "POST"
    assert_url_call "release create URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/releases"
    payload="$(printf '%s' "$(Log_body 1)" | jq -c .)"
    assert_eq "release create tag_name" "v1.1.0" "$(printf '%s' "$payload" | jq -r .tag_name)"
    assert_eq "release create name" "v1.1.0" "$(printf '%s' "$payload" | jq -r .name)"
    assert_eq "release create body from file" "release notes" "$(printf '%s' "$payload" | jq -r .body)"
    assert_eq "release create target" "main" "$(printf '%s' "$payload" | jq -r .target_commitish)"
    assert_eq "release create prerelease flag" "true" "$(printf '%s' "$payload" | jq -r .prerelease)"

    # ── release edit PATCHes /releases/{id} ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/release_created.json")"
EOF
    out="$(cd /tmp && "$FGH" release edit 22 --title "renamed" 2>/dev/null)"
    assert_method_call "release edit PATCH" 1 "PATCH"
    assert_url_call "release edit URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/releases/22"
    assert_eq "release edit name" "renamed" "$(printf '%s' "$(Log_body 1)" | jq -r .name)"

    # ── release asset upload: multipart + ?name= ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '{"id":91,"name":"dist.zip","browser_download_url":"https://forgejo.test/attachments/91"}'
EOF
    printf 'PK\x03\x04fake' > "$TEST_TMP/dist.zip"
    out="$(cd /tmp && "$FGH" release upload 22 "$TEST_TMP/dist.zip" 2>/dev/null)"
    line1="$(Log_line 1)"
    assert_contains "release upload multipart field" "attachment=@" "$line1"
    assert_url_contains "release upload URL assets" "/releases/22/assets?" "$(Url_of 1)"
    assert_url_contains "release upload default name from file" "name=dist.zip" "$(Url_of 1)"

    reset_log
    printf 'PK\x03\x04fake' > "$TEST_TMP/dist.zip"
    out="$(cd /tmp && "$FGH" release upload 22 "$TEST_TMP/dist.zip" --name renamed.zip --json browser_download_url 2>/dev/null)"
    assert_url_contains "release upload --name in query" "name=renamed.zip" "$(Url_of 1)"
    assert_contains "release upload returns embed URL" "browser_download_url" "$out"

    # ── release delete by ID ──
    reset_log
    out="$(cd /tmp && "$FGH" release delete 22 2>/dev/null)"
    assert_method_call "release delete DELETE" 1 "DELETE"
    assert_url_call "release delete URL" 1 \
        "https://forgejo.test/api/v1/repos/acme/widgets/releases/22"

    # ── package list (repo owner scope, optional type filter) ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 "$(cat "$TESTS_DIR/fixtures/packages.json")"
EOF
    out="$(cd /tmp && "$FGH" package list --json name,type,version 2>/dev/null)"
    assert_contains "package list names" "widgets" "$out"
    assert_url_call "package list URL owner-scoped" 1 \
        "https://forgejo.test/api/v1/packages/acme?page=1&limit=50"

    reset_log
    out="$(cd /tmp && "$FGH" package list container --json version 2>/dev/null)"
    assert_url_contains "package list type filter" "type=container" "$(Url_of 1)"

    # ── package delete: exact path with owner/type/name/version ──
    reset_log
    cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 204 ''
EOF
    out="$(cd /tmp && "$FGH" package delete container widgets 1.2.3 2>/dev/null)"
    assert_contains "package delete confirms" "container/widgets:1.2.3" "$out"
    assert_url_call "package delete URL exact" 1 \
        "https://forgejo.test/api/v1/packages/acme/container/widgets/1.2.3"
    assert_method_call "package delete DELETE" 1 "DELETE"
}
