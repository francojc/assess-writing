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
        buildInputs = [pkgs.imagemagick pkgs.pandoc pythonEnv];

        installPhase = ''
          # Create the bin directory
          mkdir -p $out/bin

          # Find all '.sh' files in the source directory (scripts/)
          # Copy them into $out/bin and make them executable
          find . -type f -name '*.sh' -print0 | while IFS= read -r -d $'\0' file; do
            # Get the base name of the script file
            local script_name=$(basename "$file")
            # Copy the file to the output bin directory
            cp "$file" "$out/bin/$script_name"
            # Make it executable
            chmod +x "$out/bin/$script_name"
          done

          # Now, wrap *each* script in $out/bin
          # This ensures dependencies are in the PATH for all scripts
          for script in $out/bin/*; do
            wrapProgram $script \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.imagemagick pkgs.pandoc pythonEnv ]}
          done
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
