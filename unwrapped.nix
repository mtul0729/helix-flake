# Mirrors nixpkgs' pkgs/by-name/he/helix-unwrapped: builds the helix binary
# from a pinned source (usually a flake input of helix-editor/helix) with
# nixpkgs' rustPlatform and a default runtime without grammars. The actual
# grammars are assembled by the helix wrapper (package.nix).
{
  lib,
  rustPlatform,
  runCommand,
  installShellFiles,
  git,
  versionCheckHook,
  helixSrc,
  gitRev ? null,
}:
rustPlatform.buildRustPackage (
  finalAttrs:
  let
    # helix-term/Cargo.toml only has `version.workspace = true`; the version
    # lives in the workspace root Cargo.toml.
    baseVersion =
      (builtins.fromTOML (builtins.readFile "${helixSrc}/Cargo.toml")).workspace.package.version;
    # nixpkgs convention for packages tracking an unreleased rev.
    version =
      if gitRev == null
      then baseVersion
      else "${baseVersion}-unstable-" + builtins.substring 0 8 gitRev;

    defaultRuntimeDir = runCommand "helix-default-runtime" {} ''
      cp -r --no-preserve=mode ${helixSrc}/runtime $out
      rm -rf $out/grammars $out/queries
    '';
  in
    {
      name = "helix-unwrapped-${version}";

      src = helixSrc;

      # fetchCargoVendor, like nixpkgs: a single fixed-output derivation for
      # all cargo dependencies, so it is substitutable and cacheable.
      # update.sh refreshes the hash automatically when Cargo.lock changes.
      cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

      nativeBuildInputs = [
        installShellFiles
        git
        versionCheckHook
      ];

      env = {
        # disable fetching and building of tree-sitter grammars in the helix-term build.rs
        HELIX_DISABLE_AUTO_GRAMMAR_BUILD = "1";
        HELIX_DEFAULT_RUNTIME = defaultRuntimeDir;
        # So `hx --version` shows the commit it was built from.
        HELIX_NIX_BUILD_REV = gitRev;
      };

      postInstall = ''
        installShellCompletion ${helixSrc}/contrib/completion/hx.{bash,fish,zsh}
        mkdir -p $out/share/{applications,icons/hicolor/{256x256,scalable}/apps}
        cp ${helixSrc}/contrib/Helix.desktop $out/share/applications/Helix.desktop
        cp ${helixSrc}/contrib/helix.png $out/share/icons/hicolor/256x256/apps/helix.png
        cp ${helixSrc}/logo.svg $out/share/icons/hicolor/scalable/apps/helix.svg
      '';

      versionCheckProgram = "${placeholder "out"}/bin/hx";
      doInstallCheck = true;

      passthru = {
        updateScript = ./update.sh;
        inherit helixSrc version;
      };

      meta = {
        description = "Post-modern modal text editor";
        homepage = "https://helix-editor.com";
        changelog = "https://github.com/helix-editor/helix/blob/${gitRev}/CHANGELOG.md";
        license = lib.licenses.mpl20;
        mainProgram = "hx";
        platforms = lib.platforms.unix;
      };
    }
)
