#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") <input_file>

Converts various file types:
  - PDF (.pdf)      -> PNG (.png) into ./images/ (requires imagemagick)
  - DOCX (.docx)    -> Markdown (.md) into ./text/ (requires pandoc)
  - HTML (.html)    -> Markdown (.md) into ./text/ (requires pandoc)

Outputs are named based on the input filename.

Example:
  $(basename "$0") my_document.pdf
  $(basename "$0") report.docx
  $(basename "$0") submission.html
EOF
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

# Check if an input file is provided
if [ -z "$1" ]; then
  echo "Error: Input file not specified." >&2
  usage
  exit 1
fi

input_file="$1"

# Check if the input file exists
if [[ ! -f "$input_file" ]]; then
  echo "Error: Input file '$input_file' not found." >&2
  exit 1
fi

# Extract the filename and extension
filename=$(basename "$input_file")
extension="${filename##*.}"
base_name="${filename%.*}"

# Image output directory
image_dir="./images"
# Text output directory
text_dir="./text"

# Determine file type and process accordingly
case "${extension,,}" in # Convert extension to lowercase for comparison
  pdf)
    # Check for imagemagick
    if ! command -v magick &> /dev/null; then
      echo "Error: imagemagick ('magick' command) not found, required for PDF conversion." >&2
      exit 1
    fi
    mkdir -p "$image_dir"
    output_png="$image_dir/${base_name}.png"
    echo "Converting PDF to PNG: '$input_file' -> '$output_png'"
    if magick -density 300 "$input_file" -append "$output_png"; then
      echo "Successfully converted '$filename' to '$output_png'"
    else
      echo "Error converting '$filename' to PNG." >&2
      exit 1 # Exit script on conversion error
    fi
    ;;
  docx)
    # Check for pandoc
    if ! command -v pandoc &> /dev/null; then
      echo "Error: pandoc not found, required for DOCX conversion." >&2
      exit 1
    fi
    mkdir -p "$text_dir"
    output_md="$text_dir/${base_name}.md"
    echo "Converting DOCX to Markdown: '$input_file' -> '$output_md'"
    if pandoc "$input_file" -o "$output_md"; then
       echo "Successfully converted '$filename' to '$output_md'"
    else
       echo "Error converting '$filename' to Markdown." >&2
       exit 1 # Exit script on conversion error
    fi
    ;;
  html)
    # Check for pandoc
    if ! command -v pandoc &> /dev/null; then
      echo "Error: pandoc not found, required for HTML conversion." >&2
      exit 1
    fi
    mkdir -p "$text_dir"
    output_md="$text_dir/${base_name}.md"
    echo "Converting HTML to Markdown: '$input_file' -> '$output_md'"
    # Explicitly specify from HTML to markdown
    if pandoc "$input_file" -f html -t markdown -o "$output_md"; then
       echo "Successfully converted '$filename' to '$output_md'"
    else
       echo "Error converting '$filename' to Markdown." >&2
       exit 1 # Exit script on conversion error
    fi
    ;;
  *)
    echo "Error: Unsupported file type '$extension' for input file '$filename'." >&2
    echo "Supported types: pdf, docx, html." >&2
    exit 1
    ;;
esac
