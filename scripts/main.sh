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

  # Check for Canvas input if processing is requested
  if [ "$convert_flag" = true ] && [ -z "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
    echo "No Canvas submissions found in '$sub_dir'."
    echo "Running Canvas acquisition step..."
    # Acquire Canvas submissions
    if ! do-acquire.sh; then
      echo "Error acquiring Canvas submissions." >&2
      exit 1
    fi

    # Check again after acquisition
    if [ -z "$(ls -A "$sub_dir" 2>/dev/null)" ]; then
      echo "No Canvas submissions were acquired. Cannot proceed." >&2
      exit 1
    fi
  fi
else
  # Original scanned PDF checks
  mkdir -p "$sub_dir"

  # Check for PDFs if conversion is requested
  if [ "$convert_flag" = true ]; then
    pdf_files_exist=$(ls -A "$sub_dir"/*.pdf 2>/dev/null)

    if [ -z "$pdf_files_exist" ]; then
      echo "No PDF files found in '$sub_dir'."
      echo "Please add student submission PDF files to '$sub_dir'."
      exit 0
    fi
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
# WARN: Need to update. Canvas files may include other formats (docx, HTML, etc.)
if [ "$convert_flag" = true ]; then
  echo "--- Running Conversion ---"
  processed_count=0
  error_count=0

  if [ "$workflow_source" = "canvas" ]; then
    echo "Converting Canvas submissions..."
    shopt -s nullglob
    for canvas_file in "$sub_dir"/*; do
      echo "Converting: '$(basename "$canvas_file")'"
      if ! do-convert.sh --source canvas "$canvas_file"; then
        echo "Error converting '$(basename "$canvas_file")'." >&2
        ((error_count++))
      else
        ((processed_count++))
      fi
    done
    shopt -u nullglob
  else
    echo "Converting scanned PDFs..."
    shopt -s nullglob
    for pdf_file in "$sub_dir"/*.pdf; do
      echo "Converting: '$(basename "$pdf_file")'"
      if ! do-convert.sh --source scanned "$pdf_file"; then
        echo "Error converting '$(basename "$pdf_file")'." >&2
        ((error_count++))
      else
        ((processed_count++))
      fi
    done
    shopt -u nullglob
  fi

  echo "Conversion Summary: $processed_count converted, $error_count errors."
  if [ $error_count -gt 0 ]; then
    echo "Warning: Some conversion errors occurred." >&2
  fi

  # Check if any files for next step were created
  if [ "$extract_flag" = true ]; then
    if [ "$workflow_source" = "canvas" ]; then
      # For canvas workflow, we may already have text files ready for assessment
      if [ -z "$(ls -A "$image_dir"/*.png 2>/dev/null)" ] && [ -z "$(ls -A "$text_dir"/*.md 2>/dev/null)" ]; then
        echo "No files found for processing after conversion. Cannot proceed." >&2
        extract_flag=false
        assess_flag=false
      fi
    else
      # For scanned workflow, we need PNGs
      if [ -z "$(ls -A "$image_dir"/*.png 2>/dev/null)" ]; then
        echo "No PNG files found or created in '$image_dir'. Cannot proceed with extraction." >&2
        extract_flag=false
        assess_flag=false
      fi
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
    if ! do-extract.sh --source "$workflow_source" "$png_file"; then
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
    if ! do-assess.sh --source "$workflow_source" "$text_file"; then
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

