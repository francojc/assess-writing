{
  description = "Canvass Tools Flake: Provides scripts and project template for AI assignment assessment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Add llm input since it's not readily available in nixpkgs
    llm-cli.url = "github:simonw/llm-cli";
  };

  outputs = { self, nixpkgs, flake-utils, llm-cli, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # --- Dependency Resolution ---
        # Use the llm-cli flake input directly instead of relying on nixpkgs
        llmPkg = llm-cli.packages.${system}.default;

        # Helper function to create script packages
        mkScript = { name, src, deps ? [] }: pkgs.writeScriptBin name ''
          #!${pkgs.bash}/bin/bash
          # Ensure coreutils and dependencies are in PATH
          export PATH=${pkgs.lib.makeBinPath ([ pkgs.coreutils ] ++ deps)}:$PATH
          # Execute the actual script content
          ${builtins.readFile src} "$@"
        '';

        # Define packaged scripts
        canvass-convert = mkScript {
          name = "canvass-convert";
          src = ./scripts/convert_pdf_to_png.sh;
          deps = [ pkgs.imagemagick ]; # imagemagick provides 'magick'
        };
        canvass-extract = mkScript {
          name = "canvass-extract";
          src = ./scripts/extract_text_from_image.sh;
          deps = [ llmPkg ];
        };
        canvass-assess = mkScript {
          name = "canvass-assess";
          src = ./scripts/assess_assignment.sh;
          deps = [ llmPkg ];
        };
        canvass-main = mkScript {
          name = "canvass-main";
          src = ./scripts/main.sh;
          # main script needs access to the others
          deps = [ canvass-convert canvass-extract canvass-assess ];
        };

      in
      {
        # Packages provided by this flake
        packages = {
          inherit canvass-convert canvass-extract canvass-assess canvass-main;
          # Default package when using 'nix run canvass-tools'
          default = canvass-main;
        };

        # App provided by this flake (for 'nix run')
        apps.default = {
          type = "app";
          program = "${canvass-main}/bin/canvass-main";
        };


        # Template for initializing new projects
        templates.project = {
          path = ./template;
          description = "A new Canvass assignment assessment project";
        };

        # A devShell for working *on* canvass-tools itself (optional)
        devShell = pkgs.mkShell {
          packages = [
            pkgs.bashInteractive
            pkgs.shellcheck # Good for script development
            # Include the tools themselves for testing
            canvass-convert
            canvass-extract
            canvass-assess
            canvass-main
            # Dependencies needed by the scripts
            pkgs.imagemagick
            llmPkg
          ];
        };
      }
    );
}
