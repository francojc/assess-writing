{
  description = "Single-assignment writing assessment project";

  inputs.nixpkgs.url = "nixpkgs/nixos-24.05";
  inputs.assess-writing.url = "path:.."; # changed automatically when users pull from GitHub

  outputs = {
    self,
    nixpkgs,
    assess-writing,
  }: let
    system = builtins.currentSystem;
    pkgs = import nixpkgs {inherit system;};
  in {
    devShells.default = pkgs.mkShell {
      buildInputs = [
        assess-writing.packages.${system}.writing-main
      ];
    };
  };
}
