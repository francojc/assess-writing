# Canvass Tools

This repository contains a Nix flake that provides command-line tools and a project template for the Canvass AI-assisted assignment assessment workflow. It aims to streamline the process of converting student PDF submissions, extracting text using AI, and assessing them against a rubric.

## Features

*   **Packaged Scripts:** Provides the core Canvass workflow scripts as Nix packages, ensuring their dependencies (like ImageMagick and the `llm` tool) are available:
    *   `canvass-convert`: Converts PDFs to PNGs.
    *   `canvass-extract`: Extracts text from PNGs using an AI model via `llm`.
    *   `canvass-assess`: Assesses extracted text using an AI model, rubric, and assignment description via `llm`.
    *   `canvass-main`: Orchestrates the full pipeline (convert -> extract -> assess) or individual stages.
*   **Project Template:** Includes a `nix flake init` template to quickly scaffold a new assessment project directory with the necessary structure and configuration.
*   **Reproducible Environment:** Leverages Nix flakes to ensure a consistent and reproducible environment for running the assessment tools.

## Prerequisites

*   **Nix Package Manager:** Needs to be installed on your system. See [NixOS installation guide](https://nixos.org/download.html). Ensure flake support is enabled.
*   **Git:** Required for cloning repositories and using the flake template.
*   **`llm` Tool Configuration:** While the flake provides the `llm` command-line tool, you still need to configure it with your AI provider API keys (e.g., OpenAI, Google Gemini). Refer to the [`llm` documentation](https://llm.datasette.io/en/stable/setup.html#configuring-api-keys). The scripts currently use `gemini-2.0-flash` and assume `llm` is configured appropriately.
*   **`direnv` (Recommended):** Useful for automatically loading the Nix environment when you `cd` into a project directory.

## Getting Started: Creating a New Assessment Project

1.  **Navigate** to the directory where you want to create your new project folder.
2.  **Run `nix flake init`**, pointing it to this `canvass-tools` flake's `project` template.
    *   **Important:** Replace `<canvass-tools-flake-url>` with the actual URL or path to *this* `canvass-tools` flake repository.
        *   Example using a GitHub URL:
            ```bash
            nix flake init -t github:your-username/canvass-tools#project ./my-assignment-grading
            ```
        *   Example using a local path (if `canvass-tools` is checked out locally):
            ```bash
            # Assuming 'canvass-tools' is in the parent directory
            nix flake init -t path:../canvass-tools#project ./my-assignment-grading
            ```
3.  **Navigate into the new project directory:**
    ```bash
    cd ./my-assignment-grading
    ```
4.  **Allow `direnv`** to load the environment (if you use `direnv`):
    ```bash
    direnv allow
    ```
    This command reads the `.envrc` file (which contains `use flake`) and activates the Nix shell defined in the project's `flake.nix`, making the `canvass-main` command available. If not using `direnv`, manually enter the environment with `nix develop`.

## Project Workflow

Once your project is initialized:

1.  **Edit Documentation:** Customize the placeholder files in the `docs/` directory:
    *   `docs/assignment_description.md`: Add the specific description for the assignment being graded.
    *   `docs/rubric.md`: Add the specific grading rubric.
2.  **Add Submissions:** Place the student assignment PDF files into the `pdfs/` directory.
3.  **Run Processing:** Execute the main pipeline script from the project's root directory:
    ```bash
    # Run all stages: Convert PDFs -> Extract Text -> Assess Text
    canvass-main

    # Or run specific stages using flags (see details below)
    canvass-main -C # Only convert PDFs to PNGs
    canvass-main -E # Only extract text from existing PNGs
    canvass-main -A # Only assess existing text files
    canvass-main -CE # Convert and Extract, but don't assess
    ```
4.  **Check Outputs:** The script will generate files in the following directories:
    *   `pngs/`: High-resolution PNG images converted from the PDFs.
    *   `text/`: Markdown files containing the text extracted from the PNGs.
    *   `assessment/`: Markdown files containing the AI-generated assessment based on the rubric and description.

## Provided Tools: `canvass-main`

The primary tool made available in your project environment is `canvass-main`.

```
Usage: canvass-main [OPTIONS]

Orchestrates Canvass PDF processing pipeline within an initialized project.

Options:
  -C, --convert   Run PDF to PNG conversion only
  -E, --extract   Run text extraction from PNGs only
  -A, --assess    Run assignment assessment only
  -h, --help      Show this help message

Run multiple stages by combining flags (e.g., -CE).
By default (no flags), runs all stages (-CEA).

Expects to be run inside a project initialized with the Canvass template:
- pdfs/ directory for input PDFs
- docs/ directory with rubric.md and assignment_description.md

Example:
  canvass-main         # Run all stages
  canvass-main -C      # Run only conversion
```

## Dependencies Handled by Nix

The project flake ensures the following core dependencies are available in the environment:

*   **ImageMagick:** Used by `canvass-convert` for PDF-to-PNG conversion.
*   **`llm`:** The command-line tool used by `canvass-extract` and `canvass-assess` to interact with Large Language Models.

Remember to configure `llm` with your API keys separately.

## `canvass-tools` Repository Structure

*   `flake.nix`: Defines the Nix flake, its packages (`canvass-*` scripts), the project template, and a development shell for working on the tools themselves.
*   `scripts/`: Contains the raw Bash scripts (`convert_pdf_to_png.sh`, `extract_text_from_image.sh`, `assess_assignment.sh`, `main.sh`). These are wrapped by the Nix derivations defined in `flake.nix`.
*   `template/`: Contains the file structure and basic configuration files (`flake.nix`, `.envrc`, `.gitignore`, placeholder `docs/`, `pdfs/`) used by `nix flake init -t ... #project`.
*   `README.md`: This file.

## Developing `canvass-tools`

If you want to modify the scripts or the flake itself within this `canvass-tools` repository:

1.  Clone this repository.
2.  `cd canvass-tools`
3.  Run `direnv allow` or `nix develop`. This will load the `devShell` defined in `canvass-tools/flake.nix`, which includes `shellcheck` and the packaged tools themselves for testing.
