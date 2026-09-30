# Builds Helix from a pinned helix-editor/helix source (usually a flake
# input), following nixpkgs packaging conventions. Adapted from
# helix-editor/helix's own default.nix (which uses a rust-overlay and
# lib.fileset from a git checkout) so it can build from a plain source tree
# with nixpkgs' own rustPlatform.
{
  lib,
  rustPlatform,
  callPackage,
  runCommand,
  installShellFiles,
  git,
  # Helix source, usually a flake input of helix-editor/helix.
  helixSrc,
  gitRev ? null,
  includeGrammarIf ? _: true,
}:
let
  grammars = callPackage ./grammars.nix {inherit helixSrc includeGrammarIf;};

  runtimeDir = runCommand "helix-runtime" {} ''
    mkdir -p $out
    ln -s ${helixSrc}/runtime/* $out
    rm -r $out/grammars
    ln -s ${grammars} $out/grammars
  '';

  # helix-term/Cargo.toml only has `version.workspace = true`; the version
  # lives in the workspace root Cargo.toml.
  version = (builtins.fromTOML (builtins.readFile "${helixSrc}/Cargo.toml")).workspace.package.version;
  # nixpkgs convention for packages tracking an unreleased rev.
  versionSuffix =
    if gitRev == null
    then ""
    else "-unstable-" + builtins.substring 0 8 gitRev;
in
  rustPlatform.buildRustPackage {
    name = "helix${versionSuffix}";

    src = helixSrc;

    # Convenient here (but not allowed in nixpkgs): no need to specify
    # `outputHashes` for git dependencies, and no cargo hash to update when
    # Cargo.lock changes.
    cargoLock = {
      lockFile = "${helixSrc}/Cargo.lock";
      allowBuiltinFetchGit = true;
    };

    propagatedBuildInputs = [runtimeDir];

    nativeBuildInputs = [
      installShellFiles
      git
    ];

    buildType = "release";

    # Helix tries to fetch grammars from the network at runtime; they are
    # prebuilt into the runtime dir instead.
    HELIX_DISABLE_AUTO_GRAMMAR_BUILD = "1";

    # So `hx --version` shows the commit it was built from.
    HELIX_NIX_BUILD_REV = gitRev;

    doCheck = false;
    strictDeps = true;

    env.HELIX_DEFAULT_RUNTIME = "${runtimeDir}";

    postInstall = ''
      mkdir -p $out/lib
      installShellCompletion ${helixSrc}/contrib/completion/hx.{bash,fish,zsh}
      mkdir -p $out/share/{applications,icons/hicolor/{256x256,scalable}/apps}
      cp ${helixSrc}/contrib/Helix.desktop $out/share/applications/Helix.desktop
      cp ${helixSrc}/logo.svg $out/share/icons/hicolor/scalable/apps/helix.svg
      cp ${helixSrc}/contrib/helix.png $out/share/icons/hicolor/256x256/apps/helix.png
    '';

    passthru = {
      inherit grammars runtimeDir helixSrc;
      updateScript = ./update.sh;
    };

    meta = {
      description = "A post-modern modal text editor";
      homepage = "https://helix-editor.com";
      changelog = "https://github.com/helix-editor/helix/blob/${gitRev}/CHANGELOG.md";
      license = lib.licenses.mpl20;
      mainProgram = "hx";
      maintainers = [lib.maintainers.mtul];
      platforms = lib.platforms.unix;
    };
  }
