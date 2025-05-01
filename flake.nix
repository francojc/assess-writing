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
          runHook preInstall # Standard practice

          # Create the bin directory
          mkdir -p $out/bin

          echo "Copying and making scripts executable..."
          # Find all '.sh' files directly in the source directory (scripts/)
          # and copy them to $out/bin, making them executable.
          # Use -maxdepth 1 to only find files in the immediate directory.
          find . -maxdepth 1 -type f -name '*.sh' -print0 | while IFS= read -r -d $'\0' file; do
              local script_name=$(basename "$file")
              echo "  Copying $file -> $out/bin/$script_name"
              cp "$file" "$out/bin/$script_name"
              chmod +x "$out/bin/$script_name"
          done

          echo "Wrapping all scripts in $out/bin..."
          # Now, wrap *each* executable script found in $out/bin
          # Identify the scripts we want to wrap (adjust if needed)
          for script_file in $out/bin/*.sh; do
             if [[ -f "$script_file" && -x "$script_file" ]]; then
                echo "  Wrapping $script_file"
                # Add all required runtime dependencies here
                wrapProgram "$script_file" \
                  --prefix PATH : ${pkgs.lib.makeBinPath [
                    pkgs.imagemagick pkgs.pandoc pythonEnv pkgs.jq pkgs.curl pkgs.coreutils pkgs.gnused pkgs.gnugrep
                  ]}
             fi
          done

          echo "--- DEBUG: Final structure of $out/bin ---"
          ls -l $out/bin
          echo "--- END DEBUG ---"

          runHook postInstall # Standard practice
        '';


        meta = {
          description = "Shell scripts for the project workflows";
          # main.sh is still a primary entry point, but others are also available
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
        default = {
          path = ./templates/
          description = "New project pre-assessment submissions";
        };
      };
    };
}
