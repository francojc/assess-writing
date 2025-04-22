{
  description = "Writing Tools Flake: Provides scripts and project template for AI assignment assessment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};

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
          deps = [pkgs.llm]; # llm provides 'llm'
        };
        writing-assess = mkScript {
          name = "writing-assess";
          src = ./scripts/assess_assignment.sh;
          deps = [pkgs.llm]; # llm provides 'llm'
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

        # A devShell for working *on* writing-tools itself (optional)
        devShell = pkgs.mkShell {
          packages = [
            pkgs.bashInteractive
            pkgs.shellcheck
            writing-convert
            writing-extract
            writing-assess
            writing-main
            pkgs.imagemagick
            pkgs.llm
          ];
        };
      }
    ) // {
      # Template for initializing new projects
      templates = {
        project = {
          path = ./templates/default;
          description = "A new Writing assignment assessment project";
        };
      };
    };
}
