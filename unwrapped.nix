# Mirrors nixpkgs' pkgs/by-name/he/helix-unwrapped: builds the helix binary
# with nixpkgs' rustPlatform and a default runtime without grammars. The
# actual grammars are assembled by the helix wrapper (package.nix).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  runCommand,
  installShellFiles,
  git,
}:
rustPlatform.buildRustPackage (
  finalAttrs:
  let
    # Tracking helix master; update.sh bumps this via
    # `nix-update --flake helix-unwrapped --version=branch=master`. To pin a
    # release instead, replace `rev` with `tag = "25.07.1"` (or similar).
    rev = "ba40e547426b0f9896c8bdc699a4ab11f2b37dbc";
  in
    {
      pname = "helix-unwrapped";
      # helix-term/Cargo.toml only has `version.workspace = true`; the version
      # lives in the workspace root Cargo.toml. nixpkgs convention for
      # packages tracking an unreleased rev: -unstable-<shortrev>.
      version =
        (builtins.fromTOML (builtins.readFile "${finalAttrs.src}/Cargo.toml")).workspace.package.version
        + "-unstable-"
        + builtins.substring 0 8 rev;

      src = fetchFromGitHub {
        owner = "helix-editor";
        repo = "helix";
        inherit rev;
        hash = "sha256-ZjMduEHRsY0H8OHJ5oiF/AcxOBhIiCBwo7D+g1yYwKc=";
      };

      # fetchCargoVendor, like nixpkgs: a single fixed-output derivation for
      # all cargo dependencies, so it is substitutable and cacheable.
      # update.sh refreshes both hashes via nix-update.
      cargoHash = "sha256-kJP6LMcx5z91XzO4PNbNvSSWOjVvJW35O7Z4uW9J+m8=";

      nativeBuildInputs = [
        installShellFiles
        git
      ];

      env = {
        # disable fetching and building of tree-sitter grammars in the helix-term build.rs
        HELIX_DISABLE_AUTO_GRAMMAR_BUILD = "1";
        HELIX_DEFAULT_RUNTIME = runCommand "helix-default-runtime" {} ''
          cp -r --no-preserve=mode ${finalAttrs.src}/runtime $out
          rm -rf $out/grammars $out/queries
        '';
        # So `hx --version` shows the commit it was built from.
        HELIX_NIX_BUILD_REV = rev;
      };

      postInstall = ''
        installShellCompletion ${finalAttrs.src}/contrib/completion/hx.{bash,fish,zsh}
        mkdir -p $out/share/{applications,icons/hicolor/{256x256,scalable}/apps}
        cp ${finalAttrs.src}/contrib/Helix.desktop $out/share/applications/Helix.desktop
        cp ${finalAttrs.src}/contrib/helix.png $out/share/icons/hicolor/256x256/apps/helix.png
        cp ${finalAttrs.src}/logo.svg $out/share/icons/hicolor/scalable/apps/helix.svg
      '';

      # NB: no versionCheckHook — hx --version prints the upstream version
      # ("helix 25.7.1 (rev)"), which can never contain our
      # -unstable-<shortrev> suffix, so the check would always fail. It only
      # works in nixpkgs because there version is the pinned tag.

      passthru = {
        updateScript = ./update.sh;
      };

      meta = {
        description = "Post-modern modal text editor";
        homepage = "https://helix-editor.com";
        changelog = "https://github.com/helix-editor/helix/blob/${rev}/CHANGELOG.md";
        license = lib.licenses.mpl20;
        mainProgram = "hx";
        platforms = lib.platforms.unix;
      };
    }
)
