#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash nix jq
# Update the pinned helix rev and rebuild. Used by CI and runnable locally.
set -euo pipefail

cd "$(dirname "$0")"

nix flake update helix
nix build .#helix --accept-flake-config -L

new_rev="$(nix flake metadata --json | jq -r '.locks.nodes.helix.locked.rev')"
echo "helix updated to $new_rev"
