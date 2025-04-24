# This flake provides command-line tools and a project template for the
# Writing AI-assisted assignment assessment workflow. It aims to streamline
# the process of converting student PDF submissions, extracting text using AI,
# and assessing them against a rubric.
{
  description = "AI-assisted writing assessment tools + project template";

  inputs = {
    # Define the Nix Packages collection version to use for dependencies
    nixpkgs.url = "nixpkgs/nixos-24.11"; # or your preferred channel
    # Utility library to easily support multiple systems (linux, macos)
    flake-utils.url = "github:numtide/flake-utils";
  };

  # The outputs function defines what the flake provides (packages, apps, shells, etc.)
  outputs = {
    self, # Reference to this flake itself
    nixpkgs, # The nixpkgs input defined above
    flake-utils, # The flake-utils input defined above
  }:
  # Use flake-utils to define outputs for each common system (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin)
    flake-utils.lib.eachDefaultSystem (system: let
      # Create a nixpkgs instance for the specific system
      pkgs = import nixpkgs {
        inherit system;
      };

      # Define a helper function to reduce repetition when creating script packages
      mkTool = name: scriptPath:
      # writeShellApplication creates a simple wrapper around a shell script
        pkgs.writeShellApplication {
          inherit name; # The name of the command (e.g., "writing-convert")
          # Specify runtime dependencies needed by the script
          runtimeInputs = with pkgs; [
            imagemagick # For PDF conversion
            llm # For AI interaction
          ];
          # The actual script content
          text = builtins.readFile scriptPath;
          # Skip the default checkPhase (which runs shellcheck)
          checkPhase = "";
        };
    in {
      # Define the packages provided by this flake for the current system
      packages = {
        # Package the PDF conversion script
        writing-convert = mkTool "writing-convert" ./scripts/convert_pdf_to_png.sh;
        # Package the text extraction script
        writing-extract = mkTool "writing-extract" ./scripts/extract_text_from_image.sh;
        # Package the assessment script
        writing-assess = mkTool "writing-assess" ./scripts/assess_assignment.sh;
        # Package the main orchestration script
        writing-main = mkTool "writing-main" ./scripts/main.sh;

        # Set the default package when referring to the flake (e.g., `nix build .`)
        default = self.packages.${system}.writing-main;
      };

      # Define development shells provided by this flake
      # This shell is for *developing the assessment tools themselves* within this repository
      devShells.default = pkgs.mkShell {
        # List packages available in the development shell
        buildInputs = with pkgs; [
          shellcheck # Linter for shell scripts
          shfmt # Formatter for shell scripts
          llm # Include llm for testing interaction
          imagemagick # Include imagemagick for testing conversion
          # Include the packaged tools themselves for easy testing during development
          self.packages.${system}.writing-main
        ];
      };

      # Define project templates provided by this flake
      # This template is used via `nix flake new -t .#project ./target-dir`
      templates.project = {
        # Specify the directory containing the template files
        path = ./template;
        # Description shown when listing templates
        description = "Scaffold for grading a single writing assignment";
      };
    }) # End of flake-utils call that generates system-specific outputs
    # Merge the system-specific outputs with the system-agnostic outputs below
    // {
      # Define project templates provided by this flake (Now outside flake-utils)
      # This template is used via `nix flake new -t .#project ./target-dir`
      templates = {
        # The top-level key should be 'templates'
        project = {
          # Specify the directory containing the template files
          path = ./template;
          # Description shown when listing templates
          description = "Scaffold for grading a single writing assignment";
        };
      }; # End of templates definition
    }; # End of the merged attribute set returned by 'outputs'
}
# End of the whole flake definition

