#!/usr/bin/env bash
# Unified updater, following nixpkgs' pkgs/by-name/he/helix/update.sh:
# nix-update bumps the pinned rev and regenerates the src and cargo hashes in
# one step, then grammars.json is regenerated for the new source and the
# package is built as validation. This is the only path that changes rev or
# hashes — CI build runs are pure validation.
set -euo pipefail

cd "$(dirname "$0")"

nix profile install --priority 100 nixpkgs#nix-update nixpkgs#nurl

# Fast path: languages.toml — and therefore grammars.json — is fully determined
# by the pinned rev, so when master has not moved there is nothing to do but
# the expensive part would still run (~5min of per-grammar nurl prefetches).
# Keep the remote in sync with unwrapped.nix's fetchFromGitHub.
current_rev="$(nix eval --raw .#helix-unwrapped.passthru.rev --accept-flake-config)"
upstream_rev="$(git ls-remote https://github.com/helix-editor/helix refs/heads/master | cut -f1 || true)"
if [ -n "$upstream_rev" ] && [ "$upstream_rev" = "$current_rev" ]; then
  echo "helix already pinned to master $current_rev; nothing to update"
  exit 0
fi

echo "Updating helix-unwrapped (rev + src hash + cargoHash)..."
nix-update --flake helix-unwrapped --version=branch=master --build

echo "Fetching updated helix source..."
# nix build (not nix eval) realizes the src fixed-output derivation, so the
# files actually exist on disk even when it isn't in the binary cache.
helix_src="$(nix build --print-out-paths .#helix-unwrapped.src --accept-flake-config)"

echo "Generating grammars.json..."
python3 generate-grammars.py "$helix_src/languages.toml" -o grammars.json -j 16

echo "Building helix..."
nix build .#helix --accept-flake-config -L

rev="$(nix eval --raw .#helix-unwrapped.passthru.rev --accept-flake-config)"
echo "helix is now pinned to $rev"
