#!/usr/bin/env bash
# Build .#helix, auto-fixing cargoHash if Cargo.lock changed. Used by CI and
# runnable locally.
set -euo pipefail

cd "$(dirname "$0")"

out=$(nix build .#helix --accept-flake-config -L 2>&1) || {
  echo "$out" | tail -10 >&2
  got=$(printf '%s' "$out" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | head -1)
  if [ -z "$got" ]; then
    echo "build failed and no cargoHash found in output" >&2
    exit 1
  fi
  echo "fixing cargoHash to $got" >&2
  sed -i "s|cargoHash = \"sha256-[^\"]*\"|cargoHash = \"$got\"|" unwrapped.nix
  nix build .#helix --accept-flake-config -L
}

if ! git diff --quiet unwrapped.nix 2>/dev/null; then
  echo "CARGO_HASH_CHANGED=1" >> "${GITHUB_ENV:-/dev/null}" || true
fi
