{
  # Description for this specific project flake (created from the template)
  description = "Single-assignment writing assessment project";

  # Define the inputs needed for this project flake
  inputs = {
    # Use the same Nix Packages collection as the main assess-writing tool
    # to ensure dependency consistency.
    nixpkgs.url = "nixpkgs/nixos-24.05";

    # Reference the assess-writing flake itself.
    # When using `nix flake new -t github:francojc/assess-writing#project ...`,
    # Nix automatically replaces 'path:..' with the correct flake reference (e.g., 'github:francojc/assess-writing').
    # If developing locally, 'path:..' points to the parent directory containing the main flake.nix.
    assess-writing.url = "path:.."; # changed automatically when users pull from GitHub
  };

  # Define the outputs provided by this project flake
  outputs = {
    self,        # Reference to this project's flake
    nixpkgs,     # The nixpkgs input defined above
    assess-writing, # The assess-writing flake input defined above
  }: let
    # Determine the user's current system (e.g., x86_64-linux)
    system = builtins.currentSystem;
    # Create a nixpkgs instance for the specific system
    pkgs = import nixpkgs {inherit system;};
  in {
    # Define the default development shell for this project
    devShells.default = pkgs.mkShell {
      # List the packages to make available within the shell environment
      buildInputs = [
        # Include the main orchestration script package (`writing-main`)
        # provided by the assess-writing flake. This makes the `writing-main`
        # command directly runnable when the shell is activated (e.g., via `nix develop` or `direnv`).
        assess-writing.packages.${system}.writing-main
      ];
    };
  };
}
