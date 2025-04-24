{
  description = "AI-assisted writing assessment tools + project template";
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org/"
      # "https://nix-community.cachix.org"
      # "https://nixpkgs-python.cachix.org"
    ];
    extra-trusted-public-keys = [
      # keys published by the cache owners
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};

      mkTool = name: scriptPath:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            imagemagick
            python312Packages.llm
          ];
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
          python312Packages.llm
          python312Packages.llm-gemini
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
