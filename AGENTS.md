# AGENTS.md

Standalone Nix flake that packages [Helix](https://github.com/helix-editor/helix)
from a pinned rev (tracked in `flake.lock`), in nixpkgs packaging style, with
GitHub Actions auto-update and a `mtul` cachix binary cache.

## Repository layout

- `flake.nix` — inputs (`helix` source input, `nixpkgs`) and outputs
  (`packages.helix` / `packages.helix-unwrapped`, overlay `helix-git`,
  `nixConfig` for the cachix substituter).
- `unwrapped.nix` — `rustPlatform.buildRustPackage` for the `hx` binary
  (nixpkgs `helix-unwrapped` style): self-contained `fetchFromGitHub` with
  the pinned master `rev`, no grammars in the default runtime. There is no
  helix flake input — the rev lives here so nix-update can manage it.
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
- No versionCheckHook: `hx --version` prints the upstream version
  (`helix <base> (rev)`), which never contains the `-unstable-<shortrev>`
  suffix, so the hook would always fail. It works in nixpkgs only because
  their version is the pinned tag.
- Keep packaging aligned with nixpkgs'
  `pkgs/by-name/he/helix{,-unwrapped}/package.nix`, including
  `fetchCargoVendor` + `cargoHash`. Rev, src hash and cargoHash are updated
  together by `update.sh` via
  `nix-update --flake helix-unwrapped --version=branch=master --build` —
  this only works because src is a fetcher inside the package definition,
  not a flake input. No other path may change rev or hashes.
- Grammars that fail to build are fixed in `grammarsOverlay` inside
  `package.nix` (e.g. `NIX_CFLAGS_COMPILE = "-std=gnu17"` for C23/glibc
  conflicts, `dontPatch = true` when nixpkgs' patch is already in the pinned
  rev), not by editing `grammars.json`. The overlay entries are required by
  the grammar revs pinned in grammars.json (not by nixpkgs versions) — CI
  verified that removing the nixpkgs-inherited ones breaks the build. Keep
  them in sync when regenerating grammars.json.
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

- A green build job with an empty cache is a silent failure mode: always
  verify a `.narinfo` (URL is the bare store hash, no package name) returns
  200. Note that a `.drv` path differs from its output path — compare the
  right one.
- `update.sh` is the only updater (nix-update for rev+hashes, then
  grammars.json regeneration, then a build as validation). CI build runs
  are pure validation and never modify hashes.
- CI never calls `cachix push` explicitly: `.github/actions/setup` installs
  the cachix daemon (`useDaemon: true`), a post-build hook that pushes every
  store path CI builds — build-time deps included. Keep that mode; a
  runtime-only explicit push leaves consumers rebuilding source-prep
  derivations.
- build.yml builds all three platforms (x86_64-linux, aarch64-linux,
  aarch64-darwin) via a matrix; update.yml stays single-platform and only
  opens the PR. Derivation hashes do NOT depend on the Nix version — no
  version pinning anywhere.
- Locally, Nix caches flake-ref resolution for ~1h: after pushing a new
  commit, `nix build github:mtul0729/helix-flake#...` may silently evaluate
  the OLD commit — use `--refresh` when verifying pushes.
