{
  description = "Canvas submission template with CLI tool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    assess-writing.url = "github:francojc/assess-writing";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    assess-writing,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      # pythonEnv is no longer defined here, as it's part of assess-writing.packages.*.main-cli
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          assess-writing.packages.${system}.main-cli # Provides core scripts & their dependencies (Python, curl, jq, etc.)
          pkgs.bashInteractive                     # For a better interactive shell
          # Removed: pythonEnv, pkgs.curl, pkgs.jq (provided by main-cli wrapper)
        ];
        shellHook = ''
          echo "Welcome to the Canvas submission pre-assessment shell!"
          echo "The core scripts (pull.sh, acquire.sh, etc.) are available."
          echo "Ensure that you set up 'llm' correctly to use your chosen API (llm keys set)."
          echo "Also, set your Canvas environment variables: CANVAS_API_KEY and CANVAS_BASE_URL."
        '';
      };
    });
}
