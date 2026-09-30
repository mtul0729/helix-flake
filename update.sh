#!/usr/bin/env bash
# Update the pinned helix rev, regenerate grammars.json for the new rev,
# then rebuild. Used by CI and runnable locally.
set -euo pipefail

cd "$(dirname "$0")"

nix flake update helix

helix_src="$(nix eval --raw .#helix-unwrapped.src)"
nix-shell -p nurl python3 --run \
  "python3 generate-grammars.py '$helix_src/languages.toml' -o grammars.json -j 16"

./build.sh

new_rev="$(nix flake metadata --json | jq -r '.locks.nodes.helix.locked.rev')"
echo "helix updated to $new_rev"
