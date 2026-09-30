#!/usr/bin/env bash
# Build helix for a system (default: the host system), fixing cargoHash when
# the Cargo.lock of the pinned source changed.
#
# The fix is a targeted sed on the single `cargoHash` line in unwrapped.nix:
# nix-update cannot update hashes when the derivation's src is a flake input
# it cannot change (no src/version bump -> no hash update). If nix-update
# ever gains this capability, switch to it.
# Used by CI and runnable locally.
set -euo pipefail

cd "$(dirname "$0")"

system="${1:-}"
target=".#helix"
if [ -n "$system" ]; then
  target=".#packages.${system}.helix"
fi

if ! out=$(nix build "$target" --accept-flake-config -L 2>&1); then
  # Keep enough context to diagnose remote failures.
  printf '%s\n' "$out" | grep -E "error|fail" | head -40 >&2
  got=$(printf '%s' "$out" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | head -1)
  if [ -z "$got" ]; then
    echo "build failed and no cargoHash mismatch found; see log above" >&2
    exit 1
  fi
  echo "fixing cargoHash to $got" >&2
  sed -i "s|cargoHash = \"sha256-[^\"]*\"|cargoHash = \"$got\"|" unwrapped.nix
  nix build "$target" --accept-flake-config -L
fi
