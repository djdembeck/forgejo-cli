#!/usr/bin/env bash
# Install fgh from the forgejo-cli repo as a symlink to ~/.local/bin
# This lets you test feature branches by checking them out.

set -euo pipefail

REPO="${REPO:-$HOME/projects/github/forgejo-cli}"
BIN_DIR="$HOME/.local/bin"

if [[ ! -d "$REPO" ]]; then
    mkdir -p "$(dirname "$REPO")"
    git clone git@github.com:djdembeck/forgejo-cli.git "$REPO"
fi

mkdir -p "$BIN_DIR"
ln -sf "$REPO/fgh" "$BIN_DIR/fgh"
echo "Installed: $BIN_DIR/fgh -> $REPO/fgh"
