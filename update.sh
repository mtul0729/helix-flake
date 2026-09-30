#!/usr/bin/env bash
# Unified updater, following nixpkgs' pkgs/by-name/he/helix/update.sh:
# nix-update bumps the pinned rev and regenerates the src and cargo hashes in
# one step, then grammars.json is regenerated for the new source and the
# package is built as validation. This is the only path that changes rev or
# hashes — CI build runs are pure validation.
set -euo pipefail

cd "$(dirname "$0")"

nix profile install --priority 100 nixpkgs#nix-update nixpkgs#nurl

echo "Updating flake inputs (nixpkgs)..."
nix flake update

echo "Updating helix-unwrapped (rev + src hash + cargoHash)..."
nix-update --flake helix-unwrapped --version=branch=master --build

echo "Fetching updated helix source..."
helix_src="$(nix eval --raw .#helix-unwrapped.src --accept-flake-config)"

echo "Generating grammars.json..."
python3 generate-grammars.py "$helix_src/languages.toml" -o grammars.json -j 16

echo "Building helix..."
nix build .#helix --accept-flake-config -L

rev="$(nix eval --raw .#helix-unwrapped.passthru.rev --accept-flake-config)"
echo "helix is now pinned to $rev"
