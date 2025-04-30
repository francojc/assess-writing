#!/usr/bin/env bash
# Processes submission files from ./submissions/ directory.
# Converts various formats (PDF, DOCX, HTML, TXT) to Markdown (.md) in ./assignments/.
# Handles PDF by converting to PNG and then using OCR (tesseract).

set -uo pipefail # Exit on unset variables and pipeline errors

usage() {
  cat <<EOF
Usage: $(basename "$0")

Processes supported files found in ./submissions/ and outputs plain
text Markdown files to ./assignments/. Creates ./assignments/ if it
doesn't exist.

Requires:
  - imagemagick ('magick' command) for PDF conversion.
  - tesseract for OCR (PDF -> PNG -> Text).
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
if ! command -v tesseract &> /dev/null; then
  echo "Error: tesseract not found." >&2
  exit 1
fi
if ! command -v pandoc &> /dev/null; then
  echo "Error: pandoc not found." >&2
  exit 1
fi

# Define directories
submissions_dir="./submissions"
assignments_dir="./assignments"
intermediate_images_dir="./intermediate_images" # Optional: For temporary PNGs

# Check if submissions directory exists
if [ ! -d "$submissions_dir" ]; then
  echo "Error: Submissions directory '$submissions_dir' not found." >&2
  exit 1
fi

# Create output directories
mkdir -p "$assignments_dir"
mkdir -p "$intermediate_images_dir"

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
      output_png="$intermediate_images_dir/${base_name}.png"
      echo "  Converting PDF to PNG: '$filename' -> '$output_png'"
      # Combine pages, use high density for OCR
      if ! magick -density 300 "$input_file" -append "$output_png"; then
          echo "  Error converting '$filename' to PNG." >&2
          ((error_count++))
          continue # Skip to next file
      fi

      echo "  Extracting text using OCR (tesseract): '$output_png' -> '$output_md'"
      if ! tesseract "$output_png" stdout > "$output_md"; then
          echo "  Error extracting text from '$output_png'." >&2
          ((error_count++))
      else
          echo "  Successfully prepared '$filename' to '$output_md'."
          ((processed_count++))
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

# Optional: Clean up intermediate image directory if it's empty or after run
# rmdir "$intermediate_images_dir" 2>/dev/null || true

echo "Preparation Summary: $processed_count files prepared, $skipped_count skipped, $error_count errors."

if [ $error_count -gt 0 ]; then
   echo "Warning: Some files failed during preparation." >&2
   exit 1
fi

exit 0
