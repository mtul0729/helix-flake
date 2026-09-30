{
  description = "Helix editor tracking helix-editor/helix master, built with your own nixpkgs";

  inputs = {
    # Keep this in sync with your system (e.g. add
    # `helix-flake.inputs.nixpkgs.follows = "nixpkgs";` from your config) so
    # the toolchain and other build inputs come from the same, already-cached
    # nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    eachSystem = f:
      nixpkgs.lib.genAttrs systems (system:
        f nixpkgs.legacyPackages.${system});
  in {
    packages = eachSystem (pkgs: let
      helix-unwrapped = pkgs.callPackage ./unwrapped.nix {};
      helix = pkgs.callPackage ./package.nix {inherit helix-unwrapped;};
    in {
      inherit helix-unwrapped;
      inherit helix;
      default = helix;
    });

    overlays.default = final: prev: let
      helix-unwrapped = final.callPackage ./unwrapped.nix {};
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
