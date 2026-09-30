#!/usr/bin/env bash
# Build helix for a system (default: the host system), updating cargoHash
# with nix-update if the Cargo.lock of the pinned source changed.
# Used by CI and runnable locally.
set -euo pipefail

cd "$(dirname "$0")"

system="${1:-}"
target=".#helix"
if [ -n "$system" ]; then
  target=".#packages.${system}.helix"
fi

if ! out=$(nix build "$target" --accept-flake-config -L 2>&1); then
  echo "$out" | tail -10 >&2
  nix run nixpkgs#nix-update -- --flake helix-unwrapped --version=skip --generate-hashes --build
  nix build "$target" --accept-flake-config -L
fi
