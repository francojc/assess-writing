{
  description = "Single-assignment writing assessment project";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
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
