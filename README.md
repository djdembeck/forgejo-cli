# forgejo-cli

`fgh` is a zero-install Bash CLI for Forgejo with `gh`-style commands and full Forgejo 16 Actions coverage.

`fgh` wraps Forgejo's REST API in a `gh`-style command model for developers and DevOps engineers running self-hosted Forgejo. It auto-detects the repository from the current Git remote, accepts an `FGH_REPO` override, and uses environment variables instead of a generated configuration format.

It is intentionally a single-file Bash script: there is no compilation step, package manager, or virtual environment. Use it to manage issues, pull requests, labels, repositories, Forgejo 16.0 Actions runs, logs, artifacts, secrets, and variables, or call any Forgejo REST endpoint directly.

## Table of Contents

- [Background](#background)
- [Install/Running](#installrunning)
- [Usage](#usage)
  - [Quickstart](#quickstart)
  - [Issues](#issues)
  - [Pull requests](#pull-requests)
  - [Labels](#labels)
  - [Actions](#actions)
  - [Repository](#repository)
  - [Raw API passthrough](#raw-api-passthrough)
  - [Help](#help)
- [Configuration](#configuration)
- [Dependencies](#dependencies)
- [Building](#building)
- [Contributing](#contributing)
- [License](#license)

## Background

Forgejo does not expose GraphQL, so the official GitHub CLI (`gh`) does not work against it. The Gitea [`tea` CLI](https://gitea.com/gitea/tea) SDK also lags behind Forgejo 16.0's new Actions endpoints. `fgh` provides a practical terminal workflow for self-hosted Forgejo without adding a compilation or dependency-management step.

## Install/Running

`fgh` needs Bash, `curl`, `jq`, and `column`. `git` is needed for automatic repository detection, and `gunzip` is needed when reading compressed Actions logs. Install the script as a symlink:

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/fgh" ~/.local/bin/fgh
```

Make sure `~/.local/bin` is on your `PATH`. Set the required Forgejo URL and token before running a command; the first example is also shown in [Usage](#quickstart):

```bash
export FORGEJO_URL=https://git.example.com
export FORGEJO_TOKEN=your-token-here
fgh issue list
```

Generate a token at `<FORGEJO_URL>/user/settings/applications`.

## Usage

Run `fgh` without arguments, or use `fgh --help`, for the full command list. Commands auto-detect `owner/repo` from the `origin` Git remote in the current directory. Outside a checkout, set `FGH_REPO=owner/repo`.

### Quickstart

These are the commands most users need first:

```bash
# Configure the instance for this shell.
export FORGEJO_URL=https://git.example.com
export FORGEJO_TOKEN=your-token-here

# List open issues (prints number, state, labels, and title).
fgh issue list

# Use a state argument and a repository override.
fgh issue list closed
FGH_REPO=owner/repo fgh pr view 17

# Create an issue with common options.
fgh issue create "Login fails" --body "Steps to reproduce..." --label bug --assignee alice
```

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

### Pull requests

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

### Actions

`fgh actions` supports Forgejo 16.0+ workflow runs, including polling, logs, artifacts, secrets, variables, and runners:

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

### Repository

```bash
fgh repo view
```

### Raw API passthrough

`fgh api` sends requests to `${FORGEJO_URL}/api/v1/<endpoint>` with the configured token. Use `-X METHOD` to select the HTTP method; pass a request body as the argument immediately after the endpoint.

```bash
fgh api repos/owner/repo/releases
fgh api -X POST repos/owner/repo/issues '{"title":"test"}'
```

### Help

```bash
fgh --help
```

## Configuration

Export these variables in your shell profile. If you keep them in `~/.config/fgh/config`, source that file from your profile; `fgh` does not load configuration files itself.

| Variable | Required | Description |
|---|---:|---|
| `FORGEJO_URL` | Yes | Forgejo base URL, such as `https://git.example.com`. |
| `FORGEJO_TOKEN` | Yes | Forgejo access token. |
| `FGH_TOKEN` | No | Token override with highest priority. |
| `FORGEJO_ISSUE_TOKEN` | No | Token fallback after `FGH_TOKEN` and before `FORGEJO_TOKEN`. |
| `FGH_REPO` | No | Overrides Git remote detection with `owner/repo`. |
| `FGH_DEFAULT_ASSIGNEE` | No | Auto-assigns created issues to this user. |

Token selection is `FGH_TOKEN`, then `FORGEJO_ISSUE_TOKEN`, then `FORGEJO_TOKEN`. The script still requires `FORGEJO_TOKEN` to be set at startup, even when an override is used.

## Dependencies

The runtime utilities are `bash`, `curl`, `jq`, `column`, `sed`, and `gunzip`; `git` is used for repository detection. There is no package manager or virtual environment.

## Building

There is nothing to compile. `install.sh` clones the repository when needed and symlinks `fgh` to `~/.local/bin/fgh`:

```bash
./install.sh
```

The installer uses `$HOME/projects/github/forgejo-cli` by default. Set `REPO=/path/to/forgejo-cli` to choose another checkout location. Cloning the default location requires `git` access to `git@github.com:djdembeck/forgejo-cli.git`.

## Contributing

There is no `CONTRIBUTING.md`, build system, or test suite. Edit the single `fgh` Bash script directly, keep changes focused, and exercise the affected command against a Forgejo instance before submitting a change. Contributions are covered by the MIT license.

## License

MIT
