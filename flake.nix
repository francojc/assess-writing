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

    perSystem = system: let
      pkgs = import nixpkgs {inherit system;};

      pythonEnv = pkgs.python3.withPackages (ps:
        with ps; [
          llm
          llm-gemini
          llm-openai-plugin
          llm-ollama
          llm-anthropic
        ]);

      main-cli = pkgs.stdenv.mkDerivation {
        pname = "main-cli";
        version = "1.0";
        src = ./scripts;

        nativeBuildInputs = [pkgs.makeWrapper];
        buildInputs = [pkgs.imagemagick pkgs.pandoc];

        installPhase = ''
          mkdir -p $out/bin
          for f in *.sh; do
            chmod +x $f
            cp $f $out/bin/
          done
          wrapProgram $out/bin/main.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.imagemagick pkgs.pandoc]}
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
          pythonEnv
        ];
      };
    };

    allSystems = flake-utils.lib.eachSystem systems perSystem;
  in
    allSystems
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
