{
  description = "Reusable shell scripts + project template with devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    systems = flake-utils.lib.defaultSystems;
  in
    flake-utils.lib.eachSystem systems (system: let
      pkgs = import nixpkgs {inherit system;};

      main-cli = pkgs.stdenv.mkDerivation {
        pname = "main-cli";
        version = "1.0";
        src = ./scripts;

        nativeBuildInputs = [pkgs.makeWrapper];
        buildInputs = [pkgs.jq pkgs.imagemagick];

        installPhase = ''
          mkdir -p $out/bin
          for f in *.sh; do
            chmod +x $f
            cp $f $out/bin/
          done
          wrapProgram $out/bin/main.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.jq pkgs.imagemagick]}
        '';

        meta = {
          description = "Main CLI entry point for project scripts";
          mainProgram = "main.sh";
        };
      };
    in {
      packages = {
        default = main-cli;
        main-cli = main-cli;
      };

      devShells.default = pkgs.mkShell {
        buildInputs = [
          main-cli
          pkgs.bashInteractive
        ];
      };
    })
    // {
      templates = {
        hand = {
          path = ./templates/hand;
          description = "New project for hand-written submissions";
        };
        canvas = {
          path = ./templates/canvas;
          description = "New project for canvas submissions";
        };
      };
    };
}
