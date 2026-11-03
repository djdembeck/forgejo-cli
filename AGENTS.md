# Agents

`fgh` is a Bash CLI for Forgejo's REST API, not GitHub's. Review changes against these existing contracts:

- **Output/errors:** README "JSON and JQ output". Structured-output stdout carries only the requested data, never human tables/status text; preserve established `--jq` scalar formatting. Non-2xx responses retain the API error on stderr and exit nonzero; automation uses exit status, not success-text matching.
- **Actions identifiers:** README "Actions". Bare integers are REST database IDs; UI run/job/attempt values require their explicit selectors or complete UI URL. Never strip a UI number and pass it as a REST ID.
- **Authentication:** README "Configuration" and the dispatch/token handling in `fgh`. `FGH_TOKEN` overrides all commands; `FORGEJO_ISSUE_TOKEN` overrides `FORGEJO_TOKEN` only for issue/label/milestone. Other families use `FORGEJO_TOKEN` unless overridden by `FGH_TOKEN`.
- **Version-dependent behavior:** follow the README's server-version limits and the CLI's version gates; do not invent unsupported operations or bypass fail-closed checks.

Read `tests/README.md` before harness changes. Use deterministic fake-curl fixtures; live Forgejo mutations are not part of verification.
