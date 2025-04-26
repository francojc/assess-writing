#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [SOURCE] [OPTIONS]

Orchestrates Writing assessment processing pipeline within an initialized project.

  -h, --help      Show this help message

Source (Select one, default is --scanned):
  -S, --scanned   Process scanned PDFs
  -C, --canvas    Process submissions from Canvas

Options (Combine to run multiple steps, default is all steps for the source):
  -q, --acquire   Run Canvas acquisition step only (requires -C/--canvas)
  -c, --convert   Run conversion step only
  -e, --extract   Run text extraction step only
  -a, --assess    Run assignment assessment only

Source dependent options:
  When using '-C, --canvas', these are required:
    --course COURSE_ID          Canvas Course ID
    --assignment ASSIGNMENT_ID  Canvas Assignment ID

Run multiple stages by combining flags (e.g., -ce).
By default (no source/options flags), runs all stages for scanned PDFs (-S -cea).

Examples:
  $(basename "$0")                      # Run all stages with scanned PDFs (-S implicitly)
  $(basename "$0") -C --course 1 --assignment 2  # Run all stages with Canvas submissions
  $(basename "$0") -S -c                # Run only conversion on scanned PDFs
  $(basename "$0") -C -ea --course 1 --assignment 2 # Run extraction and assessment on Canvas submissions

EOF
}

# Initialize flags
acquire_flag=false
convert_flag=false
extract_flag=false
assess_flag=false
run_all=false

# Canvas specific variables
course_id_val=""
assignment_id_val=""
# Default to scanned workflow
workflow_source="scanned"

# Parse command line arguments
while (( $# > 0 )); do
  case "$1" in
    -S|--scanned)
      workflow_source="scanned"
      shift
      ;;
    -C|--canvas)
      workflow_source="canvas"
      shift
      ;;
    -q|--acquire)
      acquire_flag=true
      shift
      ;;
    -c|--convert)
      convert_flag=true
      shift
      ;;
    -e|--extract)
      extract_flag=true
      shift
      ;;
    -a|--assess)
      assess_flag=true
      shift
      ;;
    --course)
      # Check if the next argument is empty or starts with a hyphen
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: --course requires a value." >&2; usage; exit 1;
      fi
      course_id_val="$2"
      shift 2
      ;;
    --assignment)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "Error: --assignment requires a value." >&2; usage; exit 1;
      fi
      assignment_id_val="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Determine execution mode if no specific flags provided
if [ "$acquire_flag" = false ] && [ "$convert_flag" = false ] && [ "$extract_flag" = false ] && [ "$assess_flag" = false ]; then
  run_all=true
  acquire_flag=true
  convert_flag=true
  extract_flag=true
  assess_flag=true
fi

# Validate Canvas flags if canvas workflow is selected
if [[ "$workflow_source" == "canvas" && \
      ( "$acquire_flag" = true || "$convert_flag" = true || "$extract_flag" = true || "$assess_flag" = true || "$run_all" = true ) ]]; then
   if [[ -z "$course_id_val" || -z "$assignment_id_val" ]]; then
     echo "Error: --course and --assignment flags are required for the 'canvas' workflow." >&2
     usage
     exit 1
   fi
fi
# --- Project Structure and Input Checks ---
sub_dir="./submissions"
image_dir="./images"
text_dir="./text"
assessment_dir="./assessment"
docs_dir="./docs"

# Check for essential project directories and files
if [ ! -d "$docs_dir" ] || \
   [ ! -f "$docs_dir/rubric.md" ] || \
   [ ! -f "$docs_dir/assignment.md" ]; then
  echo "Error: Project structure incomplete or not run from project root." >&2
  echo "Expected: ./docs/, ./docs/rubric.md, ./docs/assignment.md" >&2
  echo "Initialize the project using: nix flake init -t <writing-tools-flake-url>#project" >&2
  exit 1
fi

# Ensure output directories exist
mkdir -p "$image_dir" "$text_dir" "$assessment_dir"

# Workflow-specific checks and setup
if [ "$workflow_source" = "canvas" ]; then
  mkdir -p "$sub_dir"
else
  # Original scanned PDF checks
  mkdir -p "$sub_dir"
