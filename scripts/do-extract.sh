#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <input_png_file>

Options:
  -h, --help    Show this help message and exit

Extracts text from PNG images using LLM tool with Gemini 2.0 Flash model.

Requirements:
  - llm command line tool (https://llm.datasette.io/)
  - Input file must be a valid PNG

Example:
  $0 scanned_page.png

EOF
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

# Check if llm is installed
if ! command -v llm &> /dev/null; then
  echo "Error: llm is not installed. Please install it with \`pipx install llm\` to use this script."
  exit 1
fi

# Check if an input file is provided
if [ -z "$1" ]; then
  usage
  exit 1
fi

input_png="$1"

# Check if the input file exists and is a PNG file
if [[ ! -f "$input_png" || ! "$input_png" =~ \.png$ ]]; then
  echo "Error: Input file '$input_png' is not a valid PNG file."
  exit 1
fi

# Create the text directory if it doesn't exist
mkdir -p text

# Extract the filename without extension
filename=$(basename "$input_png" .png)
output_txt="text/${filename}.md"

# Extract the text from the image using llm and save it to a markdown file in the text/ directory
llm "Extract the text from this image and format the output as markdown. Note: Do not include the markdown code fences." -a "$input_png" > "$output_txt"

echo "Successfully extracted text from '$input_png' and saved it to '$output_txt'."
