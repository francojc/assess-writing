# Assess writing 

## Description 

This flake provides a simple way to pre-process writing samples for assessment. The templates available are: 

1. `hand`: This template is used for hand-written samples. It takes scanned PDFs of hand-written text, converts them to PNG images, extracts the text to markdown format, and then applys the pre-assessment according to assignment instruction, rubric, and other necessary context.
2. `canvas`: This template is used for pulling submissions from a Canvas course assignment. It takes the assignment ID and course ID, and then pulls the submissions from Canvas. It then applies the pre-assessment according to assignment instruction, rubric, and other necessary context.

## Usage 

To use this flake, you need to have Nix installed on your system. You can then run the following command to retreive the (`hand`) flake:

```sh
mkdir assignment; cd assignment;
nix flake init -t github:francojc/assess-writing#hand
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

## Use of `llm` 

This flake uses the `llm` package to perform the pre-assessment. The `llm` package is a scriptable interface to various LLM services (e.g. Anthropic, Gemini, Ollama, OpenAI, etc.). You will need to set up your own API keys and select your default model to use prior to running the pre-assessment. Consult [the `llm` documentation](https://llm.datasette.io/) for more information on how to do this.


## Structure 

The structure of this resource is as follows: 

```sh 

├── flake.nix
├── README.md
├── scripts
│   ├── do-assess.sh
│   ├── do-convert.sh
│   ├── do-extract.sh
│   └── main.sh
└── templates
    ├── canvas
    │   ├── docs
    │   └── flake.nix
    └── hand
        ├── docs
        ├── flake.nix
        └── pdfs
```

# Restructuring notes

To improve scalability and maintainability, the scripts in `./scripts/` could be restructured as follows:

1.  **Isolate Workflow Logic:** Create separate scripts for each distinct workflow (`canvas`, `scanned`).
2.  **Refine Step Scripts:** Ensure each processing script (`convert`, `extract`, `assess`) performs a single, focused task.
3.  **Simplify `main.sh`:** Refactor `main.sh` to act primarily as a dispatcher, identifying the workflow and calling the appropriate workflow script.
4.  **Organize Scripts:** Use subdirectories for clarity.

**Proposed Structure:**

```
scripts/
├── main.sh              # Main entry point/dispatcher
|
├── common/              # Utility scripts or functions (optional)
│   └── ...
|
├── steps/               # Atomic processing step scripts
│   ├── acquire_canvas.sh
│   ├── convert_submission.sh
│   ├── extract_text.sh
│   └── assess_writing.sh
|
└── workflows/           # Scripts defining the sequence for each source type
    ├── run_canvas.sh
    └── run_scanned.sh
```

**Benefits:**

*   **Scalability:** Easier to add new sources (workflows) or processing steps without modifying `main.sh` extensively.
*   **Maintainability:** Logic for each workflow is contained within its own script. Step scripts are simpler and potentially reusable.
*   **Clarity:** Directory structure clearly separates concerns.

