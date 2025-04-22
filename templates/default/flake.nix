{
  description = "Writing Assessment Project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    assess-writing.url = "github:francojc/assess-writing";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    assess-writing,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        # Get the writing tools for the current system
        tools = assess-writing.packages.${system};
      in {
        # Development environment for this assessment project
        devShell = pkgs.mkShell {
          # Include the main canvass script and potentially others if needed directly
          packages = [
            tools.writing-main
            # Add other tools needed for *this specific project* if any
            # e.g., pkgs.python3 for analysis scripts
          ];

          shellHook = ''
            echo "--- Writing Project Environment ---"
            echo "Assessment tools (writing-main, etc.) are available."
            echo "1. Edit files in ./docs/ (rubric.md, assignment_description.md)"
            echo "2. Add student PDFs to ./pdfs/"
            echo "3. Run 'writing-main' to process."
            echo "---------------------------------"
          '';
        };
      }
    );
}
