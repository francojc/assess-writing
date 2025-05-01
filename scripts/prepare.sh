#!/usr/bin/env bash

# Processes submission files from ./submissions/ directory.
# Converts various formats (PDF, DOCX, HTML, TXT) to Markdown (.md) in ./assignments/.
# Handles PDF by converting to PNG and then llm for text extraction (using a vision model).

set -uo pipefail # Exit on unset variables and pipeline errors

usage() {
  cat <<EOF
Usage: $(basename "$0")

Processes supported files found in ./submissions/ and outputs plain
text Markdown files to ./assignments/. Creates ./assignments/ if it
doesn't exist. Intermediate image files from PDF conversion are stored
in ./intermediate_images/ temporarily and cleaned up afterward.

Requires:
  - imagemagick ('magick' command) for PDF conversion.
  - llm (from https://llm.datasette.io/) for text extraction from images.
  - pandoc for DOCX and HTML conversion.

Example:
  $(basename "$0") # Processes all files in ./submissions/
EOF
}

# Show help if requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 1
fi

# Check for dependencies
if ! command -v magick &> /dev/null; then
  echo "Error: imagemagick ('magick' command) not found." >&2
  exit 1
fi
if ! command -v llm &> /dev/null; then
  echo "Error: llm not found. Please install it (pip install llm)." >&2
  exit 1
fi
if ! command -v pandoc &> /dev/null; then
  echo "Error: pandoc not found." >&2
  exit 1
fi

# Define directories
submissions_dir="./submissions"
assignments_dir="./assignments"
intermediate_images_dir="./intermediate_images" # Define path for potential cleanup

# Check if submissions directory exists
if [ ! -d "$submissions_dir" ]; then
  echo "Error: Submissions directory '$submissions_dir' not found." >&2
  exit 1
fi

# Create primary output directory
mkdir -p "$assignments_dir"
# Intermediate directory creation is deferred until a PDF is encountered

echo "Starting preparation of files from '$submissions_dir'..."

processed_count=0
skipped_count=0
error_count=0

# Process each file in the submissions directory
find "$submissions_dir" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' input_file; do
  filename=$(basename "$input_file")
  extension="${filename##*.}"
  base_name="${filename%.*}"
  output_md="$assignments_dir/${base_name}.md"

  echo "Processing '$filename'..."

  case "${extension,,}" in # Convert extension to lowercase
    pdf)
      # Create intermediate directory only if we process a PDF
      mkdir -p "$intermediate_images_dir"
      output_png="$intermediate_images_dir/${base_name}.png"
      echo "  Converting PDF to PNG: '$filename' -> '$output_png'"
      # Combine pages, use high density for OCR
      # Redirect stdin from /dev/null to prevent potential issues
      if ! magick -density 300 "$input_file" -append "$output_png" < /dev/null; then
          echo "  Error converting '$filename' to PNG." >&2
          ((error_count++))
          continue # Skip to next file
      fi

      echo "  Extracting text using llm: '$output_png' -> '$output_md'"
      # Use llm to extract text, redirecting stdin from /dev/null to prevent it consuming the find output
      # Ensure plain markdown output without code fences
      if llm "Extract the text from this image and format the output as plain markdown text. Do not include markdown code block fences like \`\`\`markdown or \`\`\`." -a "$output_png" < /dev/null > "$output_md"; then
          # Check if the output file is empty
          if [[ ! -s "$output_md" ]]; then
              echo "Warning: Text extraction resulted in an empty file for '$output_png'. Check llm output or the image." >&2
              # Decide if this counts as an error or just a processed file with a warning
          fi
          echo "  Successfully prepared '$filename' to '$output_md'."
          ((processed_count++))
      else
          echo "  Error running llm for text extraction on '$output_png'." >&2
          rm -f "$output_md" # Remove potentially empty/corrupt file on error
          ((error_count++))
      fi
      # Optional: Clean up intermediate PNG
      # rm "$output_png"
      ;;
    docx)
      echo "  Converting DOCX to Markdown: '$filename' -> '$output_md'"
      # Convert to plain markdown, ignore images for now
      if ! pandoc "$input_file" -t markdown -o "$output_md"; then
         echo "  Error converting '$filename' to Markdown." >&2
         ((error_count++))
      else
         echo "  Successfully prepared '$filename' to '$output_md'"
         ((processed_count++))
      fi
      ;;
    html)
      echo "  Converting HTML to Markdown: '$filename' -> '$output_md'"
      # Specify input format, disable wrapping
      if ! pandoc "$input_file" -f html -t markdown --wrap=none -o "$output_md"; then
         echo "  Error converting '$filename' to Markdown." >&2
         ((error_count++))
      else
         echo "  Successfully prepared '$filename' to '$output_md'"
         ((processed_count++))
      fi
      ;;
    txt)
      echo "  Copying TXT to Markdown: '$filename' -> '$output_md'"
      if ! cp "$input_file" "$output_md"; then
         echo "  Error copying '$filename' to '$output_md'." >&2
         ((error_count++))
      else
         echo "  Successfully prepared '$filename' to '$output_md'"
         ((processed_count++))
      fi
      ;;
    url | gdoc.url)
      echo "  Skipping URL file: '$filename'"
      ((skipped_count++))
      ;;
    *)
      echo "  Warning: Unsupported file type '$extension' for preparation: '$filename'."
      ((skipped_count++))
      ;;
  esac
done

# Forcefully remove the intermediate image directory and its contents
if [ -d "$intermediate_images_dir" ]; then
    echo "Cleaning up intermediate image directory: $intermediate_images_dir"
    rm -rf "$intermediate_images_dir"
fi

echo "Preparation Summary: $processed_count files prepared, $skipped_count skipped, $error_count errors."

if [ $error_count -gt 0 ]; then
   echo "Warning: Some files failed during preparation." >&2
   exit 1
fi

exit 0
