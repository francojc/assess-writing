{
  description = "Single-assignment writing assessment project";
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org/"
      # "https://nix-community.cachix.org"
      # "https://nixpkgs-python.cachix.org"
    ];
    extra-trusted-public-keys = [
      # keys published by the cache owners
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    assess-writing.url = "github:francojc/assess-writing";
  };

  outputs = {
    self,
    nixpkgs,
    assess-writing,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        buildInputs = [assess-writing.packages.${system}.writing-main];
      };
    });
  };
}
