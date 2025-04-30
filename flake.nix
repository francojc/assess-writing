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

      # --- Package Groups ---
       corePkgs = with pkgs; [
         curl
         jq
         bashInteractive # Good to have a consistent bash
       ];

       conversionPkgs = with pkgs; [
         imagemagick
         pandoc
       ];

      pythonEnv = pkgs.python3.withPackages (ps:
        with ps; [
          llm
          llm-gemini
          llm-openai-plugin
          llm-ollama
          llm-anthropic
        ]);

      # --- Main CLI Package ---
      main-cli = pkgs.stdenv.mkDerivation {
        pname = "main-cli";
        version = "1.1"; # Increment version due to changes
        src = ./scripts;

        nativeBuildInputs = with pkgs; [ makeWrapper patchutils ];
        # Runtime dependencies needed in the PATH for the wrapped script
        buildInputs = [ pkgs.bash ] ++ corePkgs ++ conversionPkgs ++ [ pythonEnv ];

        installPhase = ''
          mkdir -p $out/bin $out/libexec/assess-writing/workflows $out/libexec/assess-writing/steps
          cp main.sh $out/bin/main.sh
          cp workflows/*.sh $out/libexec/assess-writing/workflows/
          cp steps/*.sh $out/libexec/assess-writing/steps/

          # Make all scripts executable
          chmod +x $out/bin/main.sh
          chmod +x $out/libexec/assess-writing/workflows/*.sh
          chmod +x $out/libexec/assess-writing/steps/*.sh

          # Patch main.sh to use the correct paths within the Nix store
          substituteInPlace $out/bin/main.sh \
            --replace 'SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )' '# SCRIPT_DIR calculation replaced by Nix build' \
            --replace 'workflows_dir="$SCRIPT_DIR/workflows"' "workflows_dir=\"$out/libexec/assess-writing/workflows\"" \
            --replace 'steps_dir="$SCRIPT_DIR/steps"' "steps_dir=\"$out/libexec/assess-writing/steps\""

          done
          wrapProgram $out/bin/main.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath buildInputs}
        '';

        meta = {
          description = "Main CLI entry point for project scripts";
          mainProgram = "main.sh";
        };
      };
    in {
      # --- Exported Packages ---
      packages = {
        default = main-cli;
        main-cli = main-cli;
      };

      # --- Development Shell ---
      devShells.default = pkgs.mkShell {
        buildInputs = [
          # Tools needed for running scripts directly in dev env
         ] ++ corePkgs ++ conversionPkgs ++ [
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
