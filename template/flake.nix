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
    system = builtins.currentSystem;
    pkgs = import nixpkgs {inherit system;};
  in {
    devShell.${system} = pkgs.mkShell {
      buildInputs = [assess-writing.packages.${system}.writing-main];
    };
  };
}
