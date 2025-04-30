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
        # Dependencies needed by the scripts at runtime
        buildInputs = [
          pkgs.imagemagick pkgs.pandoc pythonEnv pkgs.jq pkgs.curl pkgs.coreutils pkgs.gnused pkgs.gnugrep
        ];

        installPhase = ''
          # Create bin and libexec directories
          mkdir -p $out/bin
          mkdir -p $out/libexec/assess-writing

          # Copy main.sh to bin
          cp main.sh $out/bin/main.sh
          chmod +x $out/bin/main.sh

          # Copy steps and workflows directories to libexec
          cp -r steps $out/libexec/assess-writing/steps
          cp -r workflows $out/libexec/assess-writing/workflows

          # Make all scripts in libexec executable
          find $out/libexec/assess-writing -type f -name '*.sh' -exec chmod +x {} +

          # Wrap main.sh to make dependencies available when it (and its children) run
          # Ensure all dependencies used by *any* script are listed here
          wrapProgram $out/bin/main.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath [
              pkgs.imagemagick pkgs.pandoc pythonEnv pkgs.jq pkgs.curl pkgs.coreutils pkgs.gnused pkgs.gnugrep
            ]}
        '';

        meta = {
          description = "Shell scripts for the project workflows";
          # Keep main.sh as the conceptual main entry point if desired
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
