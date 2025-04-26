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
      # Define Python environment with llm and llm-gemini
      pythonEnv = pkgs.python313.withPackages (ps:
        with ps; [
          llm
          llm-gemini
          llm-openai-plugin
          llm-ollama
          llm-anthropic
        ]);
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          assess-writing.packages.${system}.main-cli # Use the specific package name
          pkgs.bashInteractive
          pythonEnv # Add Python environment
          pkgs.curl # Add curl for do-acquire.sh
          pkgs.jq # Add jq for do-acquire.sh
        ];
        shellHook = ''
          echo "Welcome to the Canvas submission pre-assessment shell!"
          echo "Ensure that you set up 'llm' correctly to use your chosen API."
          echo "Also, set your Canvas environment variables: CANVAS_API_KEY and CANVAS_BASE_URL."
        '';
      };
    });
}
