# Assess Writing

## Description

This flake provides a simple way to pre-process writing samples for assessment using a command-line interface. The default template provides the scaffolding for assignment instructions, rubrics, and other necessary context. The flake is designed to be used with Nix and provides a development environment for processing writing samples (either acquired from Canvas or scanned PDFs). The main goal is to facilitate the pre-assessment of writing samples using large language models (LLMs) like OpenAI's GPT-4, Anthropic's Claude, or Google's Gemini. 

## Usage 

To use this flake, you need to have Nix installed on your system. You can then run the following command to initialize a project.

```sh
mkdir my-assignment && cd my-assignment
nix flake init -t github:francojc/assess-writing
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
│   ├── pull.sh       # Pull assignment instructions and rubric from Canvas
│   ├── acquire.sh    # Acquire Canvas submissions
│   ├── prepare.sh    # Prepare files for processing (PDF -> PNG --> MD, DOCX -> MD, etc.)
│   ├── assess.sh     # Run the pre-assessment using llm
└── templates/        # Project templates
    └── default/      # Default template for new projects 
       ├── docs/      # Placeholder for assignment/rubric markdown
       ├── flake.nix  # Template-specific flake part (if needed)
       └── ...
```

Description of the scripts: 

- `acquire.sh`: This script pulls Canvas submissions using the Canvas API. It requires the `CANVAS_API_KEY` and `CANVAS_BASE_URL` environment variables to be set and then the `-c, --course` and `-a, --assignment` flags to specify the course and assignment IDs. It will create a directory for the assignment `./submissions/` and download the submissions into it.
- `prepare.sh`: This script processes the files in the `./submissions/` directory. It converts scanned PDFs to PNG images and extracts text from them into Markdown format and converts DOCX, HTML, or TXT files to Markdown format. The processed files are saved in the `./assignments/` directory.
- `assess.sh`: This script runs the pre-assessment using the `llm` package. It takes the processed files from the `./assignments/` directory and applies the pre-assessment according to the assignment instructions, rubric, and other necessary context. The results are saved in the `./assessments/` directory.

When you initialize a project using `nix flake init -t ...`, the contents of the template will be copied into your new project directory. The core scripts from the `scripts/` directory are made available within the Nix development environment provided by the `flake.nix`.

## Dependencies

The Nix flake (`flake.nix`) manages all necessary dependencies, including:
- `bash`, `curl`, `jq` (Core utilities)
- `imagemagick`, `pandoc` (File conversion)
- `python3` with the `llm` package and related plugins (e.g., `llm-gemini`, `llm-openai`, `llm-anthropic`, `llm-ollama`) for text extraction and assessment.

## TODOS

- [ ] Add capability to retrieve assignment instructions and rubric from Canvas
- [ ] Add steps to review and finalize the assessment
- [ ] Add functionality to send the final assessment back to Canvas
