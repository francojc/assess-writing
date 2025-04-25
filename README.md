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