fi

# Check for input files in submissions if conversion is requested
if [ "$convert_flag" = true ] && [ -z "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
  if [ "$workflow_source" = "canvas" ]; then
    echo "No submissions found in '$sub_dir'. Acquisition step needed first (use -q or run all)." >&2
    exit 1 # Canvas needs acquisition first usually
  else
    echo "No submission files found in '$sub_dir'." >&2
    echo "Please add student submission files (e.g., PDFs, DOCX) to '$sub_dir'." >&2
    exit 1
  fi
fi

# --- Processing Stages ---

# 0. Acquisition step (Canvas submissions)
if [ "$acquire_flag" = true ]; then
  echo "--- Running Acquisition ---"
  if [ "$workflow_source" = "canvas" ]; then
    echo "Acquiring Canvas submissions..."
    export COURSE_ID="$course_id_val"
    export ASSIGNMENT_ID="$assignment_id_val"
    if ! do-acquire.sh; then
      echo "Error acquiring Canvas submissions." >&2
      exit 1
    fi
    echo "Acquisition complete."
  else
    echo "Acquisition step is only applicable to the 'canvas' workflow. Skipping."
  fi
else
  echo "--- Skipping Acquisition ---"
fi


# 1. Conversion step (PDFs/Canvas files to PNGs/Markdown)
if [ "$convert_flag" = true ]; then
  echo "--- Running Conversion ---"
  processed_count=0
  error_count=0

  echo "Converting submissions in '$sub_dir'..."
  shopt -s nullglob
  for input_file in "$sub_dir"/*; do
    # Skip directories if any exist
    if [ -d "$input_file" ]; then
      continue
    fi
    echo "Converting: '$(basename "$input_file")'"
    # Call do-convert.sh without the --source flag
    if ! do-convert.sh "$input_file"; then
      echo "Error converting '$(basename "$input_file")'." >&2
      ((error_count++))
    else
      ((processed_count++))
    fi
  done
  shopt -u nullglob

  echo "Conversion Summary: $processed_count converted, $error_count errors."
  if [ $error_count -gt 0 ]; then
    echo "Warning: Some conversion errors occurred." >&2
  fi

  # Check if any processable files (PNG or MD) were created for subsequent steps
  if [ "$extract_flag" = true ]; then
    if [ -z "$(ls -A "$image_dir"/*.png 2>/dev/null)" ] && [ -z "$(ls -A "$text_dir"/*.md 2>/dev/null)" ]; then
        echo "No processable files (PNGs in $image_dir or MDs in $text_dir) found after conversion." >&2
        echo "Cannot proceed with extraction or assessment." >&2
      extract_flag=false
      assess_flag=false
    fi
  fi
else
  echo "--- Skipping Conversion ---"
fi

# 2. Extract Text (from PNGs if needed)
if [ "$extract_flag" = true ]; then
  echo "--- Running Text Extraction ---"
  processed_count=0
  error_count=0

  # For Canvas workflow, we might already have text files from conversion
  # So extraction might only be needed for certain file types
  if [ "$workflow_source" = "canvas" ]; then
    echo "Extracting text from Canvas submissions (if needed)..."
  else
    echo "Extracting text from scanned PNGs..."
  fi

  shopt -s nullglob
  for png_file in "$image_dir"/*.png; do
    echo "Extracting text from: '$(basename "$png_file")'"
    if ! do-extract.sh "$png_file"; then
      echo "Error extracting text from '$(basename "$png_file")'." >&2
      ((error_count++))
    else
      ((processed_count++))
    fi
  done
  shopt -u nullglob

  echo "Extraction Summary: $processed_count extracted, $error_count errors."

  # Check if any text files were actually created before proceeding
  if [ "$assess_flag" = true ] && [ -z "$(ls -A "$text_dir"/*.md 2>/dev/null)" ]; then
    echo "No text files found or created in '$text_dir'. Cannot proceed with assessment." >&2
    assess_flag=false
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
    echo "Assessing assignment: '$(basename "$text_file")'"
    if ! do-assess.sh "$text_file"; then
      echo "Error assessing '$(basename "$text_file")'." >&2
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

