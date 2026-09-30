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
      "aarch64-darwin"
    ];
    eachSystem = f:
      nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs {localSystem.system = system;}));
    gitRev = helix.rev or helix.dirtyRev or null;
    # Bind the flake input up front: inside the `packages`/`overlays` lets,
    # the name `helix` is shadowed by the wrapper package (let bindings are
    # recursive in Nix).
    helixSrc = helix;
  in {
    packages = eachSystem (pkgs: let
      helix-unwrapped = pkgs.callPackage ./unwrapped.nix {inherit helixSrc gitRev;};
      helix = pkgs.callPackage ./package.nix {inherit helix-unwrapped;};
    in {
      inherit helix-unwrapped;
      inherit helix;
      default = helix;
    });

    overlays.default = final: prev: let
      helix-unwrapped = final.callPackage ./unwrapped.nix {inherit helixSrc gitRev;};
    in {
      inherit helix-unwrapped;
      helix-git = final.callPackage ./package.nix {inherit helix-unwrapped;};
    };

    nixConfig = {
      extra-substituters = ["https://mtul.cachix.org"];
      extra-trusted-public-keys = ["mtul.cachix.org-1:WEuapLtfyNPLkcCbwQh3jLxVwEwQNcDXhru9lbuhDlo="];
    };
  };
}
