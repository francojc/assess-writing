{
  description = "Writing Assessment Project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # --- IMPORTANT ---
    # Adjust the URL to point to your actual writing-tools flake
    # Example (GitHub): writing-tools.url = "github:yourusername/writing-tools";
    # Example (Local Path during development): writing-tools.url = "path:../writing-tools";
    writing-tools.url = "github:yourusername/writing-tools"; # <-- CHANGE THIS
  };

  outputs = { self, nixpkgs, flake-utils, writing-tools }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Get the writing tools for the current system
        tools = writing-tools.packages.${system};
      in
      {
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
