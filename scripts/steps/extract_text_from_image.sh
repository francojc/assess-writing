#!/usr/bin/env bash
# Renamed and moved from original do-extract.sh

usage() {
  cat <<EOF
Usage: $(basename "$0") <input_png_file>

Extracts text from a single PNG image using LLM tool.
Output saved as a markdown file in ./text/ directory.

Requirements:
  - llm command line tool (https://llm.datasette.io/)
  - Input file must be a valid PNG
  - ./text directory must exist

Example:
  $(basename "$0") images/scanned_page.png

EOF
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

# Check if llm is installed
if ! command -v llm &> /dev/null; then
  echo "Error: llm is not installed. Please install it to use this script." >&2
  exit 1
fi

# Check if an input file is provided
if [ -z "$1" ]; then
  echo "Error: Input PNG file not specified." >&2
  usage
  exit 1
fi

input_png="$1"

# Check if the input file exists and is a PNG file
if [[ ! -f "$input_png" || ! "$input_png" == *.png ]]; then
  echo "Error: Input file '$input_png' is not a valid PNG file or does not exist." >&2
  exit 1
fi

# Text output directory (Expected to exist)
text_dir="./text"

# Extract the filename without extension
filename=$(basename "$input_png" .png)
# Ensure output uses .md extension consistently
output_file="$text_dir/${filename}.md"

echo "  Extracting text from image: '$(basename "$input_png")' -> '$output_file'"

# Extract the text from the image using llm and save it to a markdown file in the text/ directory
# Ensure the prompt is clear about not wanting markdown code fences
if llm "Extract the text from this image and format the output as plain markdown text. Do not include markdown code block fences like \`\`\`markdown or \`\`\`." -a "$input_png" > "$output_file"; then
  # Check if the output file is empty, which might indicate an llm error or empty extraction
  if [[ ! -s "$output_file" ]]; then
      echo "Warning: Text extraction resulted in an empty file for '$input_png'. Check llm output or the image." >&2
      # Keep the file, but warn. Depending on workflow, might want to `rm "$output_file"`
  else
      echo "  Successfully extracted text from '$(basename "$input_png")' to '$output_file'."
  fi
else
    echo "Error running llm for text extraction on '$input_png'." >&2
    # Remove potentially empty/corrupt file on error
    rm -f "$output_file"
    exit 1
fi


exit 0 # Success
