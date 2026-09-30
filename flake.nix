{
  description = "Helix editor built from a pinned rev of helix-editor/helix, using your own nixpkgs";

  inputs = {
    # Pin this to a release branch or tag instead of master if you prefer,
    # e.g. "github:helix-editor/helix/25.01".
    helix = {
      url = "github:helix-editor/helix/master";
      flake = false;
    };
    # Keep this in sync with your system (e.g. add
    # `helix-flake.inputs.nixpkgs.follows = "nixpkgs";` from your config) so
    # the toolchain and other build inputs come from the same, already-cached
    # nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    helix,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    eachSystem = f:
      nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {localSystem.system = system;}));
    gitRev = helix.rev or helix.dirtyRev or null;
  in {
    packages = eachSystem (pkgs: let
      # NB: `helix` here is the flake input; do not shadow it.
      helixPkg = pkgs.callPackage ./package.nix {helixSrc = helix; inherit gitRev;};
    in {
      inherit helixPkg;
      helix = helixPkg;
      default = helixPkg;
    });

    overlays.default = final: prev: {
      helix-git = final.callPackage ./package.nix {helixSrc = helix; inherit gitRev;};
    };

    nixConfig = {
      extra-substituters = ["https://mtul.cachix.org"];
      extra-trusted-public-keys = ["mtul.cachix.org-1:REPLACE_WITH_YOUR_KEY"];
    };
  };
}
