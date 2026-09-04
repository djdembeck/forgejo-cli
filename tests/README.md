# tests/README.md — fgh regression test harness

Deterministic, zero-install test suite for the `fgh` Forgejo CLI. No network,
no credentials, no external test framework — plain Bash plus the same
dependencies `fgh` itself needs (`curl` is shadowed, `jq`, `column`, `git`).

## Run

```sh
tests/run.sh                    # everything
tests/run.sh 09_extended       # only matching case files
```

Exit status is `0` only when every assertion passes. Each failure prints the
assertion name, what was expected, and what actually happened.

## Design

- **Fake curl** — `tests/bin/curl` is prepended to `PATH`. Every `fgh` call
  into curl is recorded (full argv, request bodies) to a temp log and served
  a canned response. Each command under test gets a response profile via
  `Serve` or binary-safe `Serve_file` from the response script a case writes.
  Tests assert stdout, stderr, exit status, and recorded curl arguments/bodies—
  never implementation text.
- **Fixtures** — `tests/fixtures/` holds canned API responses and a base64 ZIP
  of run logs.
- **Token sentinels** — `FORGEJO_TOKEN=test-repo-token`,
  `FORGEJO_ISSUE_TOKEN=test-issue-token`, `FGH_TOKEN=` by default. Cases flip
  these to prove token precedence (repo vs issue scope vs FGH override).

## Layout

```
tests/run.sh          entry point; sets env, sources cases, tallies assertions
tests/bin/curl        recording + response-supplying curl stand-in
tests/lib/assert.sh   assert_eq / assert_contains / assert_exit / ...
tests/lib/log.sh      Log_count / Log_line / Url_of / Method_of / Log_body
tests/cases/*.bash    one file per feature area, each defining run()
tests/fixtures/       response payloads (issue JSON, run-logs ZIP as b64, ...)
```

## Adding a case

Create `tests/cases/<topic>.bash` defining `run()`. Inside it:

```bash
cat > "$FAKE_CURL_SCRIPT" <<'EOF'
Serve 200 '[{"number":1,"title":"t","state":"open"}]'
EOF
out="$("$FGH" issue list 2>/dev/null)"
assert_contains "issue list shows title" "t" "$out"
assert_url_call "issue list URL" 1 \
  "https://forgejo.test/api/v1/repos/o/r/issues?state=open&page=1&limit=50&type=issues"
```

`reset_log` clears the recording between invocations when one `run()` drives
`fgh` more than once.
