# AGENTS.md

Standalone Nix flake that packages [Helix](https://github.com/helix-editor/helix)
from a pinned rev (tracked in `flake.lock`), in nixpkgs packaging style, with
GitHub Actions auto-update and a `mtul` cachix binary cache.

## Repository layout

- `flake.nix` — inputs (`helix` source input, `nixpkgs`) and outputs
  (`packages.helix` / `packages.helix-unwrapped`, overlay `helix-git`,
  `nixConfig` for the cachix substituter).
- `unwrapped.nix` — `rustPlatform.buildRustPackage` for the `hx` binary
  (nixpkgs `helix-unwrapped` style: `versionCheckHook`, no grammars in the
  default runtime).
- `package.nix` — `symlinkJoin` wrapper (nixpkgs `helix` style): grammars
  from nixpkgs' `tree-sitter-grammars` collection pinned to the revs in
  helix's `languages.toml`, `hx` wrapped with `HELIX_RUNTIME`.
- `grammars.json` — grammar lock data (owner/repo/rev/hash/subpath per
  grammar), generated; do not edit by hand.
- `generate-grammars.py` — regenerates `grammars.json` with `nurl`
  (copied from nixpkgs' helix package).
- `update.sh` — one-shot updater: `nix flake update helix` → regenerate
  `grammars.json` → `nix build`.
- `.github/workflows/build.yml` — build + cachix push on push/手动触发.
- `.github/workflows/update.yml` — weekly auto-update PR (updates flake.lock
  and grammars.json, builds, pushes to cachix, opens a PR).

## Conventions

- Version strings follow nixpkgs: `<base>-unstable-<8-char rev>`, base
  version read from the workspace root `Cargo.toml` (`[workspace.package]`;
  `helix-term/Cargo.toml` only has `version.workspace = true`).
- Keep packaging aligned with nixpkgs'
  `pkgs/by-name/he/helix{,-unwrapped}/package.nix`, including
  `fetchCargoVendor` + `cargoHash`. `build.sh` auto-fixes `cargoHash` when
  Cargo.lock changes (CI commits the fix); never hand-edit it unless
  `build.sh` is unavailable.
- Grammars that fail to build are fixed in `grammarsOverlay` inside
  `package.nix` (e.g. `NIX_CFLAGS_COMPILE = "-std=gnu17"` for C23/glibc
  conflicts, `dontPatch = true` when nixpkgs' patch is already in the pinned
  rev), not by editing `grammars.json`.
- Update `systems` in `flake.nix` if nixpkgs support changes (x86_64-darwin
  was dropped by nixpkgs 26.11).

## Build & test

- Evaluation only (fast, no compilation):
  `nix eval --raw .#helix.name`
- Full build happens in CI (do not run full `nix build` locally unless the
  user asks); single grammars are cheap:
  `nix build .#helix.passthru.tree-sitter-grammars.tree-sitter-<name> -L`
- Verify the cachix cache serves a path (URL is the bare store hash, NO name
  suffix):
  `curl -s -o /dev/null -w "%{http_code}" https://mtul.cachix.org/<hash>.narinfo`

## Version control

- Use `jj` (Jujutsu, colocated with git) for all commits; `jj st`, `jj
  describe -m ...`, `jj git push`. GitHub account: `mtul0729`, repo:
  `mtul0729/helix-flake`.

## CI gotchas

- **Nix version pin**: CI installs Nix 2.34.8 (`install_url` in both
  workflows) to match the consumer machines. Nix 2.35 changed
  structuredAttrs serialization, so derivations built with 2.35 hash
  differently than 2.34 — a CI built with the wrong version produces a
  completely useless cache. Bump the pin together with local Nix upgrades.
- `cachix/cachix-action@v16` has no `nixBuildArgs` input — building must be a
  separate explicit `nix build` step, then `cachix push mtul result`.
- A green build job with empty cachix is a silent failure mode: always
  verify a `.narinfo` (URL is the bare store hash, no package name) returns
  200 after "successful" pushes.
- `nix flake update helix` alone is not enough: `grammars.json` must be
  regenerated for the new rev and `cargoHash` re-fixed (both handled by
  `update.sh`).
- CI pushes the full BUILD closure (`cachix push mtul $(nix eval --raw
  .#helix.drvPath)`), so build-time deps like the cargo vendor dir are also
  cached; a runtime-only `cachix push result` leaves consumers rebuilding
  source-prep derivations locally.
- Locally, Nix caches flake-ref resolution for ~1h: after pushing a new
  commit, `nix build github:mtul0729/helix-flake#...` may silently evaluate
  the OLD commit — use `--refresh` when verifying pushes.
