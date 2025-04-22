{
  description = "Writing Tools Flake: Provides scripts and project template for AI assignment assessment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Add llm input since it's not readily available in nixpkgs
    llm-cli.url = "github:simonw/llm";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    llm-cli,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};

        # --- Dependency Resolution ---
        # Use the llm-cli flake input directly instead of relying on nixpkgs
        llmPkg = llm-cli.packages.${system}.default;

        # Helper function to create script packages
        mkScript = {
          name,
          src,
          deps ? [],
        }:
          pkgs.writeScriptBin name ''
            #!${pkgs.bash}/bin/bash
            # Ensure coreutils and dependencies are in PATH
            export PATH=${pkgs.lib.makeBinPath ([pkgs.coreutils] ++ deps)}:$PATH
            # Execute the actual script content
            ${builtins.readFile src} "$@"
          '';

        # Define packaged scripts
        writing-convert = mkScript {
          name = "writing-convert";
          src = ./scripts/convert_pdf_to_png.sh;
          deps = [pkgs.imagemagick]; # imagemagick provides 'magick'
        };
        writing-extract = mkScript {
          name = "writing-extract";
          src = ./scripts/extract_text_from_image.sh;
          deps = [llmPkg];
        };
        writing-assess = mkScript {
          name = "writing-assess";
          src = ./scripts/assess_assignment.sh;
          deps = [llmPkg];
        };
        writing-main = mkScript {
          name = "writing-main";
          src = ./scripts/main.sh;
          # main script needs access to the others
          deps = [writing-convert writing-extract writing-assess];
        };
      in {
        # Packages provided by this flake
        packages = {
          inherit writing-convert writing-extract writing-assess writing-main;
          # Default package when using 'nix run writing-tools'
          default = writing-main;
        };

        # App provided by this flake (for 'nix run')
        apps.default = {
          type = "app";
          program = "${writing-main}/bin/writing-main";
        };

        # Template for initializing new projects
        templates.project = {
          path = ./template;
          description = "A new Writing assignment assessment project";
        };

        # A devShell for working *on* writing-tools itself (optional)
        devShell = pkgs.mkShell {
          packages = [
            pkgs.bashInteractive
            pkgs.shellcheck # Good for script development
            # Include the tools themselves for testing
            writing-convert
            writing-extract
            writing-assess
            writing-main
            # Dependencies needed by the scripts
            pkgs.imagemagick
            llmPkg
          ];
        };
      }
    );
}
