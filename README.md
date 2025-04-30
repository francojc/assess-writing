# Assess Writing

## Description

This flake provides a simple way to pre-process writing samples for assessment using a command-line interface driven by `scripts/main.sh`. It supports two primary workflows corresponding to the different project templates:

1. `hand`: This template is used for hand-written samples. It takes scanned PDFs of hand-written text, converts them to PNG images, extracts the text to markdown format, and then applys the pre-assessment according to assignment instruction, rubric, and other necessary context.
2. `canvas`: This template is used for pulling submissions from a Canvas course assignment. It takes the assignment ID and course ID, and then pulls the submissions from Canvas. It then applies the pre-assessment according to assignment instruction, rubric, and other necessary context.

## Usage 

To use this flake, you need to have Nix installed on your system. You can then run the following command to initialize a project using one of the templates (e.g., `hand`):

```sh
mkdir my-assignment && cd my-assignment
nix flake init -t github:francojc/assess-writing#hand # Or use #canvas
```

You can verify that the flake is working by running the following commands: 

```sh
nix flake show
nix flake check
```

Finally, you can build the development environment by running the following command: 

```sh
direnv allow
```

> [!WARNING]
> This assumes that you have [direnv](https://direnv.net/) installed. If you don't have direnv installed, you can run the following command to build the development environment: 
>

```sh
nix develop
```

Once inside the development environment, you can use the main script `scripts/main.sh` to run the processing pipelines.

### Running the Pipeline

The `scripts/main.sh` script orchestrates the workflow. Use `-h` or `--help` to see all options.

**Common Usage:**

*   **Process scanned PDFs (default):**
    ```sh
    scripts/main.sh # Runs convert -> extract -> assess for files in ./submissions
    # OR explicitly
    scripts/main.sh -S
    ```

*   **Process Canvas submissions:**
    ```sh
    # Set required environment variables first (or use .envrc from template)
    export CANVAS_API_KEY="your_key"
    export CANVAS_BASE_URL="https://your.instructure.com"
    # Then run:
    scripts/main.sh -C --course 1234 --assignment 5678 # Runs acquire -> convert -> extract -> assess
    ```

*   **Run specific steps:** Combine flags to run only certain steps.
    ```sh
    # Run only conversion and extraction for scanned PDFs
    scripts/main.sh -S -ce

    # Run only acquisition for Canvas
    scripts/main.sh -C -q --course 1234 --assignment 5678
    ```

## Use of `llm` 

This flake uses the `llm` package to perform the pre-assessment. The `llm` package is a scriptable interface to various LLM services (e.g. Anthropic, Gemini, Ollama, OpenAI, etc.). You will need to set up your own API keys and select your default model to use prior to running the pre-assessment. Consult [the `llm` documentation](https://llm.datasette.io/) for more information on how to do this.


## Structure 

The structure of this flake repository (containing the templates and core scripts) is as follows:

```plaintext
.
├── flake.nix         # Main flake definition, sets up dev environment
├── README.md         # This file
├── scripts/          # Core processing scripts
│   ├── main.sh       # Main entry point/dispatcher script
│   ├── steps/        # Atomic processing step scripts
│   │   ├── acquire_canvas_submissions.sh
│   │   ├── assess_assignment_text.sh
│   │   ├── convert_submission_file.sh
│   │   └── extract_text_from_image.sh
│   └── workflows/    # Scripts defining the sequence for each source type
│       ├── run_canvas.sh
│       └── run_scanned.sh
└── templates/        # Project templates
    ├── canvas/       # Template for Canvas workflow
    │   ├── docs/     # Placeholder for assignment/rubric markdown
    │   ├── flake.nix # Template-specific flake part (if needed)
    │   └── ...
    └── hand/         # Template for scanned/hand-written workflow
        ├── docs/     # Placeholder for assignment/rubric markdown
        ├── flake.nix # Template-specific flake part (if needed)
        └── ...
```

When you initialize a project using `nix flake init -t ...`, the contents of the chosen template (`canvas` or `hand`) will be copied into your new project directory. The core scripts from the `scripts/` directory are made available within the Nix development environment provided by the `flake.nix`.

## Dependencies

The Nix flake (`flake.nix`) manages all necessary dependencies, including:
- `bash`, `curl`, `jq` (Core utilities)
- `imagemagick`, `pandoc` (File conversion)
- `python3` with the `llm` package and related plugins (e.g., `llm-gemini`, `llm-openai`, `llm-anthropic`, `llm-ollama`) for text extraction and assessment.

## TODOS

- [ ] Add capability to retrieve assignment instructions and rubric from Canvas
- [ ] Add steps to review and finalize the assessment
- [ ] Add functionality to send the final assessment back to Canvas

