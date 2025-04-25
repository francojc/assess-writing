#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Orchestrates Writing assessment processing pipeline within an initialized project.

Options:
  -C, --convert   Run PDF to PNG conversion only
  -E, --extract   Run text extraction from PNGs only
  -A, --assess    Run assignment assessment only
  -h, --help      Show this help message

Run multiple stages by combining flags (e.g., -CE).
By default (no flags), runs all stages (-CEA).

Expects to be run inside a project initialized with the Writing template:
- pdfs/ directory for input PDFs
- docs/ directory with rubric.md and assignment_description.md

Example:
  writing-main         # Run all stages
  writing-main -C      # Run only conversion

EOF
}

# Initialize flags
convert_flag=false
extract_flag=false
assess_flag=false
run_all=false

# Determine execution mode
if [ $# -eq 0 ]; then
  run_all=true
  convert_flag=true
  extract_flag=true
  assess_flag=true
else
  while getopts ":CEAh-" opt; do
    case ${opt} in
      C ) convert_flag=true ;;
      E ) extract_flag=true ;;
      A ) assess_flag=true ;;
      h ) usage; exit 0 ;;
      - ) # Handle long options if needed, or ignore
          case "${OPTARG}" in
              help) usage; exit 0 ;;
              convert) convert_flag=true ;;
              extract) extract_flag=true ;;
              assess) assess_flag=true ;;
              *) echo "Invalid long option --$OPTARG" >&2; usage; exit 1 ;;
          esac ;;
      \? ) echo "Invalid short option: -$OPTARG" >&2; usage; exit 1 ;;
      : ) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
    esac
  done
  shift $((OPTIND -1))

  # If specific flags were given, don't assume run_all
  if [ "$convert_flag" = true ] || [ "$extract_flag" = true ] || [ "$assess_flag" = true ]; then
      run_all=false
  else
      # If flags were parsed but none were set (e.g., only invalid options entered before corrected)
      # Or if only -h was passed initially. Recheck if any valid processing flag is set.
      if [ $# -ne 0 ] || { [ "$convert_flag" = false ] && [ "$extract_flag" = false ] && [ "$assess_flag" = false ]; }; then
        echo "No processing stage selected." >&2
        usage
        exit 1
      fi
  fi
fi

# --- Project Structure and Input Checks ---
pdf_dir="./pdfs"
png_dir="./pngs"
text_dir="./text"
assessment_dir="./assessment"
docs_dir="./docs"

# Check for essential project directories and files
if [ ! -d "$pdf_dir" ] || [ ! -d "$docs_dir" ] || \
   [ ! -f "$docs_dir/rubric.md" ] || \
   [ ! -f "$docs_dir/assignment.md" ]; then
  echo "Error: Project structure incomplete or not run from project root." >&2
  echo "Expected: ./pdfs/, ./docs/, ./docs/rubric.md, ./docs/assignment.md" >&2
  echo "Initialize the project using: nix flake init -t <writing-tools-flake-url>#project" >&2
  exit 1
fi

# Ensure output directories exist (template might not create all)
mkdir -p "$png_dir" "$text_dir" "$assessment_dir"

# Check for PDFs if any processing stage is requested
processing_requested=false
if [ "$convert_flag" = true ] || [ "$extract_flag" = true ] || [ "$assess_flag" = true ]; then
    processing_requested=true
fi

pdf_files_exist=$(ls -A "$pdf_dir"/*.pdf 2>/dev/null)

if [ "$processing_requested" = true ] && [ -z "$pdf_files_exist" ]; then
    echo "No PDF files found in '$pdf_dir'."
    echo "Please add student submission PDF files to '$pdf_dir'."
    # Exit cleanly if no PDFs are present; nothing to process.
    exit 0
fi

# Exit if only input check was needed (e.g., ran with no flags, no PDFs found)
if [ "$processing_requested" = false ]; then
    echo "Project structure looks okay. Add PDFs to '$pdf_dir' and run again to process."
    exit 0
fi

# --- Processing Stages ---

# 1. Convert PDFs to PNGs
if [ "$convert_flag" = true ]; then
  echo "--- Running PDF to PNG Conversion ---"
  processed_count=0
  error_count=0
  shopt -s nullglob # Prevent loop from running if no files match
  for pdf_file in "$pdf_dir"/*.pdf; do
    echo "Converting: '$pdf_file'"
    # Call the Nix-packaged script (assumes it's in PATH via devShell)
    do-convert.sh "$pdf_file"
    if ! do-convert.sh "$pdf_file"; then
      echo "Error converting '$pdf_file'." >&2
      ((error_count++))
    else
      ((processed_count++))
    fi
  done
  shopt -u nullglob # Turn off nullglob
  echo "Conversion Summary: $processed_count converted, $error_count errors."
  if [ $error_count -gt 0 ]; then
      echo "Halting due to conversion errors." >&2
      # Decide if you want to exit on error, currently we don't exit the main script
      # exit 1
  fi
   # Check if any PNGs were actually created before proceeding
   if [ "$extract_flag" = true ] && [ -z "$(ls -A "$png_dir"/*.png 2>/dev/null)" ]; then
       echo "No PNG files found or created in '$png_dir'. Cannot proceed with extraction." >&2
       extract_flag=false # Skip next step
       assess_flag=false  # Skip assessment too
   fi
else
   echo "--- Skipping PDF to PNG Conversion ---"
fi


# 2. Extract Text from PNGs
if [ "$extract_flag" = true ]; then
  echo "--- Running Text Extraction ---"
  processed_count=0
  error_count=0
  shopt -s nullglob
  for png_file in "$png_dir"/*.png; do
    echo "Extracting text from: '$png_file'"
    do-extract.sh "$png_file"
    if do-extract.sh "$png_file"; then
      echo "Error extracting text from '$png_file'." >&2
       ((error_count++))
    else
        ((processed_count++))
    fi
  done
  shopt -u nullglob
  echo "Extraction Summary: $processed_count extracted, $error_count errors."
   if [ $error_count -gt 0 ]; then
      echo "Continuing despite text extraction errors." >&2
       # Decide if you want to exit on error
   fi
   # Check if any text files were actually created before proceeding
   if [ "$assess_flag" = true ] && [ -z "$(ls -A "$text_dir"/*.md 2>/dev/null)" ]; then
       echo "No text files found or created in '$text_dir'. Cannot proceed with assessment." >&2
       assess_flag=false # Skip next step
   fi
else
    echo "--- Skipping Text Extraction ---"
fi


# 3. Assess Assignments
if [ "$assess_flag" = true ]; then
  echo "--- Running Assessment ---"
  processed_count=0
  error_count=0
  shopt -s nullglob
  for text_file in "$text_dir"/*.md; do
    echo "Assessing assignment: '$text_file'"
    do-assess.sh "$text_file"
    if do-assess.sh "$text_file"; then
      echo "Error assessing '$text_file'." >&2
       ((error_count++))
    else
        ((processed_count++))
    fi
  done
  shopt -u nullglob
   echo "Assessment Summary: $processed_count assessed, $error_count errors."
else
  echo "--- Skipping Assessment ---"
fi

echo "--- Writing processing finished ---"
exit 0
