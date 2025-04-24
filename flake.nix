{
  description = "AI-assisted writing assessment tools + project template";

  inputs = {
    # New channel
    nixpkgs.url = "nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};

      mkTool = name: scriptPath:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [imagemagick llm];
          text = builtins.readFile scriptPath;
        };
    in {
      # ── Packages ─────────────────────────────────────────────
      packages = {
        writing-convert = mkTool "writing-convert" ./scripts/convert_pdf_to_png.sh;
        writing-extract = mkTool "writing-extract" ./scripts/extract_text_from_image.sh;
        writing-assess = mkTool "writing-assess" ./scripts/assess_assignment.sh;
        writing-main = mkTool "writing-main" ./scripts/main.sh;

        default = self.packages.${system}.writing-main;
      };

      # ── Dev-shell for hacking on this repo ──────────────────
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          shellcheck
          shfmt
          imagemagick
          llm
          self.packages.${system}.writing-main
        ];
      };
    })
    # ── Template exposed to the outside world ──────────────────
    // {
      templates.project = {
        path = ./template;
        description = "Scaffold for grading a single writing assignment";
      };
    };
}
