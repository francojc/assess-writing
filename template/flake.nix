{
  description = "Canvass Assessment Project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # --- IMPORTANT ---
    # Adjust the URL to point to your actual canvass-tools flake
    # Example (GitHub): canvass-tools.url = "github:yourusername/canvass-tools";
    # Example (Local Path during development): canvass-tools.url = "path:../canvass-tools";
    canvass-tools.url = "github:yourusername/canvass-tools"; # <-- CHANGE THIS
  };

  outputs = { self, nixpkgs, flake-utils, canvass-tools }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Get the canvass tools for the current system
        tools = canvass-tools.packages.${system};
      in
      {
        # Development environment for this assessment project
        devShell = pkgs.mkShell {
          # Include the main canvass script and potentially others if needed directly
          packages = [
            tools.canvass-main
            # Add other tools needed for *this specific project* if any
            # e.g., pkgs.python3 for analysis scripts
          ];

          shellHook = ''
            echo "--- Canvass Project Environment ---"
            echo "Assessment tools (canvass-main, etc.) are available."
            echo "1. Edit files in ./docs/ (rubric.md, assignment_description.md)"
            echo "2. Add student PDFs to ./pdfs/"
            echo "3. Run 'canvass-main' to process."
            echo "---------------------------------"
          '';
        };
      }
    );
}
