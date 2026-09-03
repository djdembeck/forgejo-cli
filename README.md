# forgejo-cli

`fgh` is a zero-install, single-file Bash CLI for Forgejo, targeting **Forgejo 16.0.3**, with `gh`-style commands and first-class Actions coverage.

`fgh` wraps the Forgejo v1 REST API in a `gh`-style command model for developers and DevOps engineers running self-hosted Forgejo. It auto-detects the repository from the current Git remote, accepts an `FGH_REPO` or `-R owner/repo` override, and is configured entirely through environment variables. Issues, labels, milestones, pull requests (including reviews, reviewers, checks, and merge), releases and their assets, packages, and Forgejo Actions (runs, jobs, logs, artifacts, secrets, variables, runners, dispatch) are all first-class commands. Anything not first-class is reachable through `fgh api`.

## Table of Contents

- [Background](#background)
- [Install/Running](#installrunning)
- [Usage](#usage)
  - [Quickstart](#quickstart)
  - [JSON and JQ output](#json-and-jq-output)
  - [Issues](#issues)
  - [Labels](#labels)
  - [Milestones](#milestones)
  - [Pull requests](#pull-requests)
  - [Releases](#releases)
  - [Packages](#packages)
  - [Actions](#actions)
  - [Repository](#repository)
  - [Instance](#instance)
  - [Raw API passthrough](#raw-api-passthrough)
- [Configuration](#configuration)
- [Dependencies](#dependencies)
- [Forgejo 16.0.3 limitations](#forgejo-1603-limitations)
- [Building](#building)
- [Contributing](#contributing)
- [License](#license)

## Background

Forgejo does not expose GraphQL, so the official GitHub CLI (`gh`) does not work against it. The Gitea [`tea` CLI](https://gitea.com/gitea/tea) SDK also lags behind Forgejo 16.0's Actions endpoints. `fgh` provides a practical terminal workflow for self-hosted Forgejo without adding a compilation or dependency-management step. Every REST path, method, and payload in `fgh` is written against the Forgejo 16.0.3 API.

## Install/Running

Install the script as a symlink:

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/fgh" ~/.local/bin/fgh
```

Make sure `~/.local/bin` is on your `PATH`. Set the required Forgejo URL and token before running a command; the first example is also shown in [Quickstart](#quickstart):

```bash
export FORGEJO_URL=https://git.example.com
export FORGEJO_TOKEN=your-token-here
fgh issue list
```

Generate a token at `<FORGEJO_URL>/user/settings/applications`. The token needs the scopes matching the commands you use (repo read/write, Actions read/write, package write for `fgh package delete`).

## Usage

Run `fgh` without arguments or `fgh --help` for the full command list; `fgh <command> --help` (for example `fgh issue --help`) prints per-command usage. Commands auto-detect `owner/repo` from the `origin` Git remote in the current directory. Outside a checkout, set `FGH_REPO=owner/repo` or pass `-R owner/repo` to any command.

Token selection: `FGH_TOKEN` overrides all; `FORGEJO_ISSUE_TOKEN` is used only by `issue`, `label`, and `milestone` commands; everything else uses `FORGEJO_TOKEN`.

### Quickstart

```bash
# Configure the instance for this shell.
export FORGEJO_URL=https://git.example.com
export FORGEJO_TOKEN=your-token-here

# List open issues (human table).
fgh issue list

# Search issues and cap results — automation-safe JSON.
fgh issue list --state open --search "cron" --limit 5 --json number,title

# Create an issue with body/labels/assignee from files and variables.
fgh issue create "Login fails" --body-file notes.md --label bug --assignee alice

# Follow a failing PR through merge.
fgh pr view 17
fgh pr checks 17
fgh pr merge 17 --squash --delete-branch

# Watch a run and fetch logs.
fgh actions list --limit 5
fgh actions watch 1983
fgh actions logs 1983                     # run archive, printed as text
fgh actions logs 1983 --job 4620          # canonical plaintext job log
```

### JSON and JQ output

Every list and view command accepts structured-output flags; `--jq` implies JSON:

```bash
fgh issue list --json                                  # full JSON array
fgh issue list --json number,title                     # projected fields
fgh pr list --state open --head main --json number,author   # author = PR author login
fgh repo view --json --jq '.stars_count'
fgh issue list --jq '[.[] | select(.title | test("cron")) | .number]'
```

When `--json` or `--jq` is set, the command emits only JSON on stdout — human tables and status messages never interleave, and non-2xx API responses exit nonzero with the response body on stderr. Without structured flags, output is a readable column/indented table.

### Issues

```bash
fgh issue list [--state open|closed|all] [--search TEXT] [--label A,B]
               [--milestone NAME|ID] [--assignee USER] [--creator USER]
               [--mentioned USER] [--since RFC3339] [--before RFC3339]
               [--sort ORDER] [--limit N] [--json [FIELDS]] [--jq EXPR]
fgh issue view 42 [--json ...]
fgh issue create TITLE [--body TEXT | --body-file FILE|-]
      [--assignee USER]... [--label NAME]... [--milestone ID] [--json ...]
fgh issue edit 42 --title "new" --body-file fix.md --state open
fgh issue close 42 | fgh issue open 42
fgh issue comments 42 [--json ...]
fgh issue comment 42 "text" | --body-file FILE
fgh issue attach 42 FILE [--name NAME]      # prints the embed (browser_download_url)
fgh issue attach-list 42 | fgh issue detach 42 ATTACH_ID
fgh issue comment-attach COMMENT_ID FILE [--name NAME]
fgh issue comment-attachments COMMENT_ID
fgh issue comment-detach COMMENT_ID ATTACH_ID
```

`--label` names are resolved to label IDs; a missing label is auto-created (default color `#c5c5c5`). If `FGH_DEFAULT_ASSIGNEE` is set and no `--assignee` is given, created issues are assigned to that user.

### Labels

```bash
fgh label list [--json ...]
fgh label create bug --color d73a4a --description "Something isn't working" [--exclusive]
fgh label edit 7 --name bug2 --color 00aabb [--exclusive true|false | --no-exclusive]
fgh label delete 7
fgh label ensure          # create the standard label set when missing
```

### Milestones

```bash
fgh milestone list [--state open|closed|all] [--json ...]
fgh milestone create "v1.2" --description "..." --due-on 2026-01-31T00:00:00Z
fgh milestone edit 3 --state closed
fgh milestone delete 3
```

### Pull requests

PR comments and attachments reuse the issue endpoints (a PR index is an issue index in Forgejo).

```bash
fgh pr list [--state open|closed|all] [--head REF] [--base BRANCH] [--json number,title,author,...]
fgh pr view 17
fgh pr create --head feature --base main --title "Add X" --body-file body.md [--draft]
fgh pr edit 17 --title "..." --allow-maintainer-edit true
fgh pr close 17 | fgh pr open 17
fgh pr comments 17 / fgh pr comment 17 "text" / fgh pr attach 17 FILE
fgh pr diff 17             # raw diff ('patch' also accepted)
fgh pr files 17 / fgh pr commits 17
fgh pr checks 17           # commit statuses of the head SHA
fgh pr status 17           # merged + mergeability snapshot
fgh pr reviews 17          # paginated review list with full bodies
fgh pr review-comments 17 [REVIEW_ID]
fgh pr review-comment 17 REVIEW_ID --path src/a.go --line 42 --body "note"
fgh pr review 17 --event APPROVED --body "lgtm"    # or --request-changes / --comment
fgh pr review-reply 17 99 --body-file review.md    # submit a pending review
fgh pr reviewer add 17 alice bob --team backend
fgh pr reviewer remove 17 alice
fgh pr merge 17 --squash [--subject T] [--message M] [--delete-branch] [--force]
fgh pr update-branch 17 [--style merge|rebase]
```

Merge methods: `-m`/`--merge`, `--rebase`, `--squash`, `--rebase-merge`, `--fast-forward-only`, `--manually-merged`. Use `--manually-merged --commit-id <sha>` to record an existing merge commit.

### Releases

```bash
fgh release list [--json ...]
fgh release view v1.0.0            # by ID or tag
fgh release create --tag v1.1.0 --title "..." --notes-file notes.md [--draft] [--prerelease] [--target SHA]
fgh release edit 5 [--body "..." | --notes-file notes.md] [--prerelease]
fgh release delete 5
fgh release assets 5               # list assets
fgh release upload 5 dist.zip [--name other.zip]
fgh release delete-asset 5 ASSET_ID
```

### Packages

The Forgejo package API is owner-scoped, so `fgh package list` covers the repository owner's packages:

```bash
fgh package list [TYPE] [--search TEXT] [--json ...]
fgh package list container --json type,name,version
fgh package delete container myimage 1.2.3     # TYPE NAME VERSION
```

### Actions

`fgh actions` covers Forgejo 16.0 workflow runs, jobs, logs, the task queue, dispatch, artifacts, secrets, variables, and runners:

```bash
fgh actions list [--status S] [--event E] [--ref R] [--workflow ID] [--run-number N]
fgh actions view 1983                     # run details + jobs
fgh actions jobs 1983                     # job table (id, status, runs-on, attempt)
fgh actions watch 1983 [--timeout SEC] [--interval SEC]
fgh actions tasks [--status queued]       # task queue listing

fgh actions logs 1983                     # run logs: ZIP, safely printed as text
fgh actions logs 1983 --job 4620          # canonical plaintext job log
fgh actions logs 1983 --job 4620 --attempt 2
fgh actions logs 1983 --job 4620 --follow [--timeout SEC]

fgh actions dispatch deploy.yml --ref main --input region=eu-west-1
fgh actions cancel 1983
fgh actions delete 1983

fgh actions artifact list [--run 1983] [--name NAME]
fgh actions artifact download 496 out.zip
fgh actions artifact delete 496

fgh actions secret list
fgh actions secret set MY_KEY             # value: stdin, prompt, or --body VALUE
fgh actions secret delete MY_KEY

fgh actions variable list                 # values are returned for variables
fgh actions variable set REGION eu-west-1
fgh actions variable delete REGION

fgh actions runner list [--visible true|false] [--org ORG]
fgh actions runner view 3
fgh actions runner register --name shell-2 --description "Linux runner" [--ephemeral]
fgh actions runner jobs [--labels self-hosted,linux]
fgh actions runner token                  # deprecated compatibility endpoint
fgh actions runner delete 3
```

Log mechanics in Forgejo 16.0.3: `actions logs RUN` downloads the run's log ZIP and prints each `.log` member (named `{job-name}-{job-id}-attempt-{N}.log`) with `unzip -p` — never binary. `--job JOB_ID` fetches the canonical plaintext job log instead; `--attempt N` selects a historical attempt. `--follow` **requires a job ID** (run archives are static) and polls the job log with `Range: bytes=offset-` requests, printing exactly the new bytes and never duplicating output; it exits 0 when the job succeeds, 1 otherwise (use `--timeout` to bound the wait).

### Repository

```bash
fgh repo view [--json [FIELDS]] [--jq EXPR]
```

### Instance

```bash
fgh instance version [--json [FIELDS]] [--jq EXPR]
```

### Raw API passthrough

`fgh api` is the fallback for anything without a first-class command. It normalizes leading `/` and an optional `api/v1/` prefix, accepts all HTTP methods, and supports `--input FILE|-`, `-f/--field KEY=VALUE`, `-H 'K: V'`, and `--jq EXPR`:

```bash
fgh api repos/owner/repo/issues?state=open
fgh api -X POST repos/owner/repo/issues -f title=Test -f body="From fgh api"
fgh api --input payload.json -X PATCH repos/owner/repo/issues/9
fgh api '/api/v1/repos/owner/repo/commits/main/status' --jq '.state'
```

Non-2xx responses print the response body to stderr and exit 1.

## Configuration

Export in your shell profile (optionally kept in `~/.config/fgh/config` and sourced from there; `fgh` loads no files itself):

| Variable | Required | Description |
|---|---:|---|
| `FORGEJO_URL` | Yes | Forgejo base URL, e.g. `https://git.example.com`. |
| `FORGEJO_TOKEN` | Yes | Access token. |
| `FGH_TOKEN` | No | Token override; highest priority for every command. |
| `FORGEJO_ISSUE_TOKEN` | No | Token fallback used only by `issue`, `label`, and `milestone` commands. |
| `FGH_REPO` | No | Overrides Git remote detection with `owner/repo`. |
| `FGH_DEFAULT_ASSIGNEE` | No | Auto-assigns created issues to this user when `--assignee` is not given. |

`-R owner/repo` overrides repository detection for any single invocation.

## Dependencies

- `bash` — the shell fgh runs under
- `curl` — HTTP
- `jq` — JSON parsing, filtering, and payload construction (all request bodies are built with `jq`; user text is never interpolated into JSON)
- `column` — human-readable tables
- `sed` and `grep` — remote parsing and small text filters
- `git` — repository detection from the origin remote
- `unzip` — extracting per-job `.log` members from run log ZIPs (`fgh actions logs RUN`); not needed when using `--job JOB_ID` logs or artifacts

## Forgejo 16.0.3 limitations

- **No workflow-run rerun.** Forgejo 16.0.3 implements no rerun API for Actions; `fgh` deliberately provides no rerun command rather than faking one. Re-dispatch the workflow (`fgh actions dispatch`) or push a new commit instead.
- **Run logs are a ZIP**, not plain text; `fgh actions logs RUN` requires `unzip` to print them. Job logs (`--job`) are plaintext with no extra dependency.
- **`--follow` is job-only** because run log archives are static snapshots; the job log endpoint answers Range requests.
- **Package listing is owner-scoped** (Forgejo API shape), so `fgh package list` shows the repository owner's packages with optional type/name filters.

## Building

There is nothing to compile. `install.sh` clones the repository when needed and symlinks `fgh` to `~/.local/bin/fgh`:

```bash
./install.sh
```

The installer uses `$HOME/projects/github/forgejo-cli` by default. Set `REPO=/path/to/forgejo-cli` to choose another checkout location.

## Contributing

`fgh` is a single Bash script. Keep changes focused and exercise affected commands against Forgejo 16.0.3. Run the deterministic fake-API regression suite with `tests/run.sh`; it requires no network or real credentials. Run `shellcheck fgh` if available. Contributions are covered by the MIT license.

## License

MIT
