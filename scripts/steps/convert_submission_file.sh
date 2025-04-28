#!/usr/bin/env bash
# Renamed and moved from original do-convert.sh

usage() {
  cat <<EOF
Usage: $(basename "$0") <input_file>

Converts a single submission file:
  - PDF (.pdf)      -> PNG (.png) into ./images/ (requires imagemagick)
  - DOCX (.docx)    -> Markdown (.md) into ./text/ (requires pandoc)
  - HTML (.html)    -> Markdown (.md) into ./text/ (requires pandoc)

Outputs are named based on the input filename.
Output directories (./images, ./text) are assumed to exist.

Example:
  $(basename "$0") submissions/my_document.pdf
  $(basename "$0") submissions/report.docx
  $(basename "$0") submissions/submission.html
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

# Image output directory (Expected to exist)
image_dir="./images"
# Text output directory (Expected to exist)
text_dir="./text"

# Determine file type and process accordingly
case "${extension,,}" in # Convert extension to lowercase for comparison
  pdf)
    # Check for imagemagick
    if ! command -v magick &> /dev/null; then
      echo "Error: imagemagick ('magick' command) not found, required for PDF conversion." >&2
      exit 1
    fi
    output_png="$image_dir/${base_name}.png"
    echo "  Converting PDF to PNG: '$filename' -> '$output_png'"
    # Use -append to handle multi-page PDFs into a single tall PNG
    if magick -density 300 "$input_file" -append "$output_png"; then
      echo "  Successfully converted '$filename' to '$output_png'"
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
    output_md="$text_dir/${base_name}.md"
    echo "  Converting DOCX to Markdown: '$filename' -> '$output_md'"
    if pandoc --extract-media="$image_dir" "$input_file" -o "$output_md"; then # Extract images if possible
       echo "  Successfully converted '$filename' to '$output_md'"
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
    output_md="$text_dir/${base_name}.md"
    echo "  Converting HTML to Markdown: '$filename' -> '$output_md'"
    # Explicitly specify from HTML to markdown
    # Add --wrap=none to prevent line wrapping issues if text is intended to be processed later
    if pandoc "$input_file" -f html -t markdown --wrap=none -o "$output_md"; then
       echo "  Successfully converted '$filename' to '$output_md'"
    else
       echo "Error converting '$filename' to Markdown." >&2
       exit 1 # Exit script on conversion error
    fi
    ;;
  url)
    echo "  Skipping conversion for .url file: '$filename'"
    ;;
  gdoc.url)
     echo "  Skipping conversion for .gdoc.url file: '$filename'"
     ;;
  *)
    echo "Warning: Unsupported file type '$extension' for conversion: '$filename'." >&2
    # Don't exit with error for unsupported, just warn and continue workflow
    ;;
esac

exit 0 # Success for this file (or skipped type)
