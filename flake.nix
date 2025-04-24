{
  description = "AI-assisted writing assessment tools + project template";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05"; # or your preferred channel
    flake-utils.url = "github:numtide/flake-utils";
    # Optional: use an overlay pin if `llm` isn’t in nixpkgs yet
    llm-src.url = "github:simonw/llm";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    llm-src,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            llm = prev.python3Packages.buildPythonPackage {
              pname = "llm";
              version = "git";
              src = llm-src;
              propagatedBuildInputs = with prev.python3Packages; [
                click
                httpx
                jinja2
                pydantic
                rich
              ];
              doCheck = false;
            };
          })
        ];
      };

      # Helper to avoid repetition
      mkTool = name: scriptPath:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [imagemagick llm];
          text = builtins.readFile scriptPath;
        };
    in {
      packages = {
        writing-convert = mkTool "writing-convert" ./scripts/convert_pdf_to_png.sh;
        writing-extract = mkTool "writing-extract" ./scripts/extract_text_from_image.sh;
        writing-assess = mkTool "writing-assess" ./scripts/assess_assignment.sh;
        writing-main = mkTool "writing-main" ./scripts/main.sh;

        default = self.packages.${system}.writing-main;
      };

      # Nice dev shell with common tooling
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          shellcheck
          shfmt
          llm
          imagemagick
          self.packages.${system}.writing-main # include the packaged tools
        ];
      };

      # nix flake init -t github:francojc/assess-writing#project
      templates.project = {
        path = ./template;
        description = "Scaffold for grading a single writing assignment";
      };
    });
}
