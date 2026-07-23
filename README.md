# forgejo-cli

`fgh` — A CLI wrapper around the [Forgejo](https://forgejo.org/) REST API.

Single-file Bash script. Manages issues, PRs, labels, repos, and Actions (runs, logs, cancel, artifacts, secrets, variables).

Built because Forgejo doesn't expose GraphQL, so `gh` doesn't work against it, and the [Gitea `tea` CLI](https://gitea.com/gitea/tea) SDK lags behind Forgejo 16.0's new Actions endpoints.

## Install

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/fgh" ~/.local/bin/fgh
```

Make sure `~/.local/bin` is on your `PATH`.

## Configure

Set environment variables (e.g. in your shell profile or `~/.config/fgh/config`):

```bash
FORGEJO_URL=https://git.example.com
FORGEJO_TOKEN=your-token-here
```

Optional overrides:

| Variable | Description |
|---|---|
| `FGH_TOKEN` | Overrides `FORGEJO_TOKEN` |
| `FGH_REPO` | Overrides git remote detection (`owner/repo`) |
| `FGH_DEFAULT_ASSIGNEE` | Auto-assign issues to this user |

Generate the token at `<FORGEJO_URL>/user/settings/applications`.

## Usage

Run `fgh` without arguments for the full command list. All commands auto-detect the repo from `git remote` in the current directory, or use `FGH_REPO=owner/repo`.

### Issues

```bash
fgh issue list [open|closed]
fgh issue view 42
fgh issue create                    # interactive
fgh issue create "Title" "Body"     # or inline
fgh issue close 42
fgh issue open 42
fgh issue comment 42 "msg here"
```

### Pull Requests

```bash
fgh pr list [open|closed]
fgh pr view 17
fgh pr reviews 17
fgh pr review-comments 17
```

### Labels

```bash
fgh label list
fgh label create bug d73a4a "Something isn't working"
fgh label ensure                    # auto-creates standard labels
```

### Actions (Forgejo 16.0+)

```bash
fgh actions list                    # last 20 runs
fgh actions view 1983               # run details + jobs
fgh actions watch 1983              # poll until done
fgh actions logs 1983               # run logs (gzipped, decompressed)
fgh actions logs 1983 4620          # specific job logs
fgh actions jobs 1983               # job table
fgh actions cancel 1983             # cancel running workflow
fgh actions delete 1983             # remove workflow run

fgh actions artifact list
fgh actions artifact download 496 output.zip
fgh actions artifact delete 496

fgh actions secret list
fgh actions secret set MY_KEY       # value from stdin
fgh actions secret delete MY_KEY

fgh actions variable list
fgh actions variable set REGION us-east-1
fgh actions variable delete REGION

fgh actions runner list             # if runners endpoint available
fgh actions runner register
```

### Raw API Passthrough

```bash
fgh api repos/owner/repo/releases
fgh api -X POST repos/owner/repo/issues -d '{"title":"test"}'
```

## Dependencies

`bash`, `curl`, `jq`, `column`.
