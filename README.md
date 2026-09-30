# helix-flake

A standalone Nix flake that builds Helix from a pinned rev of
[helix-editor/helix](https://github.com/helix-editor/helix) — newer than
nixpkgs' package, and built with *your* nixpkgs toolchain so it reuses the
same binary cache as the rest of your system.

A GitHub Actions workflow periodically runs `nix flake update helix`, builds
the result, pushes it to the `mtul` cachix cache, and opens a PR.

## Usage

```console
$ nix run github:mtul0729/helix-flake
$ nix profile install github:mtul0729/helix-flake#helix
```

In your NixOS / home-manager config, follow your own nixpkgs so the Rust
toolchain and build inputs come from the same nixpkgs you already have cached:

```nix
inputs.helix-flake.url = "github:mtul0729/helix-flake";
inputs.helix-flake.inputs.nixpkgs.follows = "nixpkgs";

# then either
environment.systemPackages = [ inputs.helix-flake.packages.${pkgs.system}.helix ];
# or via the overlay
nixpkgs.overlays = [ inputs.helix-flake.overlays.default ]; # provides pkgs.helix-git
```

To also pull from your cachix cache:

```nix
nix.settings.substituters = [ "https://mtul.cachix.org" ];
nix.settings.trusted-public-keys = [ "mtul.cachix.org-1:<key>" ];
```

## How it works

- **Source**: the `helix` flake input (tracked by `flake.lock`, default
  `master`). Pin it to a release tag by editing the input URL in `flake.nix`.
- **Toolchain**: plain `rustPlatform` from the nixpkgs you pass in — no
  third-party overlay, so rustc and shared build inputs hit
  `cache.nixos.org`.
- **Cargo dependencies**: vendored from `Cargo.lock` with
  `allowBuiltinFetchGit`, so git dependencies need no `outputHashes` and
  there is no cargo hash to maintain on updates.
- **Grammars**: built from the `languages.toml` of the pinned helix rev,
  each grammar fetched at that recorded rev via `builtins.fetchTree` (pure,
  reproducible). Grammars are small C files and compile in seconds.
- **Version**: derived from the workspace `Cargo.toml` plus the pinned rev,
  in nixpkgs' `-unstable-<shortrev>` style; `hx --version` also embeds the
  rev via `HELIX_NIX_BUILD_REV`.

## Auto-update workflow

`.github/workflows/update.yml` runs weekly: updates the `helix` input, builds
the package (so a bad rev fails CI instead of your machines), pushes results
to cachix, and opens/updates a PR.

Set the `CACHIX_AUTH_TOKEN` repository secret to enable cache pushes (cache
name `mtul` is configured in the workflow and in `flake.nix`'s `nixConfig` —
remember to replace `REPLACE_WITH_YOUR_KEY` in `flake.nix` with the cache's
public key).
